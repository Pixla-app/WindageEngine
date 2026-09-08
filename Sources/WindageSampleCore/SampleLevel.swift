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

    public static let fileName = "sample-level"

    /// Where the file lives when the sample writes one: alongside the executable's own resources is
    /// not writable in every arrangement, so it goes to the user's Application Support — the one
    /// place a sandboxed *or* unsandboxed app can always write. See the engine's distribution rule.
    public static var writableURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WindageSample", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("\(fileName).json")
    }

    /// Load the level: the copy the player has been editing, or the built-in one — which is then
    /// written out so there **is** something to edit.
    ///
    /// **The built-in level is code and the played level is a file, and that is the point.** The code
    /// says what a fresh install looks like; after that the file wins, and a game shipping its own
    /// levels would ship them as files in its bundle rather than as a function like this one.
    public static func load() -> (level: Level, source: String) {
        let url = writableURL
        if let data = try? Data(contentsOf: url), let level = try? Level.decode(from: data) {
            return (level, url.path)
        }
        let level = builtIn
        try? level.encoded().write(to: url)
        return (level, url.path)
    }

    /// A courtyard: a ground plane, a wall of boxes with a gap, and four towers.
    ///
    /// Small on purpose. It exists to be *changed* — the README asks the reader to move a tower —
    /// and a level with two hundred things in it hides the one they moved.
    /// Where the crates are. Named once so the placements and the objective markers cannot drift.
    public static let cratePositions: [(Float, Float)] = [(-5, -6), (3, -9), (6, -3), (-2, -12), (-8, -22), (9, -24)]

    public static var builtIn: Level {
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
