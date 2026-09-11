#!/bin/zsh
# Wraps the built sample in an app bundle: .build/WindageSample.app — for measuring what macOS does to a
# game that is an *app*, which a bare executable run from a terminal is not. App Nap is decided per
# app, by Launch Services, for things launched as apps.
#
#   Tools/bundle_sample_app.sh
#   open -n .build/WindageSample.app --env WINDAGE_SAMPLE_FPS=1 --stdout /tmp/log --stderr /tmp/log
#
# **For measuring on the machine that built it, not for shipping.** The resource bundles are not copied
# in: SwiftPM's `Bundle.module` looks beside the app, then at the absolute path it was built at, and
# the second is what finds them here. Signed ad hoc, which is enough to launch it locally.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product WindageSample
app=.build/WindageSample.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/debug/WindageSample "$app/Contents/MacOS/WindageSample"
version=$(sed -n 's/.*semanticVersion = SemanticVersion(major: \([0-9]*\), minor: \([0-9]*\), patch: \([0-9]*\)).*/\1.\2.\3/p' Sources/WindageEngine/Engine.swift)
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>WindageSample</string>
    <key>CFBundleIdentifier</key><string>dev.windage.sample</string>
    <key>CFBundleName</key><string>Windage Sample</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
echo "$app — $version"
