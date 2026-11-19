#!/bin/bash
# Builds build/FocusNow.app. With --install, also replaces /Applications/FocusNow.app
# so Spotlight and Launchpad find it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product FocusNow
BIN="$(swift build -c release --show-bin-path)"

if [ ! -f build/AppIcon.icns ] || [ icon.png -nt build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
    swift scripts/make-icon.swift icon.png build
fi

APP=build/FocusNow.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/FocusNow" "$APP/Contents/MacOS/FocusNow"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "built $APP"

if [ "${1:-}" = "--install" ]; then
    pkill -x FocusNow || true
    rm -rf /Applications/FocusNow.app
    cp -R "$APP" /Applications/FocusNow.app
    echo "installed /Applications/FocusNow.app"
fi
