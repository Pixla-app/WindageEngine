//
//  Deprecated.swift
//  WindageEngine
//

import ModelIO
import simd

// MARK: - The British names, for one release (0.26.0)
//
// **Public names are US English from 0.26.0** — `color`, `center`, `unitsPerMeter` — because the people
// writing games against this engine read and type them, and nearly all of them write US English. The old
// names stay here, deprecated and forwarding, **for one release**: a game that upgrades gets a warning with
// a fix-it at every use rather than a build that fails. They are deleted in the release after 0.26.0.
//
// One change could not be aliased: ``ParticleSystem/appearance(of:)`` returns a tuple, and a tuple's labels
// cannot have two names — `.colour` on its result is now `.color`.

extension BoundingBox {
    @available(*, deprecated, renamed: "center")
    public var centre: SIMD3<Float> { center }
}

extension AssetOrientation {
    @available(*, deprecated, renamed: "unitsPerMeter")
    public var unitsPerMetre: Float {
        get { unitsPerMeter }
        set { unitsPerMeter = newValue }
    }

    // No default for the old label, so `AssetOrientation()` and `AssetOrientation(upAxis:)` stay unambiguous.
    @available(*, deprecated, renamed: "init(upAxis:unitsPerMeter:)")
    public init(upAxis: UpAxis = .y, unitsPerMetre: Float) {
        self.init(upAxis: upAxis, unitsPerMeter: unitsPerMetre)
    }

    @available(*, deprecated, renamed: "read(from:unitsPerMeter:)")
    public static func read(from asset: MDLAsset, unitsPerMetre: Float) -> AssetOrientation {
        read(from: asset, unitsPerMeter: unitsPerMetre)
    }
}

extension CharacterController.Surroundings.Turn {
    @available(*, deprecated, renamed: "center")
    public var centre: SIMD2<Float> {
        get { center }
        set { center = newValue }
    }
}

extension CharacterController.Surroundings.Footprint {
    @available(*, deprecated, renamed: "center")
    public var centre: SIMD2<Float> {
        get { center }
        set { center = newValue }
    }

    @available(*, deprecated, renamed: "init(center:halfSize:yaw:)")
    public init(centre: SIMD2<Float>, halfSize: SIMD2<Float>, yaw: Float) {
        self.init(center: centre, halfSize: halfSize, yaw: yaw)
    }

    @available(*, deprecated, renamed: "init(center:radius:)")
    public init(centre: SIMD2<Float>, radius: Float) {
        self.init(center: centre, radius: radius)
    }
}

extension EngineMark {
    @available(*, deprecated, renamed: "draw(into:x:y:height:color:)")
    public static func draw(into hud: HUDRenderer, x: Float, y: Float, height: Float, colour: UIColor) {
        draw(into: hud, x: x, y: y, height: height, color: colour)
    }
}

extension HUDRenderer {
    @available(*, deprecated, renamed: "ring(center:innerRadius:outerRadius:segments:color:)")
    public func ring(centre: SIMD2<Float>, innerRadius: Float, outerRadius: Float, segments: Int = 96,
                     colour: UIColor) {
        ring(center: centre, innerRadius: innerRadius, outerRadius: outerRadius, segments: segments, color: colour)
    }
}

extension ParticleRecipe {
    @available(*, deprecated, renamed: "color")
    public var colour: SIMD3<Float> {
        get { color }
        set { color = newValue }
    }

    @available(*, deprecated, renamed: "init(count:speed:spread:lifetime:size:growth:gravity:drag:color:opacity:fade:glows:)")
    public init(count: Int, speed: Float, spread: Float, lifetime: Float, size: Float,
                growth: Float = 0, gravity: Float = -6.5, drag: Float = 2.4,
                colour: SIMD3<Float>, opacity: Float = 1, fade: Float = 1, glows: Bool = false) {
        self.init(count: count, speed: speed, spread: spread, lifetime: lifetime, size: size, growth: growth,
                  gravity: gravity, drag: drag, color: colour, opacity: opacity, fade: fade, glows: glows)
    }
}

extension PunctualLight {
    @available(*, deprecated, renamed: "color")
    public var colour: SIMD3<Float> {
        get { color }
        set { color = newValue }
    }

    @available(*, deprecated, renamed: "init(position:color:range:cone:)")
    public init(position: SIMD3<Float>, colour: SIMD3<Float>, range: Float, cone: Cone? = nil) {
        self.init(position: position, color: colour, range: range, cone: cone)
    }
}
