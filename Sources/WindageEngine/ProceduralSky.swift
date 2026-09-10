//
//  ProceduralSky.swift
//  WindageEngine
//

import simd

/// A sky as a function of direction: radiance arriving from anywhere you point.
///
/// **A stand-in for a captured environment, not a replacement for one.** A real scene reflects a
/// photographed HDR panorama with buildings and clouds in it. This is a gradient, a horizon and a sun
/// disc — enough for metal to read as metal and for a reflection to be legible, and enough that a
/// game with no environment asset still gets correct image-based lighting rather than none.
///
/// **Radiance, not colour.** The sun is thousands of times brighter than the sky around it, and these
/// numbers say so; that is what the HDR target and ``ToneMapping`` exist for. Values here are linear
/// and unbounded.
public nonisolated struct ProceduralSky: Sendable, Equatable {

    /// Straight up.
    public var zenith: SIMD3<Float>

    /// At the horizon. Brighter and less saturated than the zenith in a real sky, because there is
    /// more atmosphere in the way.
    public var horizon: SIMD3<Float>

    /// Below the horizon — what the ground bounces back up. **Not black**: a surface facing down is
    /// lit by the ground, and a black lower hemisphere is the single most common reason an
    /// image-based lit object looks like it is floating in a void.
    public var ground: SIMD3<Float>

    /// Towards the sun, normalised.
    public var sunDirection: SIMD3<Float>

    /// The sun's own radiance. **Large on purpose** — a value of 1 makes a sun the same brightness as
    /// a white wall, and its reflection in polished metal then reads as a smudge rather than a sun.
    public var sunRadiance: SIMD3<Float>

    /// Angular radius of the sun's disc, in radians. The real one is about 0.00465; a wider disc
    /// gives a softer reflection and is usually what a stylised game wants.
    public var sunAngularRadius: Float

    public init(zenith: SIMD3<Float> = SIMD3(0.28, 0.45, 0.85),
                horizon: SIMD3<Float> = SIMD3(0.62, 0.72, 0.88),
                ground: SIMD3<Float> = SIMD3(0.22, 0.21, 0.18),
                sunDirection: SIMD3<Float> = normalize(SIMD3(0.4, 0.7, 0.6)),
                sunRadiance: SIMD3<Float> = SIMD3(28, 26, 22),
                sunAngularRadius: Float = 0.05) {
        self.zenith = zenith
        self.horizon = horizon
        self.ground = ground
        self.sunDirection = normalize(sunDirection)
        self.sunRadiance = sunRadiance
        self.sunAngularRadius = sunAngularRadius
    }

    /// Radiance arriving from `direction`, which need not be normalised.
    public func radiance(inDirection direction: SIMD3<Float>) -> SIMD3<Float> {
        let d = simd_length(direction) > 1e-6 ? simd_normalize(direction) : SIMD3(0, 1, 0)

        // Above the horizon, a gradient; below it, the ground fading in over a few degrees so a
        // reflection does not have a hard line across it.
        let sky: SIMD3<Float>
        if d.y >= 0 {
            // Raised to a power so most of the change happens near the horizon, which is where a real
            // sky's does.
            let t = pow(d.y, 0.45)
            sky = simd_mix(horizon, zenith, SIMD3(repeating: t))
        } else {
            let t = simd_clamp(-d.y / 0.08, 0, 1)
            sky = simd_mix(horizon, ground, SIMD3(repeating: t))
        }

        // The sun's disc, with a soft edge. **Not a hard circle**: prefiltering samples this function
        // a few dozen times per texel, and a hard edge at that sample count is a ring of speckle
        // rather than a sun.
        let cosAngle = simd_dot(d, sunDirection)
        let cosOuter = cos(sunAngularRadius)
        let cosInner = cos(sunAngularRadius * 0.55)
        guard cosAngle > cosOuter else { return sky }
        let edge = simd_smoothstep(cosOuter, cosInner, cosAngle)
        return sky + sunRadiance * edge
    }
}

/// `smoothstep`, which simd spells only for scalars in some SDKs.
nonisolated func simd_smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = simd_clamp((x - edge0) / max(edge1 - edge0, 1e-6), 0, 1)
    return t * t * (3 - 2 * t)
}
