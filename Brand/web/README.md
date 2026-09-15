# windageengine.com — working draft

Two pages, built from the concept that was picked on 2026-09-15: **the product page's first screen and code,
the proof-led page's argument, and the docs in their own shape underneath.**

| page | what it is |
|---|---|
| `index.html` | the homepage — "Native to the Mac. Nothing in between.", a game as a Swift file, then "A game engine that shows its work": the jump at four step rates, the stale-shadow story, what's in it, what it deliberately isn't, how it's checked |
| `docs/start.html` | the docs' first page — add the package, run the sample, play it by script, check it |
| `site.css` | one stylesheet for both |
| `images/` | the engine's own sample, running — nothing staged, nothing painted over |

Open `index.html` in a browser; there is no build step.

## The mark is not copied here

The pages load `../windage-engine.svg`, `../windage-engine-display.svg` and `../favicon.svg` — the files
`EngineMarkTests` writes from `EngineMark.outline` and fails on if they drift. **Publishing the site copies
those into the site's root at deploy time; nobody pastes the mark into a page.** That is the only step a
deploy needs that opening the file does not.

## What is not true yet

This is launch-day copy, and four things in it are ahead of the facts. Fix each before the site goes up:

- **The licence.** "Get the engine" and "Free for small studios under PolyForm Small Business 1.0.0" assume
  that licence is in effect. Today's `LICENSE` grants nothing. Until it does, the button reads "Follow
  development" and the footer drops the licence line.
- **The package URL.** There is no public repository, so the docs show `https://…/WindageEngine.git`.
- **The numbers.** 626 tests, 20 walk runs and 5 recorded frames are 0.21.0's. They move every release;
  check them against `swift test`, `Tools/walks.py` and `Tools/frames.py` when publishing.
- **The imagery.** Every picture is the sample's placeholder art. A launch wants a scene built to be looked
  at, and the showcase that the product concept had is left out until a title built on the engine has been
  announced — **no game is named on the engine's site before it is**.

The code on the homepage uses only real API (`GameLoop`, `CharacterController`, `MovementInput`,
`Surroundings`); if any of those change, so does the page.

## Choices worth keeping

- **The headline is the product's, the argument is the proof's.** Every engine's site says "powerful".
  This one can show a number before and after and the command that checks it; that is the distinctive half,
  and it sits directly under the first screen.
- **Two grounds, on purpose.** The first screen is night — the engine's render full-bleed — and the argument
  is day. The day half follows the reader's light or dark appearance; the night half is always night.
- **Type:** Archivo, wide and heavy, standing in for a drawn wordmark; Hanken Grotesk for reading; JetBrains
  Mono for anything a reader might type. Loaded from Google Fonts in the draft; self-host them for launch.
