#!/bin/bash
# Tests make-signing-cert.sh and build-app.sh's signing against a throwaway
# keychain under build/, never the login keychain or trust settings. The
# throwaway keychain is deleted on exit, which also takes it off the search list.
set -euo pipefail
cd "$(dirname "$0")/.."

DIR="$PWD/build/signing-check.noindex"
KC="$DIR/check.keychain-db"
PASS="focusnow-check-$(uuidgen)"
rm -rf "$DIR"
mkdir -p "$DIR"
cleanup() {
    security delete-keychain "$KC" 2>/dev/null || true
    rm -rf "$DIR"
}
trap cleanup EXIT

security create-keychain -p "$PASS" "$KC"
security set-keychain-settings "$KC" # no auto-lock during the check
security unlock-keychain -p "$PASS" "$KC"

echo "-- create"
FOCUSNOW_KEYCHAIN_PASSWORD="$PASS" scripts/make-signing-cert.sh "$KC"
echo "-- again (should leave it as is)"
FOCUSNOW_KEYCHAIN_PASSWORD="$PASS" scripts/make-signing-cert.sh "$KC"

echo "-- build"
FOCUSNOW_SIGNING_KEYCHAIN="$KC" scripts/build-app.sh | grep -E "^signed"
APP=build/Release.noindex/FocusNow.app
REQ=$(codesign -d -r- "$APP" 2>&1 | grep designated || true)
echo "$REQ"
codesign --verify --strict "$APP" && echo "verify: ok"
if [[ "$REQ" == *certificate* && "$REQ" != *cdhash* ]]; then
    echo "designated requirement names the certificate: ok"
else
    echo "designated requirement names the certificate: FAILED"
    exit 1
fi
