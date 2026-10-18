#!/bin/sh
# Builds "build/HyperImage Converter.app" (release, universal when possible) and signs it ad hoc.
# Usage: ./build-app.sh [--install]   (--install copies the app to /Applications)
set -eu
cd "$(dirname "$0")"

# SwiftUI's macro plugins ship with Xcode, not with the Command Line Tools.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

LOG="$(mktemp -t hyperimage-build)"
if swift build -c release --arch arm64 --arch x86_64 >"$LOG" 2>&1; then
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/HyperImage"
else
  echo "Build universal indisponível (log: $LOG); gerando só para $(uname -m)."
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/HyperImage"
fi

APP="build/HyperImage Converter.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/Licenses"
cp "$BIN" "$CONTENTS/MacOS/HyperImage"
cp Resources/Info.plist "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z $SIZE $SIZE Resources/AppIcon-1024.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z $DOUBLE $DOUBLE Resources/AppIcon-1024.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

cp Sources/CWebP/COPYING "$CONTENTS/Resources/Licenses/libwebp-COPYING.txt"
cp Sources/CWebP/PATENTS "$CONTENTS/Resources/Licenses/libwebp-PATENTS.txt"
cp Sources/CJPEG/README-libjpeg.txt "$CONTENTS/Resources/Licenses/libjpeg-README.txt"

strip -x "$CONTENTS/MacOS/HyperImage" 2>/dev/null || true
codesign --force --options runtime --sign - "$APP"
codesign --verify --strict "$APP"

echo "Pronto: $APP ($(du -sh "$APP" | cut -f1))"

if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/HyperImage Converter.app"
  cp -R "$APP" /Applications/
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/HyperImage Converter.app"
  echo "Instalado em /Applications/HyperImage Converter.app"
fi
