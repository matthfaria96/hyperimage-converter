#!/bin/zsh
# Downloads the Upscayl AI backend (AGPL-3.0, https://github.com/upscayl/upscayl-ncnn) and the freely licensed
# models into Vendor/Upscayl; build-app.sh copies them into the app bundle. Every file is pinned and checksummed.
# Remacri, UltraSharp and Ultramix are left out: their licences forbid commercial use.
set -euo pipefail
cd "$(dirname "$0")/.."

BIN_TAG="20251207-174704"
BIN_SHA="277419791281a56eae0c739c70120b974d7267cf7c2de8e86dc09798d4b314db"
UPSCAYL_COMMIT="a00d55fee90e0f9435d5eaa86e76700df8199af8"
NCNN_COMMIT="0beb39028a0ddd83250e845b4c3333c0675e3b97"
LICENSE_SHA="db1a87ba81e885b6bb82971964ab4e202463cde2ac4003571bc5a857d577e4a3"
typeset -A MODEL_SHA=(
  upscayl-standard-4x.param 35330ececcea33b6c397a72548e788d5d53becee4734c50b7fada36e89f10a86
  upscayl-standard-4x.bin   713ee713b0353afaa27976f0563a64a5043bd70b9bd8936c2e26e25ebcdbcddf
  upscayl-lite-4x.param     22174924330297357434ad21ed0af7f4b820008d2a502b492754d130d4142714
  upscayl-lite-4x.bin       85ee266b632a765a725425ba6a5620c088c8aa2939a03063b2d83b3462724cc1
  high-fidelity-4x.param    4576ed5c2fc5fa250d3c3d585ef02248f26abdfc1867088078f501fe71e5d61e
  high-fidelity-4x.bin      8a135402b4f39286121b76abb47601a6b7b7e8d4f3e999a5aaa45ed277824fb4
  digital-art-4x.param      2b8fb6e0ae4d2d85704ca08c119a2f5ea40add4f2ecd512eb7f4cd44b6127ed4
  digital-art-4x.bin        fe01c269cfd10cdef8e018ab66ebe750cf79c7af4d1f9c16c737e1295229bacc
)
DEST="Vendor/Upscayl"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$DEST/models"

sha_ok() { [[ -s "$1" ]] && [[ "$(shasum -a 256 "$1" | cut -d' ' -f1)" == "$2" ]] }

# Downloads $1 to $2 through a .part file and keeps it only when the checksum matches $3.
fetch() {
  sha_ok "$2" "$3" && return 0
  curl -fsSL -o "$2.part" "$1"
  if ! sha_ok "$2.part" "$3"; then rm -f "$2.part"; echo "Checksum inválido: $1" >&2; exit 1; fi
  mv "$2.part" "$2"
}

if [[ ! -x "$DEST/upscayl-bin" ]]; then
  fetch "https://github.com/upscayl/upscayl-ncnn/releases/download/$BIN_TAG/upscayl-bin-$BIN_TAG-macos.zip" "$TMP/bin.zip" "$BIN_SHA"
  mkdir "$TMP/x" && ditto -x -k "$TMP/bin.zip" "$TMP/x"
  BIN="$(find "$TMP/x" -type f -name 'upscayl-bin' | head -1)"
  [[ -n "$BIN" ]] || { echo "upscayl-bin não encontrado no zip" >&2; exit 1; }
  cp "$BIN" "$DEST/upscayl-bin.part" && chmod +x "$DEST/upscayl-bin.part" && xattr -c "$DEST/upscayl-bin.part"
  mv "$DEST/upscayl-bin.part" "$DEST/upscayl-bin"
fi
for file sha in ${(kv)MODEL_SHA}; do
  fetch "https://raw.githubusercontent.com/upscayl/upscayl/$UPSCAYL_COMMIT/resources/models/$file" "$DEST/models/$file" "$sha"
done
fetch "https://raw.githubusercontent.com/upscayl/upscayl-ncnn/$NCNN_COMMIT/LICENSE" "$DEST/LICENSE-AGPL-3.0.txt" "$LICENSE_SHA"
echo "Upscayl pronto em $DEST"
