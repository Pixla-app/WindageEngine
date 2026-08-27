//
//  BoundingBox.swift
//  WindageEngine
//

import simd

/// An axis-aligned box, and the ray test that goes with it.
///
/// **Deliberately the crudest useful shape.** Triangle-accurate hit testing needs an acceleration
/// structure, and a box is wrong in the corners — but it answers "did the round reach that thing"
/// for scenery-sized objects, which is what ranging and impact need first. The seam to replace it
/// later is this one type.
public nonisolated struct BoundingBox: Sendable, Equatable {

    public var minimum: SIMD3<Float>
    public var maximum: SIMD3<Float>

    public init(minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public var centre: SIMD3<Float> { (minimum + maximum) * 0.5 }
    public var size: SIMD3<Float> { maximum - minimum }

    /// The box containing this one after a transform.
    ///
    /// **Re-derived from the eight corners, not by transforming two points.** Transforming only the
    /// min and max gives the right answer for a translation and a wrong one for any rotation — the
    /// resulting "box" can be inside-out or far too small, and the failure is a shot that passes
    /// through a target rather than an obvious visual glitch.
    public func transformed(by matrix: matrix_float4x4) -> BoundingBox {
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        for index in 0..<8 {
            let corner = SIMD3<Float>(
                index & 1 == 0 ? minimum.x : maximum.x,
                index & 2 == 0 ? minimum.y : maximum.y,
                index & 4 == 0 ? minimum.z : maximum.z)
            let world = matrix * SIMD4<Float>(corner, 1)
            low = simd_min(low, SIMD3(world.x, world.y, world.z))
            high = simd_max(high, SIMD3(world.x, world.y, world.z))
        }
        return BoundingBox(minimum: low, maximum: high)
    }

    /// Distance along the ray to the nearest entry point, or nil if it misses.
    ///
    /// The slab method: clip the ray against each pair of parallel faces and keep the overlap. The
    /// division by zero for a ray exactly parallel to an axis is intentional and correct — IEEE
    /// infinities make the comparisons fall out the right way, where guarding against it with a
    /// branch is where implementations usually go wrong.
    public func intersection(origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float = .greatestFiniteMagnitude) -> Float? {
        let inverse = 1 / direction
        let t0 = (minimum - origin) * inverse
        let t1 = (maximum - origin) * inverse

        let near = simd_min(t0, t1)
        let far = simd_max(t0, t1)

        let entry = max(max(near.x, near.y), near.z)
        let exit = min(min(far.x, far.y), far.z)

        guard exit >= max(entry, 0), entry <= maxDistance else { return nil }
        // A ray starting inside the box hits at zero, not at a negative distance behind itself.
        return max(entry, 0)
    }

    /// Whether a segment from `start` to `end` touches the box.
    public func intersects(segmentFrom start: SIMD3<Float>, to end: SIMD3<Float>) -> Float? {
        let delta = end - start
        let length = simd_length(delta)
        guard length > 0 else {
            let inside = all(start .>= minimum) && all(start .<= maximum)
            return inside ? 0 : nil
        }
        return intersection(origin: start, direction: delta / length, maxDistance: length)
    }
}
