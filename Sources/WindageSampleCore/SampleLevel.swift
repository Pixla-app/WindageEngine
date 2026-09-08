//
//  SampleLevel.swift
//  WindageSample
//

import Foundation
import WindageEngine

/// The sample's levels: **two JSON files in this target's resources**, and nothing else.
///
/// **They used to be Swift functions that built a `Level` in code, and that was the sample teaching
/// the opposite of what the engine says.** The format's whole claim is that a level is data — a file
/// you open, edit and reload without a compiler — and the first thing anybody who clones this repo
/// reads is the sample. A level assembled by a function said the file was an export.
///
/// The files were generated once from those functions, so the courtyard is exactly the courtyard it
/// has always been, and the functions were deleted. There is one description of a level now, it is
/// the one the game loads, and a change to it is a readable diff rather than a Swift diff.
///
/// `nonisolated`, like the level format itself: a level's contents are data, and a game that wanted
/// to load one on a background thread should be able to.
public nonisolated enum SampleLevel {

    /// Every level the sample ships, in order. **Two, on purpose** — one is not enough to find out
    /// whether anything assumed there would only ever be one, and something always has.
    public static let names = ["courtyard", "ruins"]

    public static func fileName(_ index: Int) -> String {
        names[min(max(index, 0), names.count - 1)]
    }

    /// The level as shipped, from this target's bundle.
    ///
    /// **From a bundle and never from a path**, which is the engine's distribution rule: the sample
    /// has to run sandboxed or not, so it may not assume it can read wherever it likes.
    public static func bundled(_ index: Int) throws -> Level {
        try Level.load(named: fileName(index), bundle: .module)
    }

    /// Where the editor saves. A bundle is read-only in every arrangement that matters, so an edited
    /// level goes to the user's Application Support — the one place a sandboxed *or* unsandboxed app
    /// can always write.
    ///
    /// **`in:` exists so a test never writes to the real one.** The same lesson as `SaveStore`: a
    /// suite that reaches into the user's Application Support clobbers the level they were editing,
    /// and two tests running in parallel clobber each other.
    public static func writableURL(_ index: Int, in directory: URL? = nil) -> URL {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WindageSample", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("\(fileName(index)).json")
    }

    /// Which of the two files a load actually used.
    public enum Origin: Equatable {
        /// The file in the repository, compiled into the bundle.
        case shipped
        /// A copy the in-game editor has saved. **It shadows the shipped level from then on.**
        case edited
    }

    public struct Loaded {
        public let level: Level
        public let origin: Origin
        /// The file that was read, for printing.
        public let path: String
        /// The file that was *not* read. **Reported on purpose**: a reader who edits the shipped
        /// level, sees nothing change and has no idea an edited copy is shadowing it has been given
        /// a puzzle rather than a lesson.
        public let shadowedPath: String?

        /// One line for the console: which file the level came from, and what it is shadowing.
        public var report: String {
            guard origin == .edited else { return path }
            guard let shadowedPath else { return "\(path) (your edited copy)" }
            return "\(path) (your edited copy — shadowing \(shadowedPath))"
        }
    }

    /// Load a level: the copy the editor saved, or the one this repository ships.
    ///
    /// **Nothing is written here.** An earlier version copied the built-in level out to Application
    /// Support on first run, which meant the file the player edited and the file the repository
    /// shipped were different objects — and an install made before a level changed kept the old one
    /// silently, for ever, with nothing to say so.
    public static func load(_ index: Int, savedIn directory: URL? = nil) -> Loaded {
        let url = writableURL(index, in: directory)
        if let data = try? Data(contentsOf: url), let level = try? Level.decode(from: data) {
            let shipped = Bundle.module.url(forResource: fileName(index), withExtension: "json")
            return Loaded(level: level, origin: .edited, path: url.path, shadowedPath: shipped?.path)
        }
        do {
            let level = try bundled(index)
            let shipped = Bundle.module.url(forResource: fileName(index), withExtension: "json")
            return Loaded(level: level, origin: .shipped,
                          path: shipped?.path ?? fileName(index), shadowedPath: nil)
        } catch {
            // **Loud, and empty rather than wrong.** A level that failed to load must not look like
            // a level somebody authored with nothing in it.
            print("\(Engine.name): FAILED to load \(fileName(index)).json — \(error)")
            return Loaded(level: Level(name: "MISSING"), origin: .shipped,
                          path: fileName(index), shadowedPath: nil)
        }
    }

    /// Delete the editor's copy, so the shipped level is next in line again.
    @discardableResult
    public static func discardEdits(_ index: Int, in directory: URL? = nil) -> Bool {
        (try? FileManager.default.removeItem(at: writableURL(index, in: directory))) != nil
    }
}
