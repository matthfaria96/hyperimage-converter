#!/bin/sh
# UI smoke test: opens every sheet and window of the debug build with test images, draws each to PNG
# (HYPERIMAGE_SNAPSHOT, no Screen Recording permission needed) and fails if one did not render.
# Usage: scripts/ui-smoke.sh [output-dir]   (add LANG_ARGS="-AppleLanguages (en)" for English)
set -u
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build >/dev/null || exit 1
OUT="${1:-$(mktemp -d)/ui-smoke}"
FIX="$PWD/Tests/HyperImageCoreTests/Fixtures"
FILES="$FIX/paisagem.jpg:$FIX/retrato.jpg"
TMP_OUT="$(mktemp -d)"
FAILED=0

shot() {
  NAME=$1; shift
  rm -rf "$OUT/$NAME"
  env HYPERIMAGE_FILES="$FILES" HYPERIMAGE_OUT="$TMP_OUT" HYPERIMAGE_SNAPSHOT="$OUT/$NAME" "$@" \
    .build/debug/HyperImage ${LANG_ARGS:-} >/dev/null 2>&1 &
  PID=$!
  sleep "${WAIT:-7}"
  kill "$PID" 2>/dev/null
  # The main window is always drawn; a sheet or second window adds another PNG.
  COUNT=$(ls "$OUT/$NAME" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$COUNT" -ge "$EXPECT" ]; then echo "ok   $NAME"; else echo "FAIL $NAME ($COUNT png)"; FAILED=1; fi
}

EXPECT=1 shot main
EXPECT=2 shot format HYPERIMAGE_SHEET=format
EXPECT=2 shot about HYPERIMAGE_WINDOW=about
for STEP in resize rotate crop canvas colorDepth adjustments dpi text watermark border; do
  EXPECT=2 shot "advanced-$STEP" HYPERIMAGE_SHEET=advanced HYPERIMAGE_STEP=$STEP
done
EXPECT=2 shot preview HYPERIMAGE_SHEET=preview
EXPECT=2 shot progress HYPERIMAGE_SHEET=progress HYPERIMAGE_SNAPSHOT_DELAY=4

rm -rf "$TMP_OUT"
echo "Capturas em $OUT"
exit $FAILED
