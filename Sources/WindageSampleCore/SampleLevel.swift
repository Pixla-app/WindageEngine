//
//  SampleLevel.swift
//  WindageSample
//

import Foundation
import simd
import WindageEngine

/// The sample's level, written out if it is missing.
///
/// **Generated on first run rather than committed as a blob**, so the reader can see in code what
/// the file contains, then go and edit the file and watch it change. That is the whole lesson: the
/// level is data, and the code that made it is not privileged.
/// `nonisolated`, like the level format it builds: a level's contents are data, and a game that
/// wanted to load one on a background thread should be able to.
public nonisolated enum SampleLevel {

    /// Every level the sample ships, in order. **Two, on purpose** — one is not enough to find out
    /// whether anything assumed there would only ever be one, and something always has.
    public static let names = ["courtyard", "ruins"]

    public static func fileName(_ index: Int) -> String {
        names[min(max(index, 0), names.count - 1)]
    }

    /// Where the file lives when the sample writes one: alongside the executable's own resources is
    /// not writable in every arrangement, so it goes to the user's Application Support — the one
    /// place a sandboxed *or* unsandboxed app can always write. See the engine's distribution rule.
    public static func writableURL(_ index: Int) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WindageSample", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("\(fileName(index)).json")
    }

    /// Load the level: the copy the player has been editing, or the built-in one — which is then
    /// written out so there **is** something to edit.
    ///
    /// **The built-in level is code and the played level is a file, and that is the point.** The code
    /// says what a fresh install looks like; after that the file wins, and a game shipping its own
    /// levels would ship them as files in its bundle rather than as a function like this one.
    public static func load(_ index: Int) -> (level: Level, source: String) {
        let url = writableURL(index)
        if let data = try? Data(contentsOf: url), let level = try? Level.decode(from: data) {
            return (level, url.path)
        }
        let level = builtIn(index)
        try? level.encoded().write(to: url)
        return (level, url.path)
    }

    public static func builtIn(_ index: Int) -> Level {
        index == 1 ? ruins : courtyard
    }

    /// A courtyard: a ground plane, a wall of boxes with a gap, and four towers.
    ///
    /// Small on purpose. It exists to be *changed* — the README asks the reader to move a tower —
    /// and a level with two hundred things in it hides the one they moved.
    /// The second level. **Its job is to be different in the ways that break assumptions**, not to
    /// be a better courtyard:
    ///
    /// | it differs by | what that catches |
    /// |---|---|
    /// | a mesh the first level never uses | meshes loaded once at startup, from the first level's list |
    /// | a different spawn and facing | a camera placed in `init` and never moved |
    /// | a different number of objectives | a run sized once from the first level |
    /// | a different sun | per-level settings read at load rather than at startup |
    ///
    /// Every one of those was a real assumption in this sample before there was a second level to
    /// find it, which is the whole argument for shipping two.
    public static var ruins: Level {
        var placements: [Level.Placement] = [
            Level.Placement(mesh: "ground", position: SIMD3(0, 0, 0), anchor: .absolute, tags: ["ground"]),
        ]

        // An avenue of pillars — a mesh the courtyard does not have.
        for row in 0..<6 {
            for side in [Float(-7), 7] {
                placements.append(Level.Placement(mesh: "pillar",
                                                  position: SIMD3(side, 0, -8 - Float(row) * 9),
                                                  yaw: Float(row) * 0.12,
                                                  anchor: .absolute, tags: ["solid", "landmark"]))
            }
        }
        // A ruined block at the far end, to walk around rather than through.
        for i in -3...3 {
            placements.append(Level.Placement(mesh: "box", position: SIMD3(Float(i) * 2.2, 0, -62),
                                              yaw: Float(i) * 0.2, scale: 2.4,
                                              anchor: .absolute, tags: ["solid"]))
        }
        for (i, (x, z)) in SampleLevel.ruinCratePositions.enumerated() {
            placements.append(Level.Placement(mesh: "box", position: SIMD3(x, 0, z),
                                              yaw: Float(i) * 0.55, scale: 1.5,
                                              anchor: .absolute, tags: ["solid", "objective"]))
        }

        return Level(name: "RUINS",
                     // A low sun from the other side, so the two levels do not read as one repainted.
                     settings: ["sunPitch": 22, "sunYaw": -40],
                     placements: placements,
                     markers: [Level.Marker(kind: "spawn", name: "start",
                                            position: SIMD3(0, 0, 6), anchor: .absolute, yaw: 0,
                                            values: ["pitch": -6])]
                         + SampleLevel.ruinCratePositions.map {
                             Level.Marker(kind: "objective", position: SIMD3($0.0, 0, $0.1),
                                          anchor: .absolute)
                         })
    }

    /// **Nine, where the courtyard has six** — so a run sized from the first level is visibly wrong.
    public static let ruinCratePositions: [(Float, Float)] = [
        (-4, -14), (5, -21), (-6, -30), (3, -37), (-2, -45),
        (6, -52), (-5, -58), (0, -66), (4, -70),
    ]

    /// Where the crates are. Named once so the placements and the objective markers cannot drift.
    public static let cratePositions: [(Float, Float)] = [(-5, -6), (3, -9), (6, -3), (-2, -12), (-8, -22), (9, -24)]

    public static var courtyard: Level {
        var placements: [Level.Placement] = [
            Level.Placement(mesh: "ground", position: SIMD3(0, 0, 0), anchor: .absolute,
                            tags: ["ground"]),
        ]

        // A wall running east–west, with a four-metre gap in the middle to walk through.
        for i in -8...8 where abs(i) > 1 {
            placements.append(Level.Placement(mesh: "box", position: SIMD3(Float(i) * 2, 0, -18),
                                              scale: 2, anchor: .absolute, tags: ["solid"]))
        }
        // Corner towers, so there is something to judge distance and rotation against.
        for (x, z) in [(Float(-18), Float(-18)), (18, -18), (-18, 6), (18, 6)] {
            placements.append(Level.Placement(mesh: "tower", position: SIMD3(x, 0, z),
                                              anchor: .absolute, tags: ["solid", "landmark"]))
        }
        // A few crates in the yard, at angles, so rotation is visible. **These are the objectives**
        // — the marker beside each one is what the game reads, and the crate is what you see. Two
        // records of the same thing, which is a level-authoring smell, but the alternative is the
        // engine knowing that a placement can be an objective, which it must not.
        for (i, (x, z)) in SampleLevel.cratePositions.enumerated() {
            placements.append(Level.Placement(mesh: "box", position: SIMD3(x, 0, z),
                                              yaw: Float(i) * 0.4, scale: 1.5,
                                              anchor: .absolute, tags: ["solid", "objective"]))
        }

        return Level(name: "COURTYARD",
                     // **Lighting the faces the player is looking at.** The first sun here came from behind
                     // the scene, so every surface the camera could see was in shadow and the courtyard
                     // read as black boxes on grey. Worth stating because it is the mistake a reader will
                     // make too: a sun direction that sounds pleasant is not the one that lights the shot.
                     settings: ["sunPitch": 38, "sunYaw": 25],
                     placements: placements,
                     // **`values` carries the pitch**, which is the format's per-marker numbers
                     // doing real work: the opening view is authored rather than whatever the camera
                     // happened to default to, and looking level at the horizon meant the crosshair
                     // pointed at sky.
                     markers: [Level.Marker(kind: "spawn", name: "start",
                                            position: SIMD3(0, 0, 12), anchor: .absolute, yaw: 0,
                                            values: ["pitch": -10])]
                         + SampleLevel.cratePositions.map {
                             Level.Marker(kind: "objective", position: SIMD3($0.0, 0, $0.1),
                                          anchor: .absolute)
                         })
    }
}
