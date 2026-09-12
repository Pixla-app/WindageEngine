//
//  SplashScreen.swift
//  WindageEngine
//

import simd

/// The engine saying its own name: ``EngineMark`` over a ground, with the name and version under it,
/// for as long as a game wants and no longer.
///
/// ### What the engine owes here, and what it does not
///
/// The engine owes the **surface** — a thing that can be shown, timed, skipped and drawn with no art,
/// no texture and no pipeline of its own, so that a game which wants to credit the engine has nothing
/// to build. It does not owe the decision: nothing here runs unless a game runs it, and
/// ``SplashScreen`` does not install itself in the frame loop.
///
/// ### It does not stop the game, and it must not swallow the key that skips it
///
/// **Advance it from your simulation step, draw it from your HUD.** It is an overlay and a clock, not
/// a mode: the game goes on stepping behind it, which is what a game is usually *for* during a splash
/// — loading. Two things follow, and both were worth finding out the hard way in the sample:
///
/// - A game that suspends its step while this is up makes its own first second unrepeatable.
/// - **``skip()`` must be a side effect of a press, never a consumer of it.** A splash that eats the
///   first keystroke eats the first keystroke of whatever the player was already doing — in the
///   sample's case the first press of a scripted walk, which then ends 1.2 m short. There is a check
///   for exactly that (`Tools/walks.json`, "crate behind the splash").
///
/// ### The fades are ramps, so the picture is the same at any step rate
///
/// Everything here is linear in ``elapsed``, and ``elapsed`` is a sum of step lengths. A game at 30
/// steps a second and one at 240 show the same opacity at the same moment, which is the same promise
/// the body makes (see `OneCourseTests`).
public nonisolated struct SplashScreen: Sendable {

    /// Seconds fading up from nothing.
    public var fadeIn: Float = 0.4
    /// Seconds at full strength.
    public var hold: Float = 1.6
    /// Seconds fading away.
    public var fadeOut: Float = 0.5

    /// How long a press is ignored for.
    ///
    /// **A splash that can be skipped on the frame it appears is one nobody ever sees**: the key or
    /// the click that launched the game is often still down when the first frame goes up, and the
    /// splash is gone before it has drawn once.
    public var ignoresSkipsFor: Float = 0.25

    /// What is behind the mark. Near-black rather than black, so it reads as a surface.
    public var background = UIColor(hex: 0x0B0D10)

    /// The mark and the lettering. ``EngineMark/display``, because the ground is dark.
    public var foreground = EngineMark.display

    /// A line in small capitals above the mark — `"MADE WITH"` is the usual one. Nil draws none.
    public var lead: String?

    /// How wide the mark is drawn, as a share of the viewport's width. **The device leads and the
    /// name follows it**, so this is set wide enough that the lettering never out-measures the mark —
    /// a caption wider than the thing it captions reads as a title with a doodle over it.
    public var markWidthFraction: Float = 0.34

    /// Whether ``Engine/version`` is drawn under the name.
    ///
    /// **A shipped game may not want it, and a recorded frame must not have it**: the version changes
    /// every release, so a frame check that could see it would fail on the changelog rather than on
    /// the picture. The sample turns it off for `Tools/frames.py` and leaves it on in play.
    public var showsVersion = true

    /// Seconds since it went up.
    public private(set) var elapsed: Float = 0

    /// Whether ``skip()`` has been taken.
    public private(set) var isSkipped = false

    public init(lead: String? = nil) {
        self.lead = lead
    }

    /// How long it lasts if nobody skips it.
    public var duration: Float { fadeIn + hold + fadeOut }

    /// Nothing left to draw. **Drop it when this is true** — an overlay at zero opacity still costs
    /// its vertices.
    public var isFinished: Bool { elapsed >= duration }

    /// 0…1, up the ramp, flat, and down again.
    public var opacity: Float {
        if elapsed <= 0 { return 0 }
        if elapsed < fadeIn { return fadeIn > 0 ? elapsed / fadeIn : 1 }
        if elapsed < fadeIn + hold { return 1 }
        if elapsed < duration { return fadeOut > 0 ? (duration - elapsed) / fadeOut : 0 }
        return 0
    }

    /// Call once per simulation step.
    public mutating func advance(by seconds: Float) {
        elapsed = min(duration, elapsed + max(0, seconds))
    }

    /// Cut it short — **by running it to the start of its fade, not by ending it.**
    ///
    /// A splash that vanishes on the frame a key goes down looks like a dropped frame; one that fades
    /// out over its own fade looks like it was always going to. Ignored while ``ignoresSkipsFor`` has
    /// not passed, and ignored again once it is already fading, so leaning on a key does not shorten
    /// the fade twice.
    public mutating func skip() {
        guard elapsed >= ignoresSkipsFor, elapsed < fadeIn + hold else { return }
        elapsed = fadeIn + hold
        isSkipped = true
    }

    /// Draws it over the whole viewport. Call from `encodeHUD`, after everything else.
    ///
    /// The lettering is set in the host's own interface font, and that is on purpose: the engine has
    /// a **device**, not a wordmark. A line of capitals in one flat colour is not a mark — it is the
    /// name shouting — so the drawing that carries the identity is ``EngineMark`` and the name under
    /// it is a caption.
    @MainActor
    public func draw(into hud: HUDRenderer, viewport: SIMD2<Float>) {
        let alpha = opacity
        guard alpha > 0, viewport.x > 0, viewport.y > 0 else { return }

        hud.rect(x: 0, y: 0, width: viewport.x, height: viewport.y,
                 color: background.withAlpha(background.srgb.w * alpha))

        let markWidth = viewport.x * markWidthFraction
        let markHeight = markWidth / EngineMark.aspect
        let ink = foreground.withAlpha(foreground.srgb.w * alpha)

        // **The group is centred, not the mark.** With the lead above it and the name below, centring
        // the device alone puts the whole block low; this places it so the block's optical centre is
        // the viewport's, with or without the version line.
        let markTop = viewport.y * 0.5 - markHeight * 0.7
        EngineMark.draw(into: hud, x: (viewport.x - markWidth) / 2, y: markTop,
                        height: markHeight, colour: ink)

        let namePoint = markHeight * 0.36
        let leadPoint = markHeight * 0.2

        if let lead, !lead.isEmpty {
            let width = hud.width(of: lead, pointSize: leadPoint)
            _ = hud.text(lead, x: (viewport.x - width) / 2, y: markTop - markHeight * 0.34,
                         pointSize: leadPoint, color: ink.withAlpha(ink.srgb.w * 0.5))
        }

        // **Two tones, not two colours.** "Windage" carries the name and "Engine" says what it is, so
        // the second word is set back — the studio's own rule for a two-tone wordmark, applied to the
        // one thing available in a host's font.
        let words = Engine.name.split(separator: " ", maxSplits: 1).map(String.init)
        let first = words.first ?? Engine.name
        let rest = words.count > 1 ? " " + words[1] : ""
        let nameWidth = hud.width(of: first, pointSize: namePoint) + hud.width(of: rest, pointSize: namePoint)
        let baseline = markTop + markHeight + namePoint * 1.5
        var pen = (viewport.x - nameWidth) / 2
        pen += hud.text(first, x: pen, y: baseline, pointSize: namePoint, color: ink)
        _ = hud.text(rest, x: pen, y: baseline, pointSize: namePoint, color: ink.withAlpha(ink.srgb.w * 0.6))

        guard showsVersion else { return }
        let versionPoint = markHeight * 0.2
        let versionWidth = hud.width(of: Engine.version, pointSize: versionPoint)
        _ = hud.text(Engine.version, x: (viewport.x - versionWidth) / 2,
                     y: baseline + versionPoint * 2.3,
                     pointSize: versionPoint, color: ink.withAlpha(ink.srgb.w * 0.45))
    }
}
