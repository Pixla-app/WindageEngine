//
//  Math.swift
//  WindageEngine
//

import simd

// Transform helpers. `nonisolated` because they are pure arithmetic: the engine defaults every
// declaration to @MainActor, which would otherwise make a projection unusable from a test, a worker
// thread, or a render thread — none of which is a UI context.

public nonisolated func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                                         vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                                         vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                                         vector_float4(                  0,                   0,                   0, 1)))
}

public nonisolated func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(0, 0, 1, 0),
                                         vector_float4(translationX, translationY, translationZ, 1)))
}

/// Right-handed perspective projection using **reversed-Z with an infinite far plane**.
///
/// Maps the near plane to depth 1 and infinite distance to depth 0 — the opposite of the
/// conventional near-0/far-1. Depth is stored as floating point, and floats hold far more precision
/// near zero, so the conventional mapping spends almost all of it in the first few metres and leaves
/// the far field to z-fight. A game about reading a target at 800 m wants the precision where the
/// distance is.
///
/// Three things have to agree or nothing renders at all:
///   - this projection,
///   - `depthCompareFunction = .greater` (nearer is now a larger value),
///   - a depth clear value of 0.
///
/// `RenderTargets` and `FrameRenderer` supply the other two, so a game that uses them gets a
/// consistent set rather than three constants it has to remember to match.
///
/// The far plane is gone rather than merely large: depth approaches 0 asymptotically, so there is
/// no view distance to tune and nothing to clip against at range.
public nonisolated func matrix_perspective_right_hand_reverse_z(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    return matrix_float4x4.init(columns:(vector_float4(xs,  0,     0,  0),
                                         vector_float4( 0, ys,     0,  0),
                                         vector_float4( 0,  0,     0, -1),
                                         vector_float4( 0,  0, nearZ,  0)))
}

/// The same projection, confined to a **slice of the depth buffer**.
///
/// ### What this is for: drawing a weapon in the player's hands
///
/// A first-person viewmodel is not part of the world and cannot be projected like it. Two things go
/// wrong if you try.
///
/// **It is too big.** At a 65° field of view a real rifle held 30 cm from the eye genuinely fills a
/// quarter of the screen. Every shooter solves this with a *narrower* field of view for the weapon
/// than for the world — around 55° against 65° here — which is a projection, not a size. Shrinking
/// the model instead is the shortcut, and it makes the weapon geometrically a lie: anything measured
/// off it afterwards (a muzzle position, a bipod's contact, a bolt's travel) is computed in a space
/// that only happens to look right.
///
/// **It intersects the world.** A rifle 90 cm long, held by a player who can stand 45 cm from a
/// wall, pokes through the wall. That is physically true and looks broken. Reserving the front of
/// the depth buffer for the viewmodel puts it in front of everything without an extra pass and
/// without breaking its *own* occlusion — a bolt behind a receiver still hides behind it, because
/// the slice is monotonic.
///
/// - Parameter depthRange: where in the buffer this projection lands. `0...1` is the whole buffer and
///   gives exactly the same matrix as the world projection. `0.9...1` is the front tenth: with a
///   0.1 m near plane, world geometry only reaches depth 0.9 at **11 cm** from the eye, which is
///   nearer than a player can get to anything.
///
/// > Reversed-Z, so **larger is nearer** — `depthRange.upperBound` is the near end. Reading it the
/// > other way puts the weapon behind the world, which renders as the weapon simply not being there.
public nonisolated func matrix_perspective_right_hand_reverse_z(fovyRadians fovy: Float,
                                                                aspectRatio: Float,
                                                                nearZ: Float,
                                                                depthRange: ClosedRange<Float>) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let low = depthRange.lowerBound
    let span = depthRange.upperBound - low
    // Derived rather than tuned: the unmapped form gives depth = nearZ / distance, and this wants
    // `low + span * nearZ / distance`. Multiplying out against clip.w = -z gives these two terms.
    return matrix_float4x4(columns: (vector_float4(xs,  0,           0,  0),
                                     vector_float4( 0, ys,           0,  0),
                                     vector_float4( 0,  0,        -low, -1),
                                     vector_float4( 0,  0, span * nearZ,  0)))
}

public nonisolated func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}

/// The transform that keeps a normal perpendicular to its surface: the inverse transpose of the
/// upper-left 3×3.
///
/// For rotation and uniform scale this equals the matrix itself, so it looks like ceremony in any
/// scene built from translations. It stops being ceremony the first time anything is scaled
/// unevenly: the plain matrix shears normals off the surface, and the shading goes subtly wrong in a
/// way that is hard to attribute afterwards.
public nonisolated func normalMatrix(from modelView: matrix_float4x4) -> matrix_float3x3 {
    let upperLeft = matrix_float3x3(columns: (
        SIMD3(modelView.columns.0.x, modelView.columns.0.y, modelView.columns.0.z),
        SIMD3(modelView.columns.1.x, modelView.columns.1.y, modelView.columns.1.z),
        SIMD3(modelView.columns.2.x, modelView.columns.2.y, modelView.columns.2.z)
    ))
    return simd_transpose(simd_inverse(upperLeft))
}
