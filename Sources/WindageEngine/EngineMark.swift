//
//  EngineMark.swift
//  WindageEngine
//

import simd

/// The engine's own mark: a straight aim, and a path carried off it.
///
/// ### Why the engine has one at all
///
/// An engine is a thing other people ship with, and every engine that is says so somewhere — a splash,
/// a credit, a logo in a corner. **Nothing in `LICENSE` requires it**, which makes this a choice about
/// what the engine is rather than an obligation to encode: a product with a name, not an implementation
/// detail of whoever happens to be building on it. ``SplashScreen`` is the surface that shows it; this
/// is the drawing.
///
/// ### What it is a picture of
///
/// *Windage* is the sideways carry of a shot — the correction a marksman dials for wind, and the thing
/// a ballistics model exists to produce. Seen from above: **a straight rule where the shot was aimed, a
/// square where it left, a path bending off the rule, and a square where it actually arrived.** That is
/// the whole device, and it is the engine's subject rather than a monogram.
///
/// ### The geometry is data, so there is one drawing of it
///
/// A mark reproduced twice is a mark that drifts — the studio's own brand notes say so about a
/// wordmark, and it is just as true of a device. ``pieces`` is the only description of this one:
/// ``draw(into:x:y:height:colour:)`` walks it, `Brand/windage-engine.svg` is written from it, and
/// `EngineMarkTests` fails if the file on disk and this array disagree. Redrawing the mark means
/// editing numbers here and re-recording the file, never touching two places.
///
/// ### It has no hue, and that is deliberate
///
/// The studio's brand rules give each title a colour lane, and a title's accent outranks everything
/// inside that title. **This mark appears inside somebody else's game**, so a hue of its own would be
/// a second brand competing with the one the player came for — and it would spend a lane the studio
/// has not got many of. Achromatic, in two tones: ``display`` on dark grounds, ``deep`` on light ones.
/// The pieces vary by *tone* within whichever is chosen, never by colour.
public nonisolated enum EngineMark {

    /// One piece of the mark, in a box **2.4 wide and 1 high with the origin at its top left** — the
    /// same convention as ``HUDRenderer``, which puts y downward.
    public struct Piece: Sendable, Equatable {
        /// The points it runs through: two for a straight rule, many for the curve, **one for a filled
        /// square** of side ``thickness`` centred on it.
        public var points: [SIMD2<Float>]
        /// How thick, in the same units as the points.
        public var thickness: Float
        /// How much of the mark's colour this piece takes. **A tone, never a second hue** — see the
        /// type's notes.
        public var tone: Float

        public init(points: [SIMD2<Float>], thickness: Float, tone: Float) {
            self.points = points
            self.thickness = thickness
            self.tone = tone
        }
    }

    /// The mark is this many times as wide as it is high.
    public static let aspect: Float = 2.4

    /// The mark's width at a given height.
    public static func width(forHeight height: Float) -> Float { height * aspect }

    /// Where the aim runs, and where the shot ends up — the two numbers the whole device is built from.
    static let aimY: Float = 0.88
    static let endX: Float = 2.16
    static let endY: Float = 0.12

    /// How many straight segments the path is drawn with.
    static let pathSegments = 24

    /// How far each segment of the path reaches past its own ends, as a share of its length, so that
    /// consecutive quads **overlap instead of abutting**.
    ///
    /// **A strip of quads has a seam at every joint, and it shows.** Two quads meeting at a point have
    /// end edges square to their own directions, so between them lies a wedge as wide as the turn: at
    /// the stroke's edge that is `(t/2)·tan(Δθ/2)` = 0.00085 of the mark's height here, zero at its
    /// centre. The first version of this called that "under a tenth of a pixel at any size", which was
    /// arithmetic done without looking — **at a splash filling a 1440-point window the mark is 400
    /// points high and the wedge is two thirds of a point**, and the curve came out visibly hatched
    /// with hairline ticks along both edges. Found by running the sample and looking at it.
    ///
    /// A twentieth of a segment is sixty times the wedge, and the material it puts outside the strip on
    /// the outside of a bend is `0.0045·sin(1.5°)` — a twentieth of a point at that same size. The ends
    /// of the path are never extended, so the mark still stops exactly where its box says.
    ///
    /// The SVG does this with `stroke-linejoin="round"`, which is the same picture to well under a
    /// pixel and the reason the two are not compared pixel for pixel.
    static let jointOverlap: Float = 0.05

    /// The whole drawing, in order: the aim, the path, the muzzle, the impact.
    public static let pieces: [Piece] = {
        let path = (0...pathSegments).map { step -> SIMD2<Float> in
            let u = Float(step) / Float(pathSegments)
            return SIMD2(u * endX, aimY - (aimY - endY) * u * u)
        }
        return [
            // The aim: dimmer, because it is where the shot was pointed and not where it went.
            Piece(points: [SIMD2(0, aimY), SIMD2(aspect, aimY)], thickness: 0.05, tone: 0.45),
            Piece(points: path, thickness: 0.13, tone: 1),
            Piece(points: [SIMD2(0.08, aimY)], thickness: 0.16, tone: 1),
            Piece(points: [SIMD2(aspect - 0.12, endY)], thickness: 0.24, tone: 1),
        ]
    }()

    /// The tone for dark grounds — a game, a store capsule, a splash.
    public static let display = UIColor(hex: 0xF2F4F7)

    /// The tone for light grounds — a page, a printed mark, anything that must meet a contrast ratio.
    public static let deep = UIColor(hex: 0x1B2027)

    /// Draws the mark with its top-left corner at `x, y` and the given height, in `colour`.
    ///
    /// `colour`'s alpha multiplies every piece's tone, so fading the whole mark is one number.
    @MainActor
    public static func draw(into hud: HUDRenderer, x: Float, y: Float, height: Float, colour: UIColor) {
        guard height > 0, colour.srgb.w > 0 else { return }
        func place(_ point: SIMD2<Float>) -> SIMD2<Float> { SIMD2(x + point.x * height, y + point.y * height) }

        for piece in pieces {
            let shade = colour.withAlpha(colour.srgb.w * piece.tone)
            let thickness = piece.thickness * height
            if piece.points.count == 1 {
                let centre = place(piece.points[0])
                hud.rect(x: centre.x - thickness / 2, y: centre.y - thickness / 2,
                         width: thickness, height: thickness, color: shade)
            } else {
                for index in 1..<piece.points.count {
                    var from = place(piece.points[index - 1]), to = place(piece.points[index])
                    let span = to - from
                    let reach = span * jointOverlap
                    // Never past the two ends of the whole piece: the mark stops where its box says.
                    if index > 1 { from -= reach }
                    if index < piece.points.count - 1 { to += reach }
                    hud.line(from: from, to: to, thickness: thickness, color: shade)
                }
            }
        }
    }
}
