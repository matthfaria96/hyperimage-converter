# Technology Stack

**Analysis Date:** 2026-10-20

## Languages

**Primary:**
- Swift (tools version 6.2, Swift 6 language mode implied) - all app and engine code in `Sources/HyperImage/` (SwiftUI app) and `Sources/HyperImageCore/` (UI-free engine), plus tests in `Tests/`
- Swift 6.4 toolchain observed locally (`swift --version` under `/Applications/Xcode.app/Contents/Developer`)

**Secondary:**
- C (IJG libjpeg and libwebp sources, compiled by SwiftPM as C targets) - `Sources/CJPEG/libjpeg/*.c` (IJG libjpeg 9f), `Sources/CJPEG/shim/hij.c` (bridge that hides libjpeg setjmp/macros from Swift), `Sources/CWebP/libwebp/src/` and `Sources/CWebP/libwebp/sharpyuv/` (libwebp 1.6.0, encoder side only)
- Shell (POSIX `sh` and `zsh`) - `build-app.sh`, `scripts/*.sh`
- XML/plist - `Resources/Info.plist`
- JSON - `Resources/Localizable.xcstrings` (String Catalog), `.hyperoptions` files written by the app

## Runtime

**Environment:**
- macOS 26.0 minimum (`Package.swift` `platforms: [.macOS(.v26)]`, `Resources/Info.plist` `LSMinimumSystemVersion` 26.0)
- Native arm64 and x86_64 binaries (universal build attempted by `build-app.sh` with `swift build -c release --arch arm64 --arch x86_64`, falls back to host arch)
- Xcode required: the SwiftUI macro plugins ship with Xcode, not the Command Line Tools (`README.md`). Default `DEVELOPER_DIR` is `/Applications/Xcode.app/Contents/Developer`.

**Package Manager:**
- Swift Package Manager (`Package.swift`, single package named `HyperImage`)
- Lockfile: missing - no `Package.resolved` exists. This is expected: the package has zero external dependencies (`.build/workspace-state.json` lists `"dependencies" : []`).

## Frameworks

**Core (Apple system frameworks, no third-party Swift packages):**
- SwiftUI - all windows and sheets, `@main` app in `Sources/HyperImage/App/HyperImageApp.swift` (`Window("HyperImage Converter", id: "main")`, `Window` for About)
- AppKit - `NSApplication`/`NSApplicationDelegate` (`AppDelegate` in `HyperImageApp.swift`), `NSOpenPanel`/`NSSavePanel` (`Sources/HyperImage/Shared/FilePanels.swift`), `NSWorkspace`, `NSPasteboard`, dock badge
- Observation - app model state (`import Observation` in `Sources/HyperImage/App/AppModel.swift` and related)
- Foundation - I/O, `Process`, `Pipe`, `UserDefaults`, `JSONEncoder`/`JSONDecoder`, `Task`, `DispatchQueue`
- CoreGraphics / ImageIO - decoding (`Sources/HyperImageCore/IO/ImageLoader.swift`), encoding (`Sources/HyperImageCore/IO/ImageEncoder.swift`), metadata, thumbnails, `CGPDFDocument` for previews
- Core Image (`CoreImage`, `CoreImage.CIFilterBuiltins`) - colour adjustments, unsharp mask, blur, hue rotation (`Sources/HyperImageCore/Imaging/ColorAdjuster.swift`, `HueRotation.swift`)
- CoreText - text overlays (`Sources/HyperImageCore/Imaging/TextOverlay.swift`)
- UniformTypeIdentifiers - `UTType` for output formats (`OutputFormat.swift`, `UTType("public.avif")`)
- UserNotifications - completion notices (`Sources/HyperImage/Convert/CompletionFeedback.swift`)

**Testing:**
- Swift Testing (`import Testing`, `#expect`, `#require`) - used by all tests under `Tests/`
- Test targets: `Tests/HyperImageCoreTests` (engine, uses `Fixtures/` with `paisagem.jpg`, `retrato.jpg`, `exemplo-opcoes.ccf`) and `Tests/HyperImageAppTests` (app flows, `Fixtures/` with two JPEGs). Both declare `resources: [.copy("Fixtures")]`.
- No third-party test frameworks or mocking libraries.

**Build/Dev:**
- SwiftPM (`swift build`, `swift test`, `swift package clean`)
- `xcrun xcstringstool` - compiles and syncs `Resources/Localizable.xcstrings` (`build-app.sh`, `scripts/sync-strings.sh`)
- `swift build -emit-localized-strings` - extracts UI strings for the catalog (`scripts/sync-strings.sh`)
- `sips` and `iconutil` - generate `AppIcon.icns` from `Resources/AppIcon-1024.png` (`build-app.sh`)
- `codesign` (ad hoc identity `-`, hardened runtime `--options runtime`), `strip`, `lipo`-style universal build via SwiftPM - `build-app.sh`
- `swift scripts/make-icon.swift` - one-off icon mask generator (AppKit/CoreGraphics script)
- `scripts/window-id.swift` - CoreGraphics window listing helper for screenshots
- `screencapture`, `pkill`, `sleep` - `scripts/debug-shot.sh`, `scripts/ui-smoke.sh`

## Package Targets (`Package.swift`)

| Target | Kind | Path | Depends on | Notes |
|--------|------|------|------------|-------|
| `CWebP` | C target | `Sources/CWebP` | none | libwebp 1.6.0 encoder; `WEBP_USE_THREAD`; `-O3` in release; public header `include/CWebP.h` |
| `CJPEG` | C target | `Sources/CJPEG` | none | IJG libjpeg 9f; public header `include/CJPEG.h`; `-O3` in release |
| `HyperImageCore` | Swift library | `Sources/HyperImageCore` | `CWebP`, `CJPEG` | UI-free engine |
| `HyperImage` | executable | `Sources/HyperImage` | `HyperImageCore` | `swiftSettings: [.defaultIsolation(MainActor.self)]` |
| `HyperImageAppTests` | test | `Tests/HyperImageAppTests` | `HyperImage`, `HyperImageCore` | MainActor default isolation |
| `HyperImageCoreTests` | test | `Tests/HyperImageCoreTests` | `HyperImageCore` | |

Product: `.executable(name: "HyperImage")`. The app bundle is assembled by `build-app.sh`, not by SwiftPM.

## Bundled Third-Party Native Code

**libwebp 1.6.0** (BSD-3-Clause, `Sources/CWebP/COPYING`, `Sources/CWebP/PATENTS`):
- Encoder only; ImageIO handles WebP decoding. Used by `Sources/HyperImageCore/IO/WebPEncoder.swift` (`WebPConfigInit`, `WebPConfigLosslessPreset(&config, 6)`, `WebPEncode`, `WebPPictureImportRGBA`, memory writer). Lossy uses `method = 4` and optional `use_sharp_yuv`.
- Header `Sources/CWebP/libwebp/src/webp/encode.h` defines `WEBP_ENCODER_ABI_VERSION 0x0210`.
- Licence copied into bundle at `Contents/Resources/Licenses/libwebp-COPYING.txt`.

**IJG libjpeg 9f** (IJG licence, `Sources/CJPEG/README-libjpeg.txt`, released 14-Jan-2024):
- Used for JPEG writing (subsampling, smoothing, Huffman optimisation, progressive, ICC/APP2) and lossless crop (`transupp.c`). Swift wrapper: `Sources/HyperImageCore/IO/LibJPEG.swift`, `Sources/HyperImageCore/IO/JPEGQualityEstimator.swift`, `Sources/HyperImageCore/Pipeline/LosslessCrop.swift`.
- C shim API in `Sources/CJPEG/include/CJPEG.h`: `hij_encode_rgba`, `hij_lossless_crop`, `hij_free`.
- Licence copied to `Contents/Resources/Licenses/libjpeg-README.txt`.

## Bundled Executable (not compiled from source here)

**Upscayl `upscayl-bin`** (AGPL-3.0, separate program):
- Pinned release tag `20251207-174704` from `github.com/upscayl/upscayl-ncnn`; SHA-256 pinned in `scripts/fetch-upscayl.sh`.
- Placed in `Vendor/Upscayl/upscayl-bin` (gitignored) and copied into `HyperImage Converter.app/Contents/MacOS/upscayl-bin`, ad hoc signed.
- Models: 4 freely-redistributable Real-ESRGAN-style `.param`/`.bin` pairs in `Vendor/Upscayl/models/` (`upscayl-standard-4x`, `upscayl-lite-4x`, `high-fidelity-4x`, `digital-art-4x`), about 75 MB total, copied to `Contents/Resources/Upscayl/models`.
- Driven as a child process from `Sources/HyperImageCore/Upscale/Upscaler.swift`. Runs on the GPU per `README.md`.

## Key Dependencies

**Critical (system-provided, no versions pinned in repo):**
- ImageIO - the main decode/encode path for JPEG, PNG, GIF, BMP, TIFF, HEIC/HEIF, AVIF, JPEG 2000, PSD, TGA, OpenEXR, DNG and camera RAW (`ImageFileTypes.readable` in `Sources/HyperImageCore/Files/ImageFileTypes.swift`)
- Core Graphics PDF (`CGContext(consumer:mediaBox:)`, `CGPDFDocument`) - PDF output in `Sources/HyperImageCore/IO/PDFEncoder.swift`
- Core Image - colour and filter pipeline in `Sources/HyperImageCore/Imaging/ColorAdjuster.swift`
- Swift Concurrency and Dispatch - `withThrowingTaskGroup` in `Sources/HyperImageCore/Batch/BatchConverter.swift` (worker count `min(activeProcessorCount, 6)`, forced to 1 for upscale), `DispatchQueue.concurrentPerform` in `Sources/HyperImageCore/Imaging/Resampler.swift` and `Sources/HyperImageCore/Files/FileSorting.swift`

**Vendored (bundled in repo):**
- libwebp 1.6.0 - `Sources/CWebP/`
- IJG libjpeg 9f - `Sources/CJPEG/`

**Infrastructure / runtime services in use:**
- `UserDefaults.standard` - persisted UI and convert settings under key `HyperImage.state.v1` (`Sources/HyperImage/App/PersistedState.swift`)
- `UNUserNotificationCenter` - completion notices, see INTEGRATIONS.md

## Build Pipeline

- `./build-app.sh` - release build (universal if possible), builds `build/HyperImage Converter.app`, generates icon, compiles string catalog, copies licences, fetches Upscayl if `Vendor/Upscayl/upscayl-bin` is missing, ad hoc codesigns the bundle and runs `codesign --verify --strict`. `--install` copies to `/Applications` and runs `lsregister`.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` - unit and app-flow tests
- `scripts/ui-smoke.sh` - debug build, launches with `HYPERIMAGE_SNAPSHOT` to render every sheet to PNG
- `scripts/fetch-upscayl.sh` - zsh; downloads and SHA-256 verifies the Upscayl binary and models (see INTEGRATIONS.md)
- `scripts/sync-strings.sh` - regenerates `Resources/Localizable.xcstrings` from source

## Configuration

**Environment variables read by the app or tests:**
- `HYPERIMAGE_UPSCAYL` - folder holding `upscayl-bin` and `models/`; overrides the bundled backend (`Sources/HyperImageCore/Upscale/Upscaler.swift`). Used in tests and dev.
- `HYPERIMAGE_*` (`HYPERIMAGE_FILES`, `HYPERIMAGE_SHEET`, `HYPERIMAGE_STEP`, `HYPERIMAGE_OPTIONS`, `HYPERIMAGE_WINDOW`, `HYPERIMAGE_VFOLDER`, `HYPERIMAGE_MODE`, `HYPERIMAGE_DROP`, `HYPERIMAGE_SNAPSHOT`, `HYPERIMAGE_SNAPSHOT_DELAY`, `HYPERIMAGE_OUT`) - debug-only hooks, compiled under `#if DEBUG` in `Sources/HyperImage/App/DebugLaunch.swift`
- `REF_OUTPUT_DIR`, `REF_SAVE_DIR` - optional, used by `Tests/HyperImageCoreTests/ReferenceComparison.swift`. Point at a FastStone reference output folder outside this repo.
- `DEVELOPER_DIR` - selects the Xcode toolchain for all scripts

No `.env` file, no secrets file and no `.npmrc`-style credential files are present in the repo root. Secrets management: not applicable (no credentials are used).

**Application configuration:**
- `Resources/Info.plist` - bundle id `com.hyperimage.converter`, version `1.0` (build `1`), `CFBundleDevelopmentRegion` `pt-BR`, `CFBundleLocalizations` `pt-BR` and `en`, `LSApplicationCategoryType` `public.app-category.graphics-design`, `NSHighResolutionCapable` true, `NSServices` entry for Finder ("Converter com HyperImage" → `addFilesService`), exported UTI `com.hyperimage.options` (`.hyperoptions`, conforms to `public.json`), imported UTI `com.faststone.photoresizer.options` (`.ccf`)
- No entitlements file. The app is not sandboxed. Hardened runtime is enabled only through `codesign --options runtime` in `build-app.sh`.
- `Resources/Localizable.xcstrings` - String Catalog, source language pt-BR, English translations. Compiled into `Contents/Resources` by `xcstringstool compile`.
- `.gitignore` - ignores `.build/`, `build/`, `.swiftpm/`, `*.xcodeproj`, `DerivedData/`, `.DS_Store`, `Vendor/Upscayl/`

**Persistence formats:**
- `UserDefaults` (JSON-encoded `PersistedState`, tolerant decoding via `Sources/HyperImageCore/Options/TolerantJSON.swift`)
- `.hyperoptions` files (JSON `AdvancedOptions`, written atomically by `Sources/HyperImageCore/Models/AdvancedOptions.swift`)

## Platform Requirements

**Development:**
- macOS 26 or later (the Package targets `.v26`; the local toolchain targets macOS 27)
- Xcode with its macOS SDK and SwiftUI macro plugins installed at `/Applications/Xcode.app`
- Swift tools 6.2 or newer
- Network access only when `Vendor/Upscayl` is empty and `build-app.sh` or `fetch-upscayl.sh` is run
- Optional: a FastStone reference output folder for `ReferenceComparison` tests

**Production:**
- Distributed as a locally built, ad hoc signed `.app` bundle (`build/HyperImage Converter.app`). No notarisation step, no App Store packaging, no installer, no update channel.
- Install target: `/Applications/HyperImage Converter.app` via `./build-app.sh --install`

---

*Stack analysis: 2026-10-20*
