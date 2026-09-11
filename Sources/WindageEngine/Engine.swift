//
//  Engine.swift
//  WindageEngine
//

/// Identifying information for the engine itself.
public nonisolated enum Engine {
    public static let name = "Windage Engine"

    /// The engine's version, as a value rather than a string.
    ///
    /// **One source of truth**, and everything else formats it. A version that also lives in a
    /// window title, a build setting and a changelog is a version that will eventually disagree
    /// with itself, and the disagreement surfaces in a bug report from somebody else's machine.
    public static let semanticVersion = SemanticVersion(major: 0, minor: 8, patch: 0)

    /// The version as `major.minor.patch`.
    public static var version: String { semanticVersion.description }
}

/// A semantic version, comparable so a consumer can check what it is building against.
///
/// ### What the numbers promise here
///
/// **The engine is pre-1.0, and that changes what a bump means.** Semantic Versioning gives `0.x`
/// no compatibility guarantee at all, which is honest but useless to depend on, so this repository
/// narrows it to the convention everybody actually uses before 1.0:
///
/// | | means |
/// |---|---|
/// | **minor** — 0.1 → 0.2 | Something changed that can break a build: a signature, a type, a
/// removed declaration, or a default that alters behaviour. |
/// | **patch** — 0.1.0 → 0.1.1 | Additions and fixes only. Code that compiled still compiles and
/// still does the same thing. |
///
/// So a consumer pins `.upToNextMinor(from: "0.1.0")` and gets fixes without surprises. After 1.0
/// this becomes ordinary Semantic Versioning and the major carries the breakage.
///
/// **The reversed-Z convention, the depth clear value and the vertex-descriptor contract count as
/// API even though they are not signatures.** Changing any of them breaks a consumer in a way that
/// compiles and then renders nothing, which is worse than a compile error, so they move the minor.
public nonisolated struct SemanticVersion: Sendable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `major.minor.patch`, rejecting anything else — including a leading `v`, which is not
    /// how a SwiftPM tag is written.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let major = Int(parts[0]), let minor = Int(parts[1]),
              let patch = Int(parts[2]), major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}
