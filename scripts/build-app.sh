#!/bin/bash
# Builds build/Release.noindex/FocusNow.app (the .noindex folder keeps Spotlight
# from listing this development copy). With --install, also replaces
# /Applications/FocusNow.app so Spotlight and Launchpad find it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product FocusNow
BIN="$(swift build -c release --show-bin-path)"

if [ ! -f build/AppIcon.icns ] || [ icon.png -nt build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
    swift scripts/make-icon.swift icon.png build
fi

APP=build/Release.noindex/FocusNow.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/FocusNow" "$APP/Contents/MacOS/FocusNow"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# A local certificate (scripts/make-signing-cert.sh) keeps the app's identity
# the same across builds, so macOS keeps its permissions; otherwise ad hoc.
IDENTITY="FocusNow Local Signing"
if [ -n "${FOCUSNOW_SIGNING_KEYCHAIN:-}" ]; then
    if security find-identity -p codesigning "$FOCUSNOW_SIGNING_KEYCHAIN" 2>/dev/null | grep -q "\"$IDENTITY\""; then
        codesign --force --sign "$IDENTITY" --keychain "$FOCUSNOW_SIGNING_KEYCHAIN" "$APP"
        echo "signed with $IDENTITY"
    else
        codesign --force --sign - "$APP"
        echo "signed ad hoc"
    fi
elif security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "signed with $IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "signed ad hoc"
fi
echo "built $APP"

if [ "${1:-}" = "--install" ]; then
    pkill -x FocusNow || true
    rm -rf /Applications/FocusNow.app
    cp -R "$APP" /Applications/FocusNow.app
    # Make Launch Services and Spotlight resolve "FocusNow" to the installed copy,
    # not the build folder's copy with the same bundle identifier.
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    "$LSREGISTER" -u "$APP" 2>/dev/null || true
    "$LSREGISTER" -f /Applications/FocusNow.app
    mdimport /Applications/FocusNow.app 2>/dev/null || true
    echo "installed /Applications/FocusNow.app"
fi
