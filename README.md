# HyperImage Converter

English · [Português](README.pt-BR.md)

A batch image converter for macOS 26+, built in Swift/SwiftUI. It recreates the conversion features of
FastStone Photo Resizer with a native Mac interface, and adds three focused modes:

- **Converter**: JPEG, HEIC, PNG, WebP, AVIF, GIF, TIFF, BMP, JPEG 2000 and PDF, with resizing, renaming and the
  10 advanced-edit steps (resize, rotate, crop, canvas, colour depth, adjustments, DPI, text, watermark, borders).
- **Comprimir** (Compress): every file keeps its format and gets smaller, never larger, with a size estimate before
  you start, a before/after comparison, a per-file size limit and removal of location and camera data.
- **AI Upscale**: enlarges images 2×, 3× or 4× on the Mac's GPU with the Upscayl engine (Real-ESRGAN).

More apps at [witchmymac.com](https://witchmymac.com).

## Install

**1. Terminal, one line (recommended)**

```sh
curl -fsSL https://witchmymac.com/install.sh | bash -s hyperimage
```

It downloads the latest release from GitHub, checks its SHA-256, installs the app in Applications and opens it.
There is no Gatekeeper prompt, because files downloaded by `curl` are not quarantined. Run it again to update.

**2. DMG + Terminal**

Download the DMG from [Releases](https://github.com/matthfaria96/hyperimage-converter/releases) or from
[witchmymac.com](https://witchmymac.com) and drag the app to Applications. The app is not notarized, so macOS
blocks it the first time. To allow it, paste this in Terminal (it only removes the "downloaded from the internet" mark):

```sh
xattr -dr com.apple.quarantine "/Applications/HyperImage Converter.app"
```

**3. DMG + System Settings**

Download the DMG and drag the app to Applications as above. Open the app and click OK on the warning, then go to
System Settings → Privacy & Security and click **Open Anyway**.

Requires macOS 26 Tahoe or later, on Apple Silicon or Intel.

## Build and tests
```sh
./build-app.sh              # builds build/HyperImage Converter.app (universal, ad hoc signed)
./build-app.sh --install    # and copies it to /Applications
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
scripts/ui-smoke.sh         # opens every sheet/window of the app and saves an image of each
```
The tests cover the engine (`HyperImageCoreTests`) and the app's flows (`HyperImageAppTests`: input list,
conversion with the overwrite question, cancelling, virtual folders, end-to-end lossless crop and the size estimate).
Once installed, Finder gets "Converter com HyperImage" in its context menu (Quick Actions/Services), which
sends the selected images and folders to the input list. If it doesn't show up, turn it on in System Settings →
Keyboard → Keyboard Shortcuts → Services.

Xcode is required (the Command Line Tools don't include SwiftUI's macro plugins).

## AI Upscale

The **AI Upscale** mode enlarges images 2×, 3× or 4× with the [Upscayl](https://github.com/upscayl/upscayl) engine
(Real-ESRGAN on the GPU). The `upscayl-bin` executable and the models are not in the repository:
`./scripts/fetch-upscayl.sh` downloads pinned versions, checks their SHA-256 and stores them in `Vendor/Upscayl/`
(`build-app.sh` runs it by itself when something is missing). The engine is AGPL-3.0 and runs as a separate program;
its license goes into `Contents/Resources/Licenses/`. Only the models that may be redistributed are included
(Standard, Lite, High fidelity/HFA2k and Digital art); Remacri, UltraSharp and Ultramix are left out because of
their non-commercial licenses. The upscale tests use `Vendor/Upscayl` and are skipped when it hasn't been downloaded.

## Languages
The interface is in Portuguese (source language) and English. Translations live in `Resources/Localizable.xcstrings`,
which `build-app.sh` compiles into the app. After changing strings in the code, run `scripts/sync-strings.sh` to
update the catalog and translate the new entries (in Xcode or by editing the JSON).

## Layout
- `Sources/HyperImageCore`: UI-free engine. Option models, geometry (resize/crop/canvas), a separable
  resampler with the 12 filters, adjustments through Core Image, text/watermark/borders, a median-cut quantizer,
  encoders (ImageIO, WebP through libwebp, PDF), concurrent batches and output naming templates.
- `Sources/HyperImage`: SwiftUI app (input list, fixed options panel on the right, sheets).
- `Sources/CWebP`: libwebp 1.6.0 (BSD), encoder only. ImageIO reads WebP but can't write it.
- `Sources/CJPEG`: IJG libjpeg 9f (IJG license, see `README-libjpeg.txt`) with a C bridge (`shim/hij.c`) to write
  JPEG and do lossless crops (`transupp`).

## Differences from the original
- Output: besides the 8 original formats, also HEIC and AVIF.
- Input: everything ImageIO reads (including RAW). PCX, WMF/EMF and FAX aren't supported by macOS.
- JPEG: written with the bundled libjpeg 9f, so chroma subsampling, smoothing and optimized Huffman work
  as in the original, and the quality scale is IJG's. Only the CMYK photometric still goes through ImageIO (and ignores those
  three options). "Use the original's quality" estimates quality from the DQT table. The YCbCrK photometric doesn't exist.
- Lossless JPEG crop: when the crop is the only step that touches pixels (DPI may be on), the source is
  JPEG without EXIF rotation and the output is YCbCr JPEG, the DCT blocks are cut directly, without re-encoding. The result
  matches FastStone pixel for pixel. If the X/Y origin doesn't fall on the block grid, the crop is re-encoded.
- TIFF: uncompressed, LZW, ZIP, JPEG, PackBits and G3/G4 fax (these convert to black and white). ImageIO writes
  G3 only in 1D, so "G3 Fax 2D" comes out the same as 1D. The original's YCbCr and CIELAB photometrics don't exist.
- PNG: None/Sub/Paeth filter as in the original, plus "Automatic" (ImageIO's default). The compression level isn't
  exposed by ImageIO. BMP without RLE and without 65536 colors, and GIF without interlacing, for the same reason.
- Options are saved as JSON (`.hyperoptions`). The original's `.ccf` files can be loaded (read only);
  `.ccf` doesn't store the watermark path, so it has to be chosen again.

## License

HyperImage Converter is free software under the [GNU General Public License v3.0](LICENSE). Copyright (C) 2026 Matheus Faria.
Third-party components: IJG libjpeg (IJG license; "This software is based in part on the work of the Independent JPEG Group."),
libwebp (BSD 3-Clause), Sparkle (MIT, in-app updates) and the Upscayl engine (AGPL-3.0, runs as a separate program). The texts ship in
`Contents/Resources/Licenses/` and appear in About → Open-source licenses.
