# Windage Engine — the mark

**The Drift W: the initial, with the windage dialled in.**

*Windage* is the sideways carry of a shot, and the correction a marksman dials against it. The mark is a
W drawn as one continuous stroke whose **right half is carried up by 16% of its height**. The middle
apex sits well below both shoulders, which is what makes it read as a W rather than two Vs; the lift is
the windage.

| file | what it is | use |
|---|---|---|
| `windage-engine.svg` | the mark in **deep** `#1B2027` | light grounds: a page, print, anything that must meet a contrast ratio |
| `windage-engine-display.svg` | the mark in **display** `#F2F4F7` | dark grounds: a game, a splash, a store capsule |
| `windage-engine-icon.svg` | the app icon on Apple's 1024 grid | a Dock, an App Store listing, anywhere an icon tile is expected |
| `favicon.svg` | a full-bleed tile with the mark | a browser tab |
| `exports/` | PNGs of all of the above | made by `Tools/make_brand_exports.sh` |
| `web/` | the site for `windageengine.com` | a working draft; see `web/README.md` |

The mark is square. The icon tile is an 824 square inset 100 on a 1024 canvas with a 185.4 corner, the
mark at 56% of the canvas; the favicon fills its square with the mark at 76%.

## There is one drawing of it, and it is in the code

**Every file above is generated from `EngineMark.outline`**, and `EngineMarkTests` fails if a file on disk
and the outline disagree. The outline is *constructed*, not traced: five points on the stroke's centre
line — left shoulder, left valley, middle apex, right valley, right shoulder — and a stroke width measured
across, as type is. Each arm's edges are its centre line moved half the width either way; every corner is
where two of those edges meet; every end is cut flat. Thirteen points in all.

To change the mark, change the construction in `Sources/WindageEngine/EngineMark.swift`, then:

```
WINDAGE_RECORD_MARK=1 swift test --filter EngineMarkTests
Tools/make_brand_exports.sh
python3 Tools/frames.py --record splash     # and look at it
```

The studio's brand notes make the case about a wordmark — *one drawing, or the imitations drift* — and a
device is no different. `Tools/frames.py` keeps a recorded picture of the splash as well, so the same drift
is caught on screen, at a tolerance of its own: a lit scene's half-percent could not see a mark move.

## Why these numbers

- **16%, and about as far as it goes.** At 10% the lift passed for a lean, or an italic. Much past 20% the
  stroke down into the right-hand valley shortens to a stub and the valley reads as a notch — the point at
  which the W stops being one letter.
- **The middle apex is cut flat and set low**, 46% down against shoulders at 22% and 6%. The first drawing
  was two Vs overlapping, whose middle peak rose as high as their outer tops, and it read as VV.
- **Stroke width 17% of the box.** That is what holds the letter at a 16 px favicon — checked by rendering
  it into sixteen real pixels — and why there is no separate small cut: the same drawing survives.

## No hue, and no accent

Every title in the studio gets a colour lane, and a title's accent outranks everything inside that title.
**This mark appears inside somebody else's game**, so a hue of its own would be a second brand competing with
the one the player came for. It is achromatic, in two tones.

An accent on the carried half was drawn and dropped. It split the letter into two pieces, which is the thing
the drawing works hardest not to be.

## What it replaced, and what else was drawn

**The first mark (2026-09-12)** was a thin rule, a curve and two squares, 2.4 times as wide as it was high. It read as a
chart going up, had no silhouette at a tab's size, and could not be an app icon.

Drawn on the way here, and why each lost:

| direction | why not |
|---|---|
| **The carry**, solid — a bar with a blade lifting off it | a rising blade off a bar is a swoosh |
| **The carry, as a wedge** — a tile split by a straight cut and a curved one | the strongest version of the idea, but the thin cut is gone by 16 px |
| **Wind tunnel** — streamlines cut through a block | speed lines are every courier's mark |
| **Vane** — three swept blades | reads as a fan or a pinwheel; the tips die small |
| **Range flag** — the wind flag on a rifle range | a golf flag |
| **Slid block** — a cube with its top slab pushed sideways | Unity's mark is a cube |

## On the splash

`SplashScreen` sets the lockup the way engines' splashes are set: **`MADE WITH` · the mark · `WINDAGE` over
`ENGINE`**, one line across.

- **No version.** No engine shows one in a shipped game; it belongs to an about box and a log.
  `showsVersion` exists for development builds and is off.
- **"Made with" stays.** A logo alone works for an engine every player recognises. Nobody recognises this one
  yet, and two words say what they are looking at.
- **The name is set, not drawn.** It is the host game's interface font. The engine has a drawn mark and no
  drawn wordmark yet; when it has one, it goes here beside the mark, and the splash draws it.

## The name

**Windage Engine**, title case, in every sentence, menu, window title, commit message and document. The
capitals — `WINDAGE ENGINE` — are the lockup's setting, not a second spelling: never a label, never
letterspaced in running text.
