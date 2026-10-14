#!/bin/zsh
# Stages windageengine.com for upload: the pages, the docs, the images and the mark files, without the
# docs' sources or this folder's tools. The pages reach the marks as ../ and ../../, which a browser
# resolves to the site's root, so they go there.
#
#   Brand/web/stage-site.sh ~/Desktop/windageengine.com
set -e
[ -n "$1" ] || { echo "usage: $0 <folder to upload>" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$1"
rsync -a --exclude '.DS_Store' --exclude 'docs-src' --exclude 'build-docs.py' \
  --exclude 'stage-site.sh' --exclude 'README.md' "$here/" "$1/"
cp "$here/../favicon.svg" "$here/../windage-engine.svg" "$here/../windage-engine-display.svg" "$1/"
echo "Staged $1"
