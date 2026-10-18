#!/bin/sh
# Debug helper: launches the debug build with HYPERIMAGE_* env vars and screenshots its main window.
# Usage: HYPERIMAGE_SHEET=advanced scripts/debug-shot.sh out.png
set -eu
cd "$(dirname "$0")/.."
pkill -x HyperImage 2>/dev/null || true
sleep 0.5
.build/debug/HyperImage >/dev/null 2>&1 &
sleep "${WAIT:-4}"
ID=$(swift scripts/window-id.swift ${PICK:-})
screencapture -o -l "$ID" "$1"
pkill -x HyperImage || true
