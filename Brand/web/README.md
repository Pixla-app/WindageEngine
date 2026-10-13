# windageengine.com — working draft

Two pages, built from the concept that was picked on 2026-09-15: **the product page's first screen and code,
the proof-led page's argument, and the docs in their own shape underneath.**

| page | what it is |
|---|---|
| `index.html` | the homepage — "Native to the Mac. Nothing in between.", a game as a Swift file, then "A game engine that shows its work": the jump at four step rates, the stale-shadow story, what's in it, what it deliberately isn't, how it's checked |
| `docs/*.html` | the docs — **generated, never edited**: 29 guides, the reference and the changelog (below) |
| `docs-src/*.md` | the guides' sources, one per page; `docs-src/WRITING.md` is how a page is written |
| `build-docs.py` | builds the docs from `docs-src/`, the changelog page from `CHANGELOG.md`, the reference page from the public types and their doc comments, and the search index |
| `docs/search.js` | search, opened from the box or ⌘K; it reads `docs/search-index.js` |
| `site.css` | one stylesheet for both |
| `images/` | the engine's own sample, running — nothing staged, nothing painted over |

Open `index.html` in a browser; there is no build step to *view* it. **After changing a guide's source, the
changelog or the engine's public types, run `python3 Brand/web/build-docs.py`** and commit what it writes.

## The docs (2026-10-13)

The sidebar listed two dozen topics with one page behind them. Every topic has a page now, plus eight the
engine had grown since the sidebar was drawn (loading meshes, the camera, sky and environment, particles,
instancing, level of detail, culling, saving), a reference page of every public type linked to its guide,
and the changelog. **Each guide was written from the engine's source, its README and the sample's real
usage**: every identifier in a Swift example exists in the engine or the sample (checked by script), the one
complete example — Your first game — was built and run, and no page names a product. The version on every
page is read from `Engine.semanticVersion`, never typed. The sidebar's order is `NAV` in `build-docs.py`.

## The mark is not copied here

The pages load `../windage-engine.svg`, `../windage-engine-display.svg` and `../favicon.svg` — the files
`EngineMarkTests` writes from `EngineMark.outline` and fails on if they drift. **Publishing the site copies
those into the site's root at deploy time; nobody pastes the mark into a page.** That is the only step a
deploy needs that opening the file does not.

## What is not true yet

- **The button and the license line stay as they are** (owner, 2026-10-13): "Get the engine" goes to the
  docs, and the footer keeps "Free for small studios under PolyForm Small Business 1.0.0".
- **The package URL.** There is no public repository, so the docs show `https://…/WindageEngine.git`.
- **The numbers.** 645 tests, 20 walk runs and 5 recorded frames are 0.27.0's (measured 2026-10-13). They move every release;
  check them against `swift test`, `Tools/walks.py` and `Tools/frames.py` when publishing.
- **The imagery.** Every picture is the sample's placeholder art, and taken before 0.22.0 strewed debris through it. A launch wants a scene built to be looked
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

## Words on the page are US English (2026-10-12)

The studio's rule for anything a person reads: color, center, meter, license. Checked 2026-10-12. **The
"No editor" item was reworded the same day**: a standalone world editor built on the engine now exists as
its own product, so the page says the engine has no editor *inside* it rather than that there is none. The
page still names no product; a showcase belongs here only once one ships.
