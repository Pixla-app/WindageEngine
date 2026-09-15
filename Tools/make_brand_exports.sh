#!/bin/bash
# Rasterise the mark's SVGs into the PNGs a website, a store page and a Dock need.
#
# The SVGs in Brand/ are not drawn by hand: EngineMarkTests writes them from EngineMark.outline, and
# fails if they drift. This turns those files into bitmaps and nothing more, so every PNG here is the
# same drawing the engine fills on screen.
#
#     WINDAGE_RECORD_MARK=1 swift test --filter EngineMarkTests    # after changing the mark
#     Tools/make_brand_exports.sh
#
# rsvg-convert renders the vector at each size rather than scaling one bitmap, which is what keeps the
# 16 px favicon's edges on the pixel grid (brew install librsvg). It is a brand tool, not part of the
# build; nothing in the package needs it.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v rsvg-convert >/dev/null || { echo "needs rsvg-convert — brew install librsvg"; exit 1; }

out=Brand/exports
rm -rf "$out"
mkdir -p "$out/icon" "$out/favicon" "$out/mark"

for size in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$size" -h "$size" Brand/windage-engine-icon.svg -o "$out/icon/windage-engine-icon-$size.png"
done
for size in 16 32 48 96; do
  rsvg-convert -w "$size" -h "$size" Brand/favicon.svg -o "$out/favicon/favicon-$size.png"
done
for tone in "" "-display"; do
  for size in 256 1024; do
    rsvg-convert -w "$size" -h "$size" "Brand/windage-engine$tone.svg" -o "$out/mark/windage-engine$tone-$size.png"
  done
done

echo "wrote $(find "$out" -name '*.png' | wc -l | tr -d ' ') PNGs to $out"
