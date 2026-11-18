import simd

/// Every uniform of Snuffler's shader. Must match `struct Uniforms` in snuffler.metal exactly:
/// `uRes` first, then the floats in the same order. SnufflerRenderer checks the size at launch.
struct SnufflerUniforms {
    var uRes = SIMD2<Float>(270, 262)
    var uYaw: Float = SnufflerUniforms.restYaw
    var uSwing: Float = 0
    var uSignSwing: Float = 0
    var uSignYaw: Float = 0
    var uBlink: Float = 0
    var uKick: Float = 0
    var uTail: Float = 0
    var uSniff: Float = 0
    var uFail: Float = 0
    var uBreathe: Float = 0
    var uRaiseR: Float = 1   // at rest he hangs by his right hand
    var uRaiseL: Float = 0
    var uShakeR: Float = 0
    var uShakeL: Float = 0
    var uTired: Float = 0
    var uBody: Float = 0
    var uGrip: Float = 1

    /// Resting turn: three-quarter view, facing right. `REST` in the page.
    static let restYaw: Float = 0.95
}

/// Uniforms of the drop-shadow pass. Must match `struct CompositeUniforms` in snuffler.metal.
struct CompositeUniforms {
    var res: SIMD2<Float>
    var offset: SIMD2<Float>
    var shift: SIMD2<Float>
    var sigma: Float
    var lod: Float
}
