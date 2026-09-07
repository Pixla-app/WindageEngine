import Testing
import Foundation
import simd
@testable import WindageEngine

/// The format's contract. **A level file outlives the code that wrote it**, so what is guarded here
/// is round-tripping, defaults, and refusing a file this build cannot honestly read.
struct LevelTests {

    private func sample() -> Level {
        Level(name: "TEST RANGE",
              settings: ["sunAngle": 42.5, "par": 90],
              placements: [
                Placement(mesh: "wall", position: SIMD3(-60, 0, -560)),
                Placement(mesh: "hab", position: SIMD3(12, 0, -600), yaw: 0.4,
                          anchor: .beddedFootprint, tags: ["solid"]),
                Placement(mesh: "sign", position: SIMD3(0, 14, -300), scale: 2,
                          anchor: .absolute, tags: ["decorative", "emissive"]),
              ],
              markers: [
                Marker(kind: "firing-position", name: "THE BROW", position: SIMD3(0, 0, 14), yaw: 0.06),
                Marker(kind: "target", position: SIMD3(-4, 0, -150), values: ["range": 150]),
              ])
    }

    private typealias Placement = Level.Placement
    private typealias Marker = Level.Marker

    @Test("A level survives the round trip unchanged")
    func roundTrips() throws {
        let original = sample()
        let decoded = try Level.decode(from: try original.encoded())
        #expect(decoded == original)
    }

    /// **Encoding twice must give byte-identical output**, or every save produces a diff whether or
    /// not anything changed, and the format stops being reviewable.
    @Test("Encoding is stable")
    func encodingIsStable() throws {
        let level = sample()
        #expect(try level.encoded() == level.encoded())
        let reEncoded = try Level.decode(from: try level.encoded()).encoded()
        #expect(try reEncoded == level.encoded())
    }

    /// Defaults are omitted, so a level of mostly-default props is a small file and a small diff.
    @Test("Defaults are not written out")
    func defaultsAreOmitted() throws {
        let level = Level(name: "bare", placements: [Placement(mesh: "rock", position: .zero)])
        let json = String(data: try level.encoded(), encoding: .utf8)!
        #expect(!json.contains("\"yaw\""))
        #expect(!json.contains("\"scale\""))
        #expect(!json.contains("\"anchor\""))
        #expect(!json.contains("\"tags\""))
        #expect(json.contains("\"mesh\""))
    }

    /// And a file that omits them decodes to those same defaults.
    @Test("An omitted field decodes to its default")
    func omittedFieldsTakeDefaults() throws {
        let json = """
        {"formatVersion":1,"name":"minimal","settings":{},"markers":[],
         "placements":[{"mesh":"rock","position":[1,2,3]}]}
        """
        let level = try Level.decode(from: Data(json.utf8))
        let placement = try #require(level.placements.first)
        #expect(placement.yaw == 0)
        #expect(placement.scale == 1)
        #expect(placement.anchor == .ground)
        #expect(placement.tags.isEmpty)
        #expect(placement.position == SIMD3(1, 2, 3))
    }

    /// **A newer file must be refused, not partly read.** Loading it anyway drops whatever this build
    /// does not understand, and the symptom is level geometry quietly missing.
    @Test("A newer format version is refused")
    func refusesANewerVersion() throws {
        let json = """
        {"formatVersion":999,"name":"future","settings":{},"placements":[],"markers":[]}
        """
        #expect(throws: Level.LoadError.unsupportedVersion(found: 999, supported: Level.currentVersion)) {
            try Level.decode(from: Data(json.utf8))
        }
    }

    @Test("A missing level names itself in the error")
    func missingLevelIsNamed() {
        #expect(throws: Level.LoadError.notFound("nope")) {
            try Level.load(named: "nope", bundle: .module)
        }
    }

    @Test("Queries filter by tag and kind, in file order")
    func queries() {
        let level = sample()
        #expect(level.placements(tagged: "solid").map(\.mesh) == ["hab"])
        #expect(level.placements(tagged: "decorative").map(\.mesh) == ["sign"])
        #expect(level.markers(ofKind: "target").count == 1)
        #expect(level.markers(ofKind: "firing-position").first?.name == "THE BROW")
        #expect(level.markers(ofKind: "nothing-of-the-sort").isEmpty)
    }

    /// The engine must not learn what a marker means. If this list ever needs extending to make a
    /// game work, the game is asking the format to have an opinion it must not have.
    @Test("The engine has no opinion about what a kind or tag means")
    func kindsAreOpen() {
        let level = Level(name: "any", markers: [
            Marker(kind: "anchorage", position: .zero),
            Marker(kind: "whatever-a-game-wants", position: .zero),
        ])
        #expect(level.markers(ofKind: "anchorage").count == 1)
        #expect(level.markers(ofKind: "whatever-a-game-wants").count == 1)
    }
}
