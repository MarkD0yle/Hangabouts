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
    /// which is exactly what the page's WebGL canvas holds. `translateY` slides the whole picture,
    /// as a fraction of its height (positive is down).
    func draw(_ uniforms: SnufflerUniforms, to target: MTLTexture, shadow: Bool = true, translateY: Float = 0,
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
        var c = CompositeUniforms(res: u.uRes, offset: SIMD2(1 * k, 4 * k), shift: SIMD2(0, translateY * Float(height)), sigma: sigma, lod: max(0, log2(max(sigma, 0.001) / 2)))
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
/// Owns the motion model and runs it: a display link while he moves, a timer for what comes later.
@MainActor
final class SnufflerView: NSView {
    /// Called on a plain click (not a drag).
    var onClicked: (() -> Void)?
    /// Called when he has landed after `show`.
    var onShown: (() -> Void)?
    /// Called when he is back in his burrow after `climb`.
    var onClimbed: (() -> Void)?

    /// Called once the shader has compiled, with how long it took in seconds.
    var onReady: ((Double) -> Void)?
    /// Called if the shader doesn't compile. Nothing will be drawn.
    var onFailed: ((Error) -> Void)?

    private let device: MTLDevice
    private var renderer: SnufflerRenderer?   // nil until the shader has compiled
    private let motion = SnufflerMotion()
    private var zoom: CGFloat = 1
    private var link: CADisplayLink?
    private var eventTimer: Timer?

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    private var now: Double { CACurrentMediaTime() }

    /// Throws if Metal isn't available or the shader file is missing.
    ///
    /// The shader compiles on a background queue: a cold compile takes about 250 ms, too long for the main thread.
    /// Nothing waits for it. The motion runs from the first call; frames are simply not drawn until it is ready.
    init(size: NSSize) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw SnufflerRenderError(description: "Metal is not available") }
        // Bundle.main, not Bundle.module: resources are copied by scripts/bundle.sh, not by SwiftPM.
        guard let url = Bundle.main.url(forResource: "snuffler", withExtension: "metal") else {
            throw SnufflerRenderError(description: "snuffler.metal is missing from the app's Resources")
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        self.device = device
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try SnufflerRenderer(device: device, source: source) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.compiled(result) }
            }
        }
    }

    private func compiled(_ result: Result<SnufflerRenderer, Error>) {
        switch result {
        case .success(let renderer):
            self.renderer = renderer
            draw(motion.current(now: now))
            onReady?(renderer.compileSeconds)
        case .failure(let error):
            onFailed?(error)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func makeBackingLayer() -> CALayer {
        let l = CAMetalLayer()
        l.device = device
        l.pixelFormat = SnufflerRenderer.pixelFormat
        l.isOpaque = false                       // premultiplied alpha over the desktop, as WebGL's canvas was
        l.framebufferOnly = true
        l.maximumDrawableCount = 2               // he is small and mostly still; a third drawable is wasted memory
        l.colorspace = CGColorSpace(name: CGColorSpace.sRGB)   // the page's colours were sRGB
        l.contentsGravity = .resize              // the drawable is stretched to the view, as the canvas was to its CSS size
        return l
    }

    // MARK: - API. The same calls the page had (`window.hangabout`).

    /// He drops in a pose. `onShown` follows when he lands.
    func show(failed: Bool) {
        let out = motion.show(failed: failed, now: now)
        draw(motion.current(now: now))   // at once, so the panel never shows where he last was
        handle(out)
    }

    /// 1: a push on the swing. 2: he pumps it himself for a few beats.
    func nudge(level: Int) { motion.nudge(level: level, now: now); schedule() }

    func swapArms() { motion.swapArms(now: now); schedule() }

    /// He climbs back up. `onClimbed` follows.
    func climb() { handle(motion.climb(now: now)) }

    func hide() { motion.hide(); schedule() }

    func setIdle(_ on: Bool) { motion.setIdle(on, now: now); schedule() }

    func setTired(_ on: Bool) { motion.setTired(on, now: now); schedule() }

    func setReducedMotion(_ on: Bool) { motion.setReducedMotion(on, now: now); schedule() }

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
        draw(motion.current(now: now))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()   // moved to a screen with a different scale
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        if window != nil {
            // The view's own display link follows whichever screen he is on (macOS 14).
            let l = displayLink(target: self, selector: #selector(tick))
            l.isPaused = true
            l.add(to: .main, forMode: .common)
            link = l
        }
        updateDrawableSize()
        schedule()
    }

    // MARK: - Running the motion

    /// One display refresh. The page's `frame()`.
    @objc private func tick() {
        let t = now
        let out = motion.fire(now: t)
        if motion.running { draw(motion.frame(now: t)) }
        handle(out)
    }

    private func handle(_ out: [SnufflerMotion.Output]) {
        schedule()
        for o in out {
            switch o {
            case .shown: onShown?()
            case .climbed: onClimbed?()
            }
        }
    }

    /// Runs the display link only while he moves, and sets a timer for the next thing due while he is still.
    private func schedule() {
        link?.isPaused = !motion.running
        eventTimer?.invalidate()
        eventTimer = nil
        guard let at = motion.nextEventTime else { return }
        let timer = Timer(timeInterval: max(0, at - now), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        eventTimer = timer
    }

    private func draw(_ frame: SnufflerMotion.Frame) {
        guard let renderer, window != nil, metalLayer.drawableSize.width > 0, let drawable = metalLayer.nextDrawable() else { return }
        // Hidden: slide him right off the page, so the drawable is clear.
        renderer.draw(frame.uniforms, to: drawable.texture, translateY: motion.isHidden ? -10 : Float(frame.translateY), presenting: drawable)
    }

    // MARK: - Input

    // A non-activating panel can ignore the first click; accepting first mouse makes it count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The pointer's x in the page's 270-wide design pixels, as `clientX` was.
    private func designX(_ event: NSEvent) -> Double {
        Double(convert(event.locationInWindow, from: nil).x * 270 / max(bounds.width, 1))
    }

    // Drag to turn him; a plain click still counts as a click.
    override func mouseDown(with event: NSEvent) { motion.dragBegan(x: designX(event), now: now); schedule() }

    override func mouseDragged(with event: NSEvent) { motion.dragMoved(x: designX(event), now: now); schedule() }

    override func mouseUp(with event: NSEvent) {
        if motion.dragEnded() { onClicked?() }
        schedule()
    }

    // Enter and Space count as a click, as on the page's button. His panel never becomes key
    // (it must not take focus when he drops), so these only arrive if something else gives him focus.
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76, 49: if !motion.isHidden { onClicked?() }   // Return, keypad Enter, Space
        default: super.keyDown(with: event)
        }
    }

    // MARK: - Accessibility. The page's <button aria-label="…">.

    override func isAccessibilityElement() -> Bool { !motion.isHidden }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilityLabel() -> String? {
        motion.failed ? "Snuffler hit a problem. Show details" : "Snuffler needs you. Show details"
    }

    override func accessibilityPerformPress() -> Bool {
        guard !motion.isHidden else { return false }
        onClicked?()
        return true
    }
}
