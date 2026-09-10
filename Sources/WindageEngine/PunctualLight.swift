//
//  PunctualLight.swift
//  WindageEngine
//

import simd

/// A light at a point, radiating in every direction.
///
/// **The first light in this engine that is not the sun.** A directional sun and an environment map
/// light an outdoor scene correctly and have no answer at all for an interior: the sun does not reach
/// inside, and a sky-coloured ambient lights a cellar as though the sky were overhead.
public nonisolated struct PunctualLight: Sendable, Equatable, Codable {

    public var position: SIMD3<Float>

    /// Colour times brightness, unbounded — **radiant intensity, not a colour.** A lamp is far
    /// brighter than white paper, which is what the HDR target and ``ToneMapping`` are for.
    public var colour: SIMD3<Float>

    /// Metres at which this light has fallen to nothing.
    ///
    /// **Finite on purpose.** An inverse-square falloff never actually reaches zero, so without a
    /// cutoff every lamp in a building is technically relevant to every fragment and no selection
    /// rule can ever discard one.
    public var range: Float

    public init(position: SIMD3<Float>, colour: SIMD3<Float>, range: Float) {
        self.position = position
        self.colour = colour
        self.range = range
    }

    // MARK: - Codable
    //
    // **Colour as a triple and brightness as its own number**, because that is how a person reasons
    // about a lamp: what colour is it, and how bright. Writing `[28, 26, 22]` in a level file means
    // holding a colour and an intensity in your head at once, and adjusting one changes the other.

    private enum CodingKeys: String, CodingKey { case position, colour, intensity, range }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func triple(_ key: CodingKeys, _ or: SIMD3<Float>) throws -> SIMD3<Float> {
            guard let values = try container.decodeIfPresent([Float].self, forKey: key) else { return or }
            guard values.count == 3 else {
                throw DecodingError.dataCorruptedError(
                    forKey: key, in: container,
                    debugDescription: "needs three components, found \(values.count)")
            }
            return SIMD3(values[0], values[1], values[2])
        }
        let intensity = try container.decodeIfPresent(Float.self, forKey: .intensity) ?? 1
        self.init(position: try triple(.position, .zero),
                  colour: try triple(.colour, SIMD3(repeating: 1)) * intensity,
                  range: try container.decodeIfPresent(Float.self, forKey: .range) ?? 8)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode([position.x, position.y, position.z], forKey: .position)

        // Split back out so a saved level reads the way a written one does: the brightest channel
        // carries the intensity and the colour is normalised against it.
        let intensity = max(colour.max(), 1e-6)
        let normalised = colour / intensity
        try container.encode([normalised.x, normalised.y, normalised.z], forKey: .colour)
        try container.encode(intensity, forKey: .intensity)
        try container.encode(range, forKey: .range)
    }

    /// How much of this light survives to a point: physical inverse-square, windowed to zero at the
    /// range.
    ///
    /// **Inverse square because that is what light does**, and the window because the range has to be
    /// a real edge. The window is squared so it approaches zero smoothly — a light that still
    /// contributes at its cutoff draws a visible sphere on the floor where it ends.
    ///
    /// Near the light this grows without bound, which is correct and is why the denominator has a
    /// floor: a fragment exactly at a lamp's position is a division by zero, and the pixel it
    /// produces is not "very bright", it is `NaN` and therefore black.
    public func attenuation(at point: SIMD3<Float>) -> Float {
        let offset = point - position
        let distanceSquared = max(simd_length_squared(offset), 1e-4)
        guard range > 0 else { return 0 }
        let ratio = distanceSquared / (range * range)
        let window = simd_clamp(1 - ratio * ratio, 0, 1)
        return window * window / distanceSquared
    }

    /// What this light actually contributes at a point, as a single number.
    ///
    /// ### Why this is not distance, and not attenuation either
    ///
    /// A budget means choosing which lights to keep, and **the obvious choice — the nearest few — has
    /// an obvious bug**: *nearest* changes as the player walks, so a light drops out of the set and a
    /// surface goes dark in one frame. The fix is not a bigger budget; it is choosing by how much a
    /// light is *doing*, so one leaves the set at the point where it had nearly stopped mattering.
    ///
    /// **And attenuation alone is not enough either, which the probe this came from had wrong.** It
    /// ranked lights by falloff and ignored their brightness — so a candle at one metre outranked a
    /// floodlight at ten, and the floodlight was the one dropped. Weighting by luminance costs a dot
    /// product and makes the ordering mean what it claims.
    public func influence(at point: SIMD3<Float>) -> Float {
        attenuation(at: point) * PunctualLight.luminance(colour)
    }

    /// Rec. 709 luminance: how bright a colour looks, rather than how large its numbers are.
    ///
    /// Green carries most of it and blue almost none, which is why a blue lamp of the same numeric
    /// magnitude as a green one is the one to drop first.
    public static func luminance(_ colour: SIMD3<Float>) -> Float {
        simd_dot(colour, SIMD3(0.2126, 0.7152, 0.0722))
    }

    /// Whether this light reaches any part of a box.
    ///
    /// **Tested against the nearest point of the box, not its centre.** A long wall whose centre is
    /// out of range still has an end inside it, and lighting a whole draw by its centre is how one
    /// end of a corridor goes dark.
    public func reaches(_ bounds: BoundingBox) -> Bool {
        influence(at: bounds.closestPoint(to: position)) > 0
    }
}

/// Which lights reach a point, when there is more than one and it is not the sun.
///
/// **Extracted from a probe built to ask this question**, and stripped of the game that asked it. A
/// fragment shader cannot loop over every lamp in a building, so a game needs a budget for how many
/// may affect one draw and a rule for choosing which.
public nonisolated struct LightSet: Sendable {

    /// How many lights may affect one draw.
    ///
    /// **A shader constant in the end**, which is why it travels with the selection rule rather than
    /// being passed around separately: the two have to agree or the shader reads past its array.
    ///
    /// Four is what the finding below was measured against. A game may raise it — and should know
    /// that raising it moves the number at which the problem happens rather than solving it.
    public let budget: Int

    /// Influence below which a light can be dropped without the player seeing it go.
    ///
    /// In the same units as ``PunctualLight/influence(at:)`` — a contribution, so it is comparable to
    /// the sun's irradiance, which in this engine is a few units.
    public let negligible: Float

    public var lights: [PunctualLight]

    public init(lights: [PunctualLight] = [], budget: Int = 4, negligible: Float = 0.02) {
        self.lights = lights
        self.budget = max(0, budget)
        self.negligible = negligible
    }

    /// The lights that reach a point, strongest first, at most ``budget`` of them.
    public func affecting(_ point: SIMD3<Float>) -> [PunctualLight] {
        strongest { $0.influence(at: point) }
    }

    /// The lights that reach any part of a box, ranked by their best contribution to it.
    ///
    /// **What a per-draw selection actually wants.** Lights are chosen once per object, not per
    /// fragment, so the question is which lights matter to *this mesh* — and a light matters if it
    /// reaches the nearest part of it.
    public func affecting(_ bounds: BoundingBox) -> [PunctualLight] {
        strongest { $0.influence(at: bounds.closestPoint(to: $0.position)) }
    }

    private func strongest(by influence: (PunctualLight) -> Float) -> [PunctualLight] {
        lights
            .map { (light: $0, influence: influence($0)) }
            .filter { $0.influence > 0 }
            .sorted { $0.influence > $1.influence }
            .prefix(budget)
            .map(\.light)
    }

    /// Whether more lights than the budget are meaningfully lit at this point.
    ///
    /// ### The probe's real finding, and it is a constraint on levels rather than a bug in code
    ///
    /// **A hard budget cannot promise a smooth hand-over in an arbitrary arrangement.** If five lights
    /// all contribute at a point, one is dropped, and how visible that is depends entirely on how the
    /// level was built. Ordering by influence does not save it, and a bigger budget only moves the
    /// number at which it happens.
    ///
    /// So the promise is conditional, and this checks the condition: **where no more than ``budget``
    /// lights are above ``negligible``, nothing the player can see is ever dropped.** A level that
    /// violates it has a lighting fault built into its geometry — and one that is findable before it
    /// ships rather than after somebody reports a flicker in one corridor.
    public func isOverSubscribed(at point: SIMD3<Float>) -> Bool {
        lights.count { $0.influence(at: point) > negligible } > budget
    }

    /// Every point of a level worth checking, and whether any of them is over-subscribed.
    ///
    /// A convenience for exactly the check above, run over the places a player can stand.
    public func overSubscribedPoints(among points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        points.filter { isOverSubscribed(at: $0) }
    }
}
