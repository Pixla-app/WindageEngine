# Windage Engine — the mark

**The aim, and the path carried off it.**

*Windage* is the sideways carry of a shot — the correction a marksman dials for wind, and the number a
ballistics model exists to produce. The device is that, seen from above: a straight rule where the shot
was aimed, a square where it left, a path bending off the rule, and a square where it actually arrived.
The engine's subject, rather than a monogram.

| | |
|---|---|
| `windage-engine.svg` | **deep** `#1B2027` — light grounds: a page, a printed mark, anything that must meet a contrast ratio |
| `windage-engine-display.svg` | **display** `#F2F4F7` — dark grounds: a game, a splash, a store capsule |

Both are 240 × 100 in their own units and scale to anything; the mark is always **2.4 times as wide as
it is high**.

## There is one drawing of it, and it is in the code

These files are **generated from `EngineMark.pieces`**, not drawn beside it. `EngineMarkTests` fails if
the file on disk and the geometry in `Sources/WindageEngine/EngineMark.swift` disagree, so redrawing the
mark is editing numbers there and re-recording:

```
WINDAGE_RECORD_MARK=1 swift test --filter EngineMarkTests
```

The studio's brand notes make the case about a wordmark — *one drawing, or the imitations drift* — and a
device is no different. The failure that prevents is the ordinary one: somebody nudges the curve in Swift
because it looked thin on screen, and the file a site and a store page are served from goes on showing the
old mark for a year.

`Tools/frames.py` keeps a recorded picture of the splash, so the same drift is caught on screen as well.
**That frame carries a tolerance of its own** — the default is sized for a lit scene, and moving the
curve by 4% of the mark's height changes only a quarter of a percent of a 640 × 400 frame, which the
scene's half-percent would let straight through.

## It has no hue, on purpose

Every title in the studio gets a colour lane, and a title's accent outranks everything inside that title.
**This mark appears inside somebody else's game.** A hue of its own would be a second brand competing with
the one the player came for, and it would spend a lane the studio has not got many of. So the mark is
achromatic, in the two tones above — the same *one hue in two tones* rule the studio applies to a colour,
with no hue to preserve.

Within a tone, pieces vary by opacity: the aim rule is at 45%, because it is where the shot was pointed
and not where it went. **A tone, never a second colour.**

## The engine has a device, not a wordmark

`SplashScreen` sets the name in the host's own interface font, and that is deliberate rather than
temporary. A line of capitals in one flat colour is **not** a mark — it is the name shouting — so the
drawing that carries the identity is the device, and the name under it is a caption. If the engine ever
earns a drawn wordmark, it goes here, beside these, and the splash starts using it.

## Where it is used

- `SplashScreen` — the engine's splash, which a game chooses to show. Nothing in `LICENSE` requires it;
  showing it is a courtesy, and the engine provides the surface so that a game which wants to has
  nothing to build.
- Anywhere a game wants to credit the engine: `EngineMark.draw(into:x:y:height:colour:)` puts it in a
  corner, a credits screen or an about box, at any size, with no texture and no pipeline.

## The name

**Windage Engine**, title case, in every sentence, menu, window title, commit message and document.
Never letterspaced in running text, never set in capitals as a label.
