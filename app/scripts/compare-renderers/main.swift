// Spec 006 M1: renders the same fixed uniforms through the page's GLSL (in WebKit) and through
// snuffler.metal, and compares the raw premultiplied pixels.
// Prints the difference per case and writes pictures: WebGL | Metal | difference ×16.
// Not part of the app (it needs WebKit). Goes away with the page in M5. Build and run from app/:
//   swiftc -O -swift-version 5 scripts/compare-renderers/main.swift Sources/Hangabouts/SnufflerUniforms.swift Sources/Hangabouts/SnufflerView.swift -o /tmp/compare-renderers
//   /tmp/compare-renderers Resources/snuffler-hanging.html Resources/snuffler.metal /tmp/compare-out
import AppKit
import WebKit
import Metal
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let html = try! String(contentsOfFile: args[1], encoding: .utf8)
let metalSource = try! String(contentsOfFile: args[2], encoding: .utf8)
let outDir = URL(fileURLWithPath: args[3])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let open = html.range(of: "<script id=\"fs\" type=\"x-shader/x-fragment\">")!
let close = html.range(of: "</script>", range: open.upperBound..<html.endIndex)!
let glsl = String(html[open.upperBound..<close.lowerBound])

let names = ["uYaw","uSwing","uSignSwing","uSignYaw","uBlink","uKick","uTail","uSniff","uFail","uBreathe","uRaiseR","uRaiseL","uShakeR","uShakeL","uTired","uBody","uGrip"]
let paths: [WritableKeyPath<SnufflerUniforms, Float>] = [\.uYaw,\.uSwing,\.uSignSwing,\.uSignYaw,\.uBlink,\.uKick,\.uTail,\.uSniff,\.uFail,\.uBreathe,\.uRaiseR,\.uRaiseL,\.uShakeR,\.uShakeL,\.uTired,\.uBody,\.uGrip]

struct Case { let name: String; let set: [String: Float] }
var cases: [Case] = []
for (pose, f) in [("needs", Float(0)), ("failed", Float(1))] {
    for yaw in [Float(-1.45), 0, 0.95, 1.45] { cases.append(Case(name: "\(pose)-yaw\(yaw)", set: ["uFail": f, "uYaw": yaw])) }
}
cases.append(Case(name: "blink1", set: ["uBlink": 1]))
cases.append(Case(name: "kick0.5", set: ["uKick": 0.5]))
cases.append(Case(name: "tired1", set: ["uTired": 1]))
cases.append(Case(name: "everything", set: ["uYaw": 0.4, "uSwing": 0.2, "uBody": -0.15, "uSignSwing": 0.3, "uSignYaw": -0.4, "uBlink": 0.5, "uKick": -0.3,
                                             "uTail": 0.3, "uSniff": 0.7, "uBreathe": 0.012, "uRaiseR": 0.6, "uRaiseL": 0.8, "uShakeR": 0.5, "uShakeL": -0.5,
                                             "uTired": 0.5, "uGrip": -0.14]))
let sizes = [("35", 284, 275), ("100", 540, 524)]

// ---------- WebGL side ----------
let harness = """
<!doctype html><canvas id="gl"></canvas><script id="fs" type="x-shader/x-fragment">\(glsl)</script><script>
const canvas = document.getElementById('gl');
const gl = canvas.getContext('webgl', { premultipliedAlpha: true, alpha: true, antialias: false, preserveDrawingBuffer: true });
const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
const p = gl.createProgram();
gl.attachShader(p, sh(gl.VERTEX_SHADER, 'attribute vec2 a; void main(){ gl_Position = vec4(a, 0., 1.); }'));
gl.attachShader(p, sh(gl.FRAGMENT_SHADER, document.getElementById('fs').textContent));
gl.linkProgram(p); gl.useProgram(p);
gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, 1,1]), gl.STATIC_DRAW);
const loc = gl.getAttribLocation(p, 'a'); gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
function render(w, h, u){
  canvas.width = w; canvas.height = h; gl.viewport(0, 0, w, h);
  gl.uniform2f(gl.getUniformLocation(p, 'uRes'), w, h);
  for (const k in u) gl.uniform1f(gl.getUniformLocation(p, k), u[k]);
  gl.clearColor(0,0,0,0); gl.clear(gl.COLOR_BUFFER_BIT); gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  const px = new Uint8Array(w*h*4); gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, px);
  let s = ''; for (let i = 0; i < px.length; i += 8192) s += String.fromCharCode.apply(null, px.subarray(i, i + 8192));
  return gl.getParameter(gl.VERSION) + '|' + btoa(s);
}
</script>
"""

final class Nav: NSObject, WKNavigationDelegate {
    var done = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done = true }
}
let app = NSApplication.shared
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
let nav = Nav(); web.navigationDelegate = nav
web.loadHTMLString(harness, baseURL: nil)
func spin(_ cond: () -> Bool) { while !cond() { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) } }
spin { nav.done }

var glVersion = ""
/// RGBA premultiplied, top row first.
func webgl(_ w: Int, _ h: Int, _ u: SnufflerUniforms) -> [UInt8] {
    let obj = zip(names, paths).map { "\($0): \(u[keyPath: $1])" }.joined(separator: ", ")
    var out: [UInt8]? = nil
    web.evaluateJavaScript("render(\(w), \(h), {\(obj)})") { r, e in
        guard let s = r as? String else { fatalError("WebGL render failed: \(String(describing: e))") }
        let parts = s.split(separator: "|", maxSplits: 1)
        glVersion = String(parts[0])
        let bottomUp = [UInt8](Data(base64Encoded: String(parts[1]))!)
        var top = [UInt8](repeating: 0, count: bottomUp.count)
        for y in 0..<h { top.replaceSubrange(y*w*4..<(y+1)*w*4, with: bottomUp[(h-1-y)*w*4..<(h-y)*w*4]) }
        out = top
    }
    spin { out != nil }
    return out!
}

// ---------- Metal side ----------
let device = MTLCreateSystemDefaultDevice()!
let renderer = try! SnufflerRenderer(device: device, source: metalSource)
print(String(format: "Metal: %@, shader compile + link %.0f ms", device.name, renderer.compileSeconds * 1000))
/// RGBA premultiplied, top row first.
func metal(_ w: Int, _ h: Int, _ u: SnufflerUniforms, shadow: Bool) -> [UInt8] {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
    d.usage = [.renderTarget, .shaderRead]; d.storageMode = .shared
    let t = device.makeTexture(descriptor: d)!
    renderer.draw(u, to: t, shadow: shadow, waitUntilDone: true)
    var px = [UInt8](repeating: 0, count: w*h*4)
    t.getBytes(&px, bytesPerRow: w*4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
    for i in stride(from: 0, to: px.count, by: 4) { px.swapAt(i, i+2) }
    return px
}

// ---------- CPU reference for the CSS drop shadow ----------
func cssShadow(_ src: [UInt8], _ w: Int, _ h: Int) -> [UInt8] {
    let k = Double(w) / 270, sigma = 4 * k, ox = 1 * k, oy = 4 * k
    let r = Int((sigma * 4).rounded(.up))
    let kernel = (-r...r).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
    let ksum = kernel.reduce(0, +)
    // Blur over a padded area: the blurred alpha is not zero just outside the page, and the offset reads from there.
    let P = r + 2, W = w + 2*P, H = h + 2*P
    var alpha = [Double](repeating: 0, count: W*H)
    for y in 0..<h { for x in 0..<w { alpha[(y+P)*W + x+P] = Double(src[(y*w+x)*4+3]) / 255 } }
    func a(_ x: Int, _ y: Int, _ buf: [Double]) -> Double { (x < 0 || y < 0 || x >= W || y >= H) ? 0 : buf[y*W+x] }
    var tmp = [Double](repeating: 0, count: W*H), blur = tmp
    for y in 0..<H { for x in 0..<W { var s = 0.0; for i in -r...r { s += kernel[i+r] * a(x+i, y, alpha) }; tmp[y*W+x] = s / ksum } }
    for y in 0..<H { for x in 0..<W { var s = 0.0; for i in -r...r { s += kernel[i+r] * a(x, y+i, tmp) }; blur[y*W+x] = s / ksum } }
    func sample(_ px: Double, _ py: Double) -> Double {   // bilinear, pixel centres at integers
        let x = px + Double(P), y = py + Double(P)
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down)); let fx = x - Double(x0), fy = y - Double(y0)
        return (a(x0, y0, blur)*(1-fx) + a(x0+1, y0, blur)*fx)*(1-fy) + (a(x0, y0+1, blur)*(1-fx) + a(x0+1, y0+1, blur)*fx)*fy
    }
    var out = src
    let col = [20.0, 12.0, 4.0]
    for y in 0..<h { for x in 0..<w {
        let i = (y*w+x)*4, sa = 0.33 * sample(Double(x) - ox, Double(y) - oy), inv = 1 - Double(src[i+3]) / 255
        for c in 0..<3 { out[i+c] = UInt8(min(255, (Double(src[i+c]) + inv * col[c] * sa).rounded())) }
        out[i+3] = UInt8(min(255, (Double(src[i+3]) + inv * 255 * sa).rounded()))
    } }
    return out
}

// ---------- compare and write pictures ----------
struct Stats { var maxDiff = 0, over2 = 0, over8 = 0, over24 = 0; var mean = 0.0 }
func compare(_ a: [UInt8], _ b: [UInt8]) -> Stats {
    var s = Stats(); var total = 0
    for p in stride(from: 0, to: a.count, by: 4) {
        var m = 0
        for c in 0..<4 { let d = abs(Int(a[p+c]) - Int(b[p+c])); m = max(m, d); total += d }
        s.maxDiff = max(s.maxDiff, m); if m > 2 { s.over2 += 1 }; if m > 8 { s.over8 += 1 }; if m > 24 { s.over24 += 1 }
    }
    s.mean = Double(total) / Double(a.count); return s
}
/// left | right | difference ×16, each over a light and a dark half so halos would show.
func sheet(_ a: [UInt8], _ b: [UInt8], _ w: Int, _ h: Int, _ name: String) {
    let W = w*3, bytes = W*4
    var out = [UInt8](repeating: 255, count: W*h*4)
    for y in 0..<h { for x in 0..<w {
        let i = (y*w+x)*4
        let bg: [Double] = x < w/2 ? [236, 238, 242] : [28, 30, 36]
        for (col, src) in [(0, a), (1, b)] {
            let o = y*bytes + (col*w + x)*4, inv = 1 - Double(src[i+3]) / 255
            for c in 0..<3 { out[o+c] = UInt8(min(255, Double(src[i+c]) + inv*bg[c])) }
        }
        let o = y*bytes + (2*w + x)*4
        for c in 0..<3 { out[o+c] = UInt8(min(255, 16 * max(abs(Int(a[i+c]) - Int(b[i+c])), abs(Int(a[i+3]) - Int(b[i+3]))))) }
    } }
    let ctx = CGContext(data: &out, width: W, height: h, bitsPerComponent: 8, bytesPerRow: bytes, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let dest = CGImageDestinationCreateWithURL(outDir.appendingPathComponent(name + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
}

var worst = 0
for (label, w, h) in sizes {
    for c in cases {
        var u = SnufflerUniforms()
        for (n, p) in zip(names, paths) { if let v = c.set[n] { u[keyPath: p] = v } }
        let g = webgl(w, h, u), m = metal(w, h, u, shadow: false)
        let s = compare(g, m); worst = max(worst, s.maxDiff)
        print(String(format: "%3@%%  %-16@ max %3d  mean %.4f  px>2 %5d  px>8 %5d  px>24 %5d  of %d", label, c.name, s.maxDiff, s.mean, s.over2, s.over8, s.over24, w*h))
        sheet(g, m, w, h, "\(label)-\(c.name)")
        if c.name == "needs-yaw0.95" || c.name == "failed-yaw0.0" {
            let ref = cssShadow(g, w, h), ms = metal(w, h, u, shadow: true)
            let ss = compare(ref, ms)
            print(String(format: "%3@%%  %-16@ max %3d  mean %.4f  px>2 %5d  px>8 %5d   (with shadow, vs a CPU Gaussian on the WebGL pixels)", label, c.name + "+shadow", ss.maxDiff, ss.mean, ss.over2, ss.over8))
            sheet(ref, ms, w, h, "\(label)-\(c.name)-shadow")
        }
    }
}
print("WebGL: \(glVersion)")
print("worst channel difference without shadow: \(worst) / 255")
