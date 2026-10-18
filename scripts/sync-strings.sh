#!/bin/sh
# Re-extracts the interface strings from the Swift sources into Resources/Localizable.xcstrings.
# New strings appear untranslated (open the catalog in Xcode to translate); removed ones are marked stale.
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
OUT="$(mktemp -d)"
swift package clean
swift build -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT"
xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata "$OUT"/*.stringsdata
echo "Catálogo atualizado: Resources/Localizable.xcstrings"
