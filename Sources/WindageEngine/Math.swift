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
