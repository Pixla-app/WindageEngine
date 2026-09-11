import Testing
import simd
import WindageEngine
@testable import WindageSampleCore

/// **What the shipped levels promise about themselves** — checks on the files, not on code.
struct SampleLevelContentTests {

    /// **A lamp with nothing under it is a light in mid-air**, which is what the ruins had until the
    /// particles made it obvious: embers rising out of nothing. A level stores its lights and its
    /// meshes separately, so nothing keeps the two together except this.
    ///
    /// The light has to sit **above the rim**, too — `Tools/make_sample_brazier.py` puts it at
    /// 1.08 m — or the lamp is inside its own bowl, and the bowl shadows the whole room from it.
    @Test("Every lamp that points nowhere stands over a brazier, above its rim")
    func lampsHaveBraziers() throws {
        let rim: Float = 1.08
        for index in SampleLevel.names.indices {
            let level = try SampleLevel.bundled(index)
            let braziers = level.placements.filter { $0.mesh == "brazier" }.map(\.position)
            for lamp in level.lights where lamp.cone == nil {
                let under = braziers.first {
                    simd_distance(SIMD2($0.x, $0.z), SIMD2(lamp.position.x, lamp.position.z)) < 0.3
                }
                #expect(under != nil, "\(SampleLevel.names[index]): a lamp at \(lamp.position) has no brazier")
                if let under {
                    #expect(lamp.position.y > under.y + rim + 0.3,
                            "\(SampleLevel.names[index]): the lamp at \(lamp.position) is in its bowl")
                }
            }
        }
    }

    /// And the other way: a brazier with no lamp is cold iron with glowing coals that light nothing.
    @Test("Every brazier has its lamp")
    func braziersHaveLamps() throws {
        for index in SampleLevel.names.indices {
            let level = try SampleLevel.bundled(index)
            for brazier in level.placements where brazier.mesh == "brazier" {
                let lit = level.lights.contains {
                    $0.cone == nil
                        && simd_distance(SIMD2($0.position.x, $0.position.z),
                                         SIMD2(brazier.position.x, brazier.position.z)) < 0.3
                }
                #expect(lit, "\(SampleLevel.names[index]): the brazier at \(brazier.position) has no lamp")
            }
        }
    }
}
