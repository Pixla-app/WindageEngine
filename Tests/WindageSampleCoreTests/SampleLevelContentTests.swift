import Testing
import simd
import WindageEngine
@testable import WindageSampleCore

/// **What the shipped levels promise about themselves** — checks on the files, not on code.
struct SampleLevelContentTests {

    /// **A brazier carries its own flame, above its rim.** The flame used to be a separate entry in
    /// the level's lights, kept over the brazier only by a test like this one; now the brazier holds
    /// it, and what is left to check is that it is there and not inside the bowl —
    /// `Tools/make_sample_brazier.py` puts the rim at 1.08 m.
    @Test("Every brazier carries a lamp above its rim")
    func braziersCarryLamps() throws {
        let rim: Float = 1.08
        for index in SampleLevel.names.indices {
            let level = try SampleLevel.bundled(index)
            for brazier in level.placements where brazier.mesh == "brazier" {
                let lamp = try #require(brazier.light, "\(SampleLevel.names[index]): a brazier with no lamp")
                #expect(lamp.cone == nil)
                #expect(abs(lamp.position.x) < 1e-4 && abs(lamp.position.z) < 1e-4,
                        "\(SampleLevel.names[index]): the flame is not over the bowl")
                #expect(lamp.position.y > (rim + 0.3) * brazier.scale,
                        "\(SampleLevel.names[index]): the lamp is inside its bowl")
            }
        }
    }

    /// **No lamp floating in the air.** A light that points nowhere and belongs to nothing is exactly
    /// what the ruins had before the braziers — embers out of thin air. Aimed lights stay free: a
    /// spot on a pole the level does not draw is a stage light, and says so by having a cone.
    @Test("Every lamp that points nowhere belongs to something")
    func noFloatingLamps() throws {
        for index in SampleLevel.names.indices {
            let level = try SampleLevel.bundled(index)
            let floating = level.lights.filter { $0.cone == nil }
            #expect(floating.isEmpty, "\(SampleLevel.names[index]): \(floating.map(\.position)) float")
        }
    }
}
