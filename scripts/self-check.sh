#!/bin/bash
# Builds the app and runs its self-check against a scratch data folder, never
# real data. Prints the self-check log.
# Usage: scripts/self-check.sh [phases]   (comma-separated; default: every phase)
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh >/dev/null
APP="$PWD/build/Release.noindex/FocusNow.app"
DIR="$PWD/build/selfcheck.noindex"

# Only stale development copies; the installed /Applications copy is left alone.
pkill -f "Release.noindex/FocusNow.app" || true
rm -rf "$DIR"
mkdir -p "$DIR/data" "$DIR/shots"
defaults delete local.focusnow.app.testing >/dev/null 2>&1 || true

env FOCUSNOW_SNAPSHOT_DIR="$DIR/shots" FOCUSNOW_DATA_DIR="$DIR/data" \
    ${1:+FOCUSNOW_SELFCHECK=$1} "$APP/Contents/MacOS/FocusNow" >"$DIR/stdout.txt" 2>&1 &
CHECK_PID=$!

# The stats phase asks to be launched again from outside, as Spotlight would.
# Only while the self-check copy is still running: `open` with no copy running
# would start a normal one, against real data.
(
    for _ in $(seq 1 480); do
        kill -0 "$CHECK_PID" 2>/dev/null || break
        if [ -f "$DIR/shots/ready-for-reopen" ]; then
            kill -0 "$CHECK_PID" 2>/dev/null && open "$APP"
            break
        fi
        sleep 0.25
    done
) &
WATCHER=$!

wait "$CHECK_PID" || true
kill "$WATCHER" 2>/dev/null || true
wait "$WATCHER" 2>/dev/null || true
cat "$DIR/shots/log.txt"
