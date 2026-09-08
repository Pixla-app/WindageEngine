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
enum SampleLevel {

    static let fileName = "sample-level"

    /// Where the file lives when the sample writes one: alongside the executable's own resources is
    /// not writable in every arrangement, so it goes to the user's Application Support — the one
    /// place a sandboxed *or* unsandboxed app can always write. See the engine's distribution rule.
    static var writableURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WindageSample", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("\(fileName).json")
    }

    /// Load the level: the user's copy if they have one, the bundled one otherwise, and failing both
    /// the built-in one — which is then written out so there is something to edit.
    static func load() -> (level: Level, source: String) {
        let url = writableURL
        if let data = try? Data(contentsOf: url), let level = try? Level.decode(from: data) {
            return (level, url.path)
        }
        if let level = try? Level.load(named: fileName, bundle: .module) {
            try? level.encoded().write(to: url)
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
    static var builtIn: Level {
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
        // A few crates in the yard, at angles, so rotation is visible.
        for (i, (x, z)) in [(Float(-5), Float(-6)), (3, -9), (6, -3), (-2, -12)].enumerated() {
            placements.append(Level.Placement(mesh: "box", position: SIMD3(x, 0, z),
                                              yaw: Float(i) * 0.4, scale: 1.5,
                                              anchor: .absolute, tags: ["solid"]))
        }

        return Level(name: "COURTYARD",
                     // **Lighting the faces the player is looking at.** The first sun here came from behind
                     // the scene, so every surface the camera could see was in shadow and the courtyard
                     // read as black boxes on grey. Worth stating because it is the mistake a reader will
                     // make too: a sun direction that sounds pleasant is not the one that lights the shot.
                     settings: ["sunPitch": 38, "sunYaw": 25],
                     placements: placements,
                     markers: [Level.Marker(kind: "spawn", name: "start",
                                            position: SIMD3(0, 0, 12), anchor: .absolute, yaw: 0)])
    }
}
