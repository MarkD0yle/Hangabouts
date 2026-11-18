import AppKit
import Metal
import QuartzCore

struct SnufflerRenderError: Error, CustomStringConvertible {
    let description: String
}

/// Compiles snuffler.metal and draws Snuffler into a texture. No AppKit, so it can be driven offscreen.
final class SnufflerRenderer {
    static let pixelFormat: MTLPixelFormat = .bgra8Unorm
    /// The page's design size. 1 world unit = 79 px.
    static let designSize = SIMD2<Float>(270, 262)

    let device: MTLDevice
    /// How long the shader took to compile and link, in seconds (Spec 006, E8).
    let compileSeconds: Double

    private let queue: MTLCommandQueue
    private let scenePipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private var scene: MTLTexture?   // pass 1's output, with mips for the shadow blur

    init(device: MTLDevice, source: String) throws {
        self.device = device
        let start = CACurrentMediaTime()
        guard let queue = device.makeCommandQueue() else { throw SnufflerRenderError(description: "no Metal command queue") }
        self.queue = queue

        let library: MTLLibrary
        do { library = try device.makeLibrary(source: source, options: nil) }
        catch { throw SnufflerRenderError(description: "shader compile error: \(error.localizedDescription)") }

        func pipeline(_ fragment: String, expecting size: Int) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "quad_vertex")
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = SnufflerRenderer.pixelFormat   // no blending: the shader writes premultiplied colour
            var reflection: MTLRenderPipelineReflection?
            let state = try device.makeRenderPipelineState(descriptor: d, options: [.bindingInfo, .bufferTypeInfo], reflection: &reflection)
            // The Swift struct and the Metal struct must be the same size, or every uniform after the gap is wrong.
            let metalSize = reflection?.fragmentBindings.compactMap { $0 as? MTLBufferBinding }.first?.bufferDataSize
            guard metalSize == size else {
                throw SnufflerRenderError(description: "\(fragment): uniforms are \(size) bytes in Swift but \(metalSize.map(String.init) ?? "?") in Metal")
            }
            return state
        }
        scenePipeline = try pipeline("snuffler_fragment", expecting: MemoryLayout<SnufflerUniforms>.stride)
        compositePipeline = try pipeline("composite_fragment", expecting: MemoryLayout<CompositeUniforms>.stride)

        let s = MTLSamplerDescriptor()
        s.minFilter = .linear; s.magFilter = .linear; s.mipFilter = .linear
        s.sAddressMode = .clampToEdge; s.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: s) else { throw SnufflerRenderError(description: "no Metal sampler") }
        self.sampler = sampler
        compileSeconds = CACurrentMediaTime() - start
    }

    /// Draws one frame into `target`, at the target's size. `shadow: false` gives pass 1 alone,
    /// which is exactly what the page's WebGL canvas holds.
    func draw(_ uniforms: SnufflerUniforms, to target: MTLTexture, shadow: Bool = true,
              presenting drawable: MTLDrawable? = nil, waitUntilDone: Bool = false) {
        let width = target.width, height = target.height
        if scene?.width != width || scene?.height != height {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: SnufflerRenderer.pixelFormat, width: width, height: height, mipmapped: true)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            scene = device.makeTexture(descriptor: d)
        }
        guard let scene, let commands = queue.makeCommandBuffer() else { return }

        func pass(_ texture: MTLTexture, _ body: (MTLRenderCommandEncoder) -> Void) {
            let p = MTLRenderPassDescriptor()
            p.colorAttachments[0].texture = texture
            p.colorAttachments[0].loadAction = .clear
            p.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            p.colorAttachments[0].storeAction = .store
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: p) else { return }
            body(encoder)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }

        var u = uniforms
        u.uRes = SIMD2(Float(width), Float(height))
        pass(scene) { e in
            e.setRenderPipelineState(scenePipeline)
            e.setFragmentBytes(&u, length: MemoryLayout<SnufflerUniforms>.stride, index: 0)
        }
        if shadow, let blit = commands.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: scene)
            blit.endEncoding()
        }
        // The page's shadow is drop-shadow(1px 4px 4px ...) in design pixels; k turns those into target pixels.
        let k = Float(width) / SnufflerRenderer.designSize.x
        let sigma = shadow ? 4 * k : 0
        var c = CompositeUniforms(res: u.uRes, offset: SIMD2(1 * k, 4 * k), sigma: sigma, lod: max(0, log2(max(sigma, 0.001) / 2)))
        pass(target) { e in
            e.setRenderPipelineState(compositePipeline)
            e.setFragmentBytes(&c, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            e.setFragmentTexture(scene, index: 0)
            e.setFragmentSamplerState(sampler, index: 0)
        }
        if let drawable { commands.present(drawable) }
        commands.commit()
        if waitUntilDone { commands.waitUntilCompleted() }
    }
}

/// Snuffler, drawn by Metal instead of a web page. Spec 006.
/// M1: a still image only. Motion (M2), drag, keyboard and accessibility (M4) come later.
@MainActor
final class SnufflerView: NSView {
    /// Called on a plain click.
    var onClicked: (() -> Void)?

    let renderer: SnufflerRenderer
    private var uniforms = SnufflerUniforms.still(failed: false)
    private var zoom: CGFloat = 1

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    /// Throws if Metal isn't available or the shader doesn't compile. The controller then falls back to WebGL.
    init(size: NSSize) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw SnufflerRenderError(description: "Metal is not available") }
        // Same Bundle.main rule as the page: resources are copied by scripts/bundle.sh, not by SwiftPM.
        guard let url = Bundle.main.url(forResource: "snuffler", withExtension: "metal") else {
            throw SnufflerRenderError(description: "snuffler.metal is missing from the app's Resources")
        }
        renderer = try SnufflerRenderer(device: device, source: try String(contentsOf: url, encoding: .utf8))
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func makeBackingLayer() -> CALayer {
        let l = CAMetalLayer()
        l.device = renderer.device
        l.pixelFormat = SnufflerRenderer.pixelFormat
        l.isOpaque = false                       // premultiplied alpha over the desktop, as WebGL's canvas was
        l.framebufferOnly = true
        l.maximumDrawableCount = 2               // he is small and mostly still; a third drawable is wasted memory
        l.colorspace = CGColorSpace(name: CGColorSpace.sRGB)   // the page's colours were sRGB
        l.contentsGravity = .resize              // the drawable is stretched to the view, as the canvas was to its CSS size
        return l
    }

    // MARK: - API

    /// Hanging still in a pose.
    func showStill(failed: Bool) {
        uniforms = .still(failed: failed)
        redraw()
    }

    /// His size relative to the 270×262 design, so no more pixels are drawn than are shown.
    func setZoom(_ z: CGFloat) {
        zoom = z > 0 ? z : 1
        updateDrawableSize()
    }

    // MARK: - Size

    /// The page's rule: k = min(dpr, max(0.5, zoom × dpr × 1.5)), with dpr capped at 2.
    private func updateDrawableSize() {
        let dpr = min(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2, 2)
        let k = min(dpr, max(0.5, zoom * dpr * 1.5))
        let size = CGSize(width: (270 * k).rounded(), height: (262 * k).rounded())
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size }
        redraw()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()   // moved to a screen with a different scale
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
    }

    // MARK: - Drawing

    private func redraw() {
        guard window != nil, metalLayer.drawableSize.width > 0, let drawable = metalLayer.nextDrawable() else { return }
        renderer.draw(uniforms, to: drawable.texture, presenting: drawable)
    }

    // MARK: - Input

    // A non-activating panel can ignore the first click; accepting first mouse makes it count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClicked?() }
    }
}
