#!/bin/sh
# UI smoke test: opens every sheet and window of the debug build with test images, draws each to PNG
# (HYPERIMAGE_SNAPSHOT, no Screen Recording permission needed) and fails if one did not render.
# Usage: scripts/ui-smoke.sh [output-dir]   (LANG_ARGS="-AppleLanguages (en)" for English; APPEARANCE=light|dark;
#        ONLY="main progress" to capture a subset)
set -u
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build >/dev/null || exit 1
# REAL=1: capture the real windows with screencapture (needs Screen Recording permission for the terminal);
# this renders Liquid Glass, which the in-process snapshot cannot. Falls back to the snapshot otherwise.
if [ -n "${REAL:-}" ]; then
  [ -x .build/window-ids ] || swiftc -O -o .build/window-ids scripts/window-ids.swift || exit 1
fi
OUT="${1:-$(mktemp -d)/ui-smoke}"
FIX="$PWD/Tests/HyperImageCoreTests/Fixtures"
FILES="$FIX/paisagem.jpg:$FIX/retrato.jpg"
TMP_OUT="$(mktemp -d)"
FAILED=0

shot() {
  NAME=$1; shift
  if [ -n "${ONLY:-}" ]; then case " $ONLY " in *" $NAME "*) ;; *) return;; esac; fi
  rm -rf "$OUT/$NAME"
  # Mode is persisted between launches: start every shot in Converter unless the shot overrides it.
  if [ -n "${REAL:-}" ]; then SNAP=""; else SNAP="$OUT/$NAME"; fi
  env HYPERIMAGE_FILES="$FILES" HYPERIMAGE_OUT="$TMP_OUT" HYPERIMAGE_SNAPSHOT="$SNAP" HYPERIMAGE_MODE=convert \
    HYPERIMAGE_APPEARANCE="${APPEARANCE:-}" HYPERIMAGE_ACTIVATE=1 "$@" \
    .build/debug/HyperImage ${LANG_ARGS:-} >/dev/null 2>&1 &
  PID=$!
  sleep "${WAIT:-7}"
  if [ -n "${REAL:-}" ]; then
    mkdir -p "$OUT/$NAME"; I=0
    for WID in $(.build/window-ids); do screencapture -x -o -l "$WID" "$OUT/$NAME/$I.png"; I=$((I+1)); done
  fi
  kill "$PID" 2>/dev/null
  # The main window is always drawn; a sheet or second window adds another PNG.
  COUNT=$(ls "$OUT/$NAME" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$COUNT" -ge "$EXPECT" ]; then echo "ok   $NAME"; else echo "FAIL $NAME ($COUNT png)"; FAILED=1; fi
}

EXPECT=1 shot main
EXPECT=1 shot empty HYPERIMAGE_FILES=
EXPECT=1 shot upscale HYPERIMAGE_MODE=upscale
EXPECT=2 shot format HYPERIMAGE_SHEET=format
EXPECT=2 shot about HYPERIMAGE_WINDOW=about
for STEP in resize rotate crop canvas colorDepth adjustments dpi text watermark border; do
  EXPECT=2 shot "advanced-$STEP" HYPERIMAGE_SHEET=advanced HYPERIMAGE_STEP=$STEP
done
EXPECT=2 shot preview HYPERIMAGE_SHEET=preview
# Single window since a381703: progress shows inside the summary card, not in a sheet.
EXPECT=1 shot progress HYPERIMAGE_SHEET=progress HYPERIMAGE_SNAPSHOT_DELAY=4
# Narrowest window (minWidth 1080) with one file selected: header tabs, preview card and cards must not clip.
for MODE in convert compress upscale; do
  EXPECT=1 shot "narrow-$MODE" HYPERIMAGE_MODE=$MODE HYPERIMAGE_SELECT=1 HYPERIMAGE_WINDOW_SIZE=1080x640
done

rm -rf "$TMP_OUT"
echo "Capturas em $OUT"
exit $FAILED
