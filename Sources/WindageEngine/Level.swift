//
//  Level.swift
//  WindageEngine
//

import Foundation
import simd

/// A level, as **data rather than code**.
///
/// ### Why this exists, and what it is deliberately not
///
/// Before this, the engine's only consumer described its level in Swift: arrays of structs, compiled
/// into the game. That works exactly once, for the person who owns the source. **Nobody else can
/// author a level for a game built that way** — not a designer without Xcode, not a modder, not a
/// tool, and not an editor, which is the thing this is the prerequisite for. An engine whose levels
/// are source files is a library with a game attached.
///
/// So a level is a file. It is JSON because a format nobody can read by hand is a format nobody can
/// fix at 2am, and because the first "editor" for any format is a text editor.
///
/// ### What the engine knows about a level, and what it refuses to know
///
/// The engine knows a level is **things placed in space** and **points that mean something**. It does
/// not know what they mean. `Marker.kind` is a string the *game* interprets: Coldkeel reads
/// `"target"` and `"firing-position"`, a pirate game would read `"anchorage"`, and the engine reads
/// neither. The same goes for ``Placement/tags``.
///
/// **This is the line that keeps the engine an engine.** The moment `Marker` gains a `.target` case,
/// the format has an opinion about genre, and every game that does not share it is fighting the
/// format. A string and a dictionary are less tidy and cost nothing to be wrong about.
///
/// ### Heights are anchored, not absolute
///
/// A placement stores **how it meets the ground**, not the height it happened to sit at when someone
/// pressed save. Terrain changes — Coldkeel's valley grew a cross-section and every structure in it
/// moved tens of metres — and a level of absolute Y values silently becomes a level of floating and
/// buried buildings. See ``Anchor``.
/// **`nonisolated`, like every other value type here.** A level is data; loading one is I/O and
/// decoding, and tying it to the main actor would mean a game could not read a level off the main
/// thread — which is exactly what a game wants to do while a loading screen is up.
public nonisolated struct Level: Codable, Equatable, Sendable {

    /// **The format's own version, checked on load.**
    ///
    /// A level file outlives the code that wrote it. Without a version, a file written by a newer
    /// build loads into an older one, silently missing whatever it did not understand — and the
    /// failure surfaces as level geometry quietly absent rather than as a refusal to load.
    public static let currentVersion = 1

    public var formatVersion: Int
    public var name: String

    /// Free-form per-level values the game interprets — a sun angle, a wind seed, a par time.
    ///
    /// **Deliberately `[String: Double]` and not `Any`.** A heterogeneous bag needs custom coding,
    /// makes round-tripping lossy, and invites a level file to become a config file for the whole
    /// game. Anything that is not a number belongs in ``markers`` or in the game's own files.
    public var settings: [String: Double]

    public var placements: [Placement]
    public var markers: [Marker]

    public init(name: String,
                settings: [String: Double] = [:],
                placements: [Placement] = [],
                markers: [Marker] = []) {
        self.formatVersion = Level.currentVersion
        self.name = name
        self.settings = settings
        self.placements = placements
        self.markers = markers
    }

    /// How a placement meets the ground.
    public nonisolated enum Anchor: String, Codable, Equatable, Sendable {
        /// `y` is a world height. For things that genuinely float — a gantry, a sign, an aircraft.
        case absolute
        /// `y` is an offset from the ground under the placement's origin.
        case ground
        /// `y` is an offset from the **lowest** ground under the placement's footprint, so a long
        /// building on a slope beds into the hill rather than standing with one end in the air.
        case beddedFootprint
    }

    /// One thing, placed.
    public nonisolated struct Placement: Codable, Equatable, Sendable {
        /// The mesh's resource name. The engine does not resolve it — the game does, from wherever
        /// its meshes live.
        public var mesh: String
        /// Metres. `y` is interpreted per ``anchor``.
        public var position: SIMD3<Float>
        /// Radians about +Y.
        public var yaw: Float
        public var scale: Float
        public var anchor: Anchor
        /// Game-defined labels — `"solid"`, `"cover"`, `"decorative"`. The engine passes them through.
        public var tags: [String]

        public init(mesh: String,
                    position: SIMD3<Float>,
                    yaw: Float = 0,
                    scale: Float = 1,
                    anchor: Anchor = .ground,
                    tags: [String] = []) {
            self.mesh = mesh
            self.position = position
            self.yaw = yaw
            self.scale = scale
            self.anchor = anchor
            self.tags = tags
        }

        // Written long-hand so the JSON stays small and stable: yaw, scale, anchor and tags are all
        // omitted at their defaults. A level of four hundred props is mostly defaults, and a format
        // that writes them all is four times the file and four times the diff.
        private enum CodingKeys: String, CodingKey {
            case mesh, position, yaw, scale, anchor, tags
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mesh = try container.decode(String.self, forKey: .mesh)
            position = try container.decode(SIMD3<Float>.self, forKey: .position)
            yaw = try container.decodeIfPresent(Float.self, forKey: .yaw) ?? 0
            scale = try container.decodeIfPresent(Float.self, forKey: .scale) ?? 1
            anchor = try container.decodeIfPresent(Anchor.self, forKey: .anchor) ?? .ground
            tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(mesh, forKey: .mesh)
            try container.encode(position, forKey: .position)
            if yaw != 0 { try container.encode(yaw, forKey: .yaw) }
            if scale != 1 { try container.encode(scale, forKey: .scale) }
            if anchor != .ground { try container.encode(anchor, forKey: .anchor) }
            if !tags.isEmpty { try container.encode(tags, forKey: .tags) }
        }
    }

    /// A point that means something to the game.
    ///
    /// Spawns, objectives, patrol nodes, cameras, trigger volumes' centres. **``kind`` is the game's
    /// word, not the engine's** — see the type's own notes.
    public nonisolated struct Marker: Codable, Equatable, Sendable {
        public var kind: String
        public var name: String?
        public var position: SIMD3<Float>
        public var anchor: Anchor
        /// Radians about +Y — which way it faces, where that means anything.
        public var yaw: Float
        /// Per-marker numbers the game interprets: a radius, a delay, a difficulty.
        public var values: [String: Double]

        public init(kind: String,
                    name: String? = nil,
                    position: SIMD3<Float>,
                    anchor: Anchor = .ground,
                    yaw: Float = 0,
                    values: [String: Double] = [:]) {
            self.kind = kind
            self.name = name
            self.position = position
            self.anchor = anchor
            self.yaw = yaw
            self.values = values
        }

        private enum CodingKeys: String, CodingKey { case kind, name, position, anchor, yaw, values }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(String.self, forKey: .kind)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            position = try container.decode(SIMD3<Float>.self, forKey: .position)
            anchor = try container.decodeIfPresent(Anchor.self, forKey: .anchor) ?? .ground
            yaw = try container.decodeIfPresent(Float.self, forKey: .yaw) ?? 0
            values = try container.decodeIfPresent([String: Double].self, forKey: .values) ?? [:]
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encode(position, forKey: .position)
            if anchor != .ground { try container.encode(anchor, forKey: .anchor) }
            if yaw != 0 { try container.encode(yaw, forKey: .yaw) }
            if !values.isEmpty { try container.encode(values, forKey: .values) }
        }
    }

    // MARK: - Queries

    /// Every placement carrying a tag. The game's way of asking "what is solid here".
    public func placements(tagged tag: String) -> [Placement] {
        placements.filter { $0.tags.contains(tag) }
    }

    /// Every marker of a kind, in file order — which is authoring order, and therefore stable.
    public func markers(ofKind kind: String) -> [Marker] {
        markers.filter { $0.kind == kind }
    }
}

// MARK: - Anchors

nonisolated extension Level {

    /// What the engine needs from the game to turn an anchored placement into a world position.
    ///
    /// **Closures rather than a protocol the game must conform to, and rather than the engine owning
    /// terrain.** Only the game knows what its ground is — Coldkeel's is a height *function* with no
    /// mesh behind it — and only the game knows how big its meshes are. What the engine does know is
    /// what an anchor *means*, and that meaning is identical in every game, so it lives here instead
    /// of being re-derived per title.
    public struct Ground: Sendable {
        /// Ground height at a world x/z.
        public let heightAt: @Sendable (Float, Float) -> Float

        /// A mesh's footprint corners in **its own model space**, for ``Anchor/beddedFootprint``.
        /// Returning none is fine — the placement then beds on its origin alone.
        public let footprintCorners: @Sendable (String) -> [SIMD2<Float>]

        public init(heightAt: @escaping @Sendable (Float, Float) -> Float,
                    footprintCorners: @escaping @Sendable (String) -> [SIMD2<Float>] = { _ in [] }) {
            self.heightAt = heightAt
            self.footprintCorners = footprintCorners
        }
    }

    /// Where a placement actually stands.
    ///
    /// The stored `y` is an **offset** for the ground anchors and a world height for `.absolute`, so
    /// a level authored on one terrain still sits on the ground after the terrain changes.
    public func worldPosition(of placement: Placement, on ground: Ground) -> SIMD3<Float> {
        let x = placement.position.x, z = placement.position.z
        switch placement.anchor {
        case .absolute:
            return placement.position
        case .ground:
            return SIMD3(x, ground.heightAt(x, z) + placement.position.y, z)
        case .beddedFootprint:
            // The **lowest** corner, not the average and not the origin: bedding to anything higher
            // leaves the low end of a long building in the air, which is the failure this exists for.
            var lowest = ground.heightAt(x, z)
            let c = cos(placement.yaw), s = sin(placement.yaw)
            for corner in ground.footprintCorners(placement.mesh) {
                let scaled = corner * placement.scale
                lowest = min(lowest, ground.heightAt(x + scaled.x * c - scaled.y * s,
                                                    z + scaled.x * s + scaled.y * c))
            }
            return SIMD3(x, lowest + placement.position.y, z)
        }
    }

    /// The same, for a marker.
    public func worldPosition(of marker: Marker, on ground: Ground) -> SIMD3<Float> {
        switch marker.anchor {
        case .absolute: return marker.position
        default: return SIMD3(marker.position.x,
                              ground.heightAt(marker.position.x, marker.position.z) + marker.position.y,
                              marker.position.z)
        }
    }
}

// MARK: - Reading and writing

nonisolated extension Level {

    public enum LoadError: Error, CustomStringConvertible, Equatable {
        case notFound(String)
        case unsupportedVersion(found: Int, supported: Int)

        public var description: String {
            switch self {
            case .notFound(let name):
                return "no level named '\(name)' in the bundle"
            case .unsupportedVersion(let found, let supported):
                return "level format version \(found); this build understands \(supported)"
            }
        }
    }

    /// Decode a level, refusing one written by a newer format.
    public static func decode(from data: Data) throws -> Level {
        let level = try JSONDecoder().decode(Level.self, from: data)
        guard level.formatVersion <= Level.currentVersion else {
            throw LoadError.unsupportedVersion(found: level.formatVersion, supported: Level.currentVersion)
        }
        return level
    }

    /// **From a bundle, never from an arbitrary path.** The engine has to run sandboxed or not — see
    /// the studio's distribution rule — so it may not assume it can read wherever it likes.
    public static func load(named name: String, extension ext: String = "json", bundle: Bundle) throws -> Level {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw LoadError.notFound(name)
        }
        return try decode(from: try Data(contentsOf: url))
    }

    /// Encode, sorted and pretty-printed.
    ///
    /// **Both of those are for the diff, not for looks.** A level file is edited by tools and read by
    /// people in pull requests; unsorted keys mean a save with no changes still produces a diff, and
    /// one line of JSON means every change produces the same useless one-line diff.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
