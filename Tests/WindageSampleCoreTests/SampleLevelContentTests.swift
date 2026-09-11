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

    /// **Every solid names what it is made of, and the sample can make that sound.** A solid with no
    /// surface falls back to stone with a line in the log; one with a surface the sample has no
    /// footsteps for would fall back silently. Both are gaps in the file, and this finds them first.
    @Test("Every solid, and the ground, names a surface the sample has footsteps for")
    func surfacesAreNamedAndHeard() throws {
        for index in SampleLevel.names.indices {
            let level = try SampleLevel.bundled(index)
            #expect(level.groundSurface.map(SampleLevel.footstepSurfaces.contains) == true,
                    "\(level.name) does not say what its ground is")
            for (i, placement) in level.placements.enumerated() where placement.tags.contains("solid") {
                #expect(placement.surface.map(SampleLevel.footstepSurfaces.contains) == true,
                        "\(level.name) #\(i) \(placement.mesh) is '\(placement.surface ?? "nothing")'")
            }
        }
    }

    /// The ruins' landing is boards laid where the stone treads end — the one place underfoot that
    /// changes material without changing shape, which is what the footstep has to follow.
    @Test("The ruins have a wooden landing at the top of stone stairs")
    func woodenLanding() throws {
        let ruins = try SampleLevel.bundled(1)
        // The lintel is cut from the same stone step, laid across two posts — it is not a tread.
        let treads = ruins.placements.filter { ($0.mesh == "step" || $0.mesh == "step_wood") && !$0.tags.contains("lintel") }
        #expect(treads.filter { $0.surface == "wood" }.count == 3)
        #expect(treads.filter { $0.surface == "stone" }.count == 3)
    }

    /// **The lintel is there to be crouched under**: its underside above a crouched body and below a
    /// standing one, so walking under it means crouching and letting go under it means staying down.
    @Test("The ruins' lintel is low enough to need a crouch and high enough to allow one")
    func lintelNeedsACrouch() throws {
        let ruins = try SampleLevel.bundled(1)
        let lintels = ruins.placements.filter { $0.tags.contains("lintel") }
        #expect(lintels.count == 2)
        let tuning = CharacterController.Tuning()
        let crouchedTop = tuning.bodyHeight(for: tuning.crouchedEyeHeight)
        let standingTop = tuning.bodyHeight(for: tuning.eyeHeight)
        for lintel in lintels {
            #expect(lintel.position.y > crouchedTop && lintel.position.y < standingTop,
                    "the lintel's underside at \(lintel.position.y) m should lie between \(crouchedTop) and \(standingTop)")
        }
    }
}
