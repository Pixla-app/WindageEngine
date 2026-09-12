//
//  EngineMarkTests.swift
//  WindageEngineTests
//

import Foundation
import Testing
import simd
@testable import WindageEngine

/// **The mark on disk and the mark on screen are one drawing.**
///
/// `Brand/windage-engine.svg` is not a second copy of the device: it is written from
/// ``EngineMark/pieces``, by the function below, and this suite fails if the file and the array
/// disagree. Redraw the mark by editing the numbers in `EngineMark` and re-recording:
///
/// ```
/// WINDAGE_RECORD_MARK=1 swift test --filter EngineMarkTests
/// ```
///
/// The studio's brand notes make the case about a wordmark — *one drawing, or the imitations drift* —
/// and a device is no different. The failure this prevents is the ordinary one: somebody nudges the
/// curve in Swift because it looked thin on screen, and the file a site and a store page are served
/// from goes on showing the old one for a year.
@Suite("The engine's mark")
struct EngineMarkTests {

    /// Where `Brand/` is, from this file rather than from a working directory a test runner chooses.
    static var brand: URL {
        URL(fileURLWithPath: #filePath)          // …/Tests/WindageEngineTests/EngineMarkTests.swift
            .deletingLastPathComponent()          // …/Tests/WindageEngineTests
            .deletingLastPathComponent()          // …/Tests
            .deletingLastPathComponent()          // …/
            .appendingPathComponent("Brand")
    }

    /// A number as short as it can be written without changing it — so the file is stable from one
    /// recording to the next and a diff shows a moved point rather than a reformatted one.
    static func number(_ value: Float) -> String {
        let rounded = (Double(value) * 10_000).rounded() / 10_000
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    /// The mark as SVG at `scale` units per unit of the mark's height, in one flat colour.
    static func svg(scale: Float, colour: String) -> String {
        let width = EngineMark.aspect * scale
        var lines = [
            "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(number(width)) \(number(scale))\""
                + " width=\"\(number(width))\" height=\"\(number(scale))\" role=\"img\""
                + " aria-label=\"\(Engine.name)\">",
            "  <title>\(Engine.name)</title>",
            "  <desc>The aim, and the path carried off it. Generated from EngineMark.pieces —"
                + " see Brand/README.md.</desc>",
        ]
        for piece in EngineMark.pieces {
            let thickness = number(piece.thickness * scale)
            let opacity = number(piece.tone)
            if piece.points.count == 1 {
                let side = piece.thickness * scale
                let centre = piece.points[0] * scale
                lines.append("  <rect x=\"\(number(centre.x - side / 2))\" y=\"\(number(centre.y - side / 2))\""
                             + " width=\"\(thickness)\" height=\"\(thickness)\""
                             + " fill=\"\(colour)\" fill-opacity=\"\(opacity)\"/>")
            } else {
                let points = piece.points
                    .map { "\(number($0.x * scale)),\(number($0.y * scale))" }
                    .joined(separator: " ")
                lines.append("  <polyline points=\"\(points)\" fill=\"none\" stroke=\"\(colour)\""
                             + " stroke-opacity=\"\(opacity)\" stroke-width=\"\(thickness)\""
                             + " stroke-linecap=\"butt\" stroke-linejoin=\"round\"/>")
            }
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The two files, and which ground each is for. **Two tones of one achromatic mark, not two
    /// colours** — see ``EngineMark``.
    static let files: [(name: String, colour: String, tone: UIColor)] = [
        ("windage-engine.svg", "#1B2027", EngineMark.deep),
        ("windage-engine-display.svg", "#F2F4F7", EngineMark.display),
    ]

    @Test("The mark in Brand/ is the mark in the code", arguments: files.map(\.name))
    func fileMatchesTheGeometry(name: String) throws {
        let entry = try #require(Self.files.first { $0.name == name })
        let wanted = Self.svg(scale: 100, colour: entry.colour)
        let url = Self.brand.appendingPathComponent(name)

        if ProcessInfo.processInfo.environment["WINDAGE_RECORD_MARK"] != nil {
            try FileManager.default.createDirectory(at: Self.brand, withIntermediateDirectories: true)
            try wanted.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        let complaint = "\(name) is not what EngineMark.pieces draws. Re-record it: "
            + "WINDAGE_RECORD_MARK=1 swift test --filter EngineMarkTests"
        #expect(onDisk == wanted, "\(complaint)")
    }

    /// The file's colour is the tone it is for, written out — so a hand edit to one of them fails here
    /// rather than being discovered on a store page.
    @Test("Each file carries its own tone", arguments: files.map(\.name))
    func toneMatches(name: String) throws {
        let entry = try #require(Self.files.first { $0.name == name })
        let expected = SIMD3(entry.tone.srgb.x, entry.tone.srgb.y, entry.tone.srgb.z) * 255
        let digits = entry.colour.dropFirst()
        let value = UInt32(digits, radix: 16) ?? 0
        let written = SIMD3(Float((value >> 16) & 0xFF), Float((value >> 8) & 0xFF), Float(value & 0xFF))
        #expect(simd_distance(expected, written) < 0.5,
                "\(name) is written \(entry.colour), and its tone is \(expected)")
    }

    /// **Every piece stays inside the box it declares.** The mark's width is promised by
    /// ``EngineMark/width(forHeight:)`` and a game lays out against it; a piece hanging over the edge
    /// would be clipped by a panel that trusted the number, and the first place it would show is
    /// somebody else's title.
    ///
    /// **A stroke's thickness is perpendicular to it, not along it** — the first version of this
    /// checked every point ± half the thickness in both axes and failed the aim rule, which runs from
    /// one edge of the box to the other and, with butt caps, ends exactly there. A filled square *is*
    /// its thickness in both axes, so those are checked whole.
    @Test("Nothing hangs outside the mark's own box")
    func insideItsBox() {
        func inside(_ point: SIMD2<Float>, margin: Float, _ what: String) {
            #expect(point.x >= -margin - 1e-5 && point.x <= EngineMark.aspect + margin + 1e-5,
                    "\(what) reaches x \(point.x), and the box is 0…\(EngineMark.aspect)")
            #expect(point.y >= -margin - 1e-5 && point.y <= 1 + margin + 1e-5,
                    "\(what) reaches y \(point.y), and the box is 0…1")
        }
        for (index, piece) in EngineMark.pieces.enumerated() {
            if piece.points.count == 1 {
                let half = piece.thickness / 2
                let centre = piece.points[0]
                inside(centre + SIMD2(half, half), margin: 0, "square \(index)")
                inside(centre - SIMD2(half, half), margin: 0, "square \(index)")
            } else {
                // The stroke can lie half its thickness off a point, in whichever direction the
                // segment's normal points — so allow that much and no more.
                for point in piece.points { inside(point, margin: piece.thickness / 2, "piece \(index)") }
            }
        }
    }

    /// The path is a ballistic curve, not a freehand line: it leaves along the aim and is carried off
    /// it, so its first segment is flat and every one after that leans further.
    @Test("The path leaves along the aim and never comes back to it")
    func thePathIsCarriedOff() throws {
        let path = try #require(EngineMark.pieces.first { $0.points.count > 2 }).points
        #expect(abs((path.first?.y ?? 0) - EngineMark.aimY) < 1e-5,
                "the path starts at \(String(describing: path.first)), off the aim")
        var lastSlope: Float = 0
        for index in 1..<path.count {
            let step = path[index] - path[index - 1]
            let slope = -step.y / step.x                      // upward on screen is negative y
            #expect(slope > lastSlope, "segment \(index) leans \(slope) where the one before leant \(lastSlope)")
            lastSlope = slope
        }
        // A ULP, not a mistake: `aimY - (aimY - endY)` is not bit-for-bit `endY` in a Float.
        #expect(abs((path.last?.y ?? 0) - EngineMark.endY) < 1e-5,
                "the path ends at \(String(describing: path.last)), not at \(EngineMark.endY)")
    }
}
