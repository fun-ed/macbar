#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP=".build/app-audio-probe.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -parse-as-library -I "$BIN_DIR/AppAudioRT.build" \
    Sources/macbar/AppAudioState.swift Sources/macbar/AppAudioDiscovery.swift \
    Sources/macbar/AppAudioRoute.swift Scripts/probe-app-audio.swift \
    "$BIN_DIR/AppAudioRT.build/AppAudioRT.c.o" -o "$APP/Contents/MacOS/app-audio-probe"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>app-audio-probe</string>
    <key>CFBundleIdentifier</key><string>no.runbox.funed.macbar.app-audio-probe</string>
    <key>CFBundleName</key><string>macbar app audio probe</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.4</string>
    <key>NSAudioCaptureUsageDescription</key><string>Verify per-application volume by capturing and replaying live audio from the selected application. No audio is recorded.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf 'Close macbar before this probe to avoid competing routes. Play audio continuously in two different apps.\n'
printf 'Run: %s/Contents/MacOS/app-audio-probe <PID-of-A> <PID-of-B>\n' "$APP"
