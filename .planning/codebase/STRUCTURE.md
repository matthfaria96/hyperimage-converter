# Codebase Structure

**Analysis Date:** 2026-10-20

## Directory Layout

```
HyperImage Converter/                 # repo root (Swift package "HyperImage")
├── Package.swift                     # SwiftPM manifest: 5 targets + 2 test targets, macOS 26, swift-tools 6.2
├── build-app.sh                      # release build → build/HyperImage Converter.app (universal, ad hoc signed)
├── README.md                         # user + build docs (Portuguese)
├── Resources/                        # app bundle resources (Info.plist, icons, Localizable.xcstrings)
├── Sources/
│   ├── HyperImage/                   # SwiftUI app target (executable)
│   │   ├── App/                      # @main scene, AppModel, MainView, persisted state, About, debug hooks
│   │   ├── Input/                    # queue ("Entrada"): workspace, file cards, drop zones
│   │   ├── Browser/                  # folder/file browser sidebar
│   │   ├── Convert/                  # settings panel, runner, progress, summary, preview, format sheet, errors
│   │   ├── Advanced/                 # Advanced Options sheet and one view per step
│   │   └── Shared/                   # file panels, thumbnail cache/view, generic list editor
│   ├── HyperImageCore/               # UI-free engine (library target)
│   │   ├── Batch/                    # BatchConverter, ConvertSettings (+ InputItem, OutputPlanner), OutputRecipe (OutputEncoder)
│   │   ├── Pipeline/                 # ImagePipeline, LosslessCrop
│   │   ├── Imaging/                  # pixel operations: resampler, transforms, colour, text, watermark, border, quantizer
│   │   ├── Geometry/                 # resize / crop / canvas maths (pure, no pixels)
│   │   ├── Models/                   # Codable option structs and enums (the persisted schema)
│   │   ├── IO/                       # ImageLoader, ImageEncoder, LibJPEG, WebP/PDF/BMP encoders, metadata
│   │   ├── Files/                    # ImageFileTypes (readable extensions, filters), FileSorting
│   │   ├── Naming/                   # TextVariables (#name#, #date# … expansion)
│   │   ├── Options/                  # .ccf (FastStone) import: DelphiStream, CCFImporter, TolerantJSON
│   │   └── Upscale/                  # Upscaler (runs upscayl-bin)
│   ├── CWebP/                        # C target: libwebp 1.6.0 encoder (vendored)
│   │   ├── include/CWebP.h           # module umbrella header
│   │   ├── libwebp/                  # vendored upstream source (src/, sharpyuv/)
│   │   ├── COPYING, PATENTS          # licences (excluded from the target)
│   └── CJPEG/                        # C target: IJG libjpeg 9f (vendored) + bridge
│       ├── include/CJPEG.h           # narrow Swift-facing API
│       ├── shim/hij.c                # bridge: encode RGBA → JPEG, lossless crop
│       ├── libjpeg/                  # vendored upstream source
│       └── README-libjpeg.txt        # licence notice (excluded from the target)
├── Tests/
│   ├── HyperImageCoreTests/          # engine tests (Swift Testing, @Test)
│   │   ├── Fixtures/                 # retrato.jpg, paisagem.jpg, exemplo-opcoes.ccf
│   │   └── *Tests.swift              # one file per engine area
│   └── HyperImageAppTests/           # app-flow tests driving AppModel / ConversionRunner
│       ├── Fixtures/                 # retrato.jpg, paisagem.jpg
│       └── AppFlowTests.swift
├── scripts/                          # developer tooling (shell + Swift)
├── Vendor/Upscayl/                   # gitignored; populated by scripts/fetch-upscayl.sh
│   ├── upscayl-bin, LICENSE-AGPL-3.0.txt
│   └── models/                       # *.param / *.bin (Real-ESRGAN models)
├── .build/                           # SwiftPM build products (gitignored)
├── build/                            # app bundle output (gitignored)
├── .planning/codebase/               # these analysis documents
└── .git/
```

## Directory Purposes

**`Sources/HyperImage/App/`:**
- Purpose: Application shell and cross-screen state.
- Contains: `HyperImageApp.swift` (`@main`, `AppDelegate`, `AppCommands`), `AppModel.swift` (input list, route,
  busy flag, debounced save), `MainView.swift` (three-column layout, sheet routing, batch start and finish),
  `PersistedState.swift` (UserDefaults schema), `AboutView.swift`, `DebugLaunch.swift` (DEBUG only).
- Key files: `Sources/HyperImage/App/AppModel.swift`, `Sources/HyperImage/App/MainView.swift`

**`Sources/HyperImage/Input/`:**
- Purpose: The queue of files to convert, shown as cards with drag, drop, and virtual folders.
- Contains: `WorkspaceView.swift` (mode tabs, list, status bar, keyboard handling), `FileCard.swift` (one row),
  `DropZoneViews.swift` (empty, compact, and drop-overlay states).
- Key files: `Sources/HyperImage/Input/WorkspaceView.swift`

**`Sources/HyperImage/Browser/`:**
- Purpose: Folder navigation sidebar.
- Contains: `BrowserModel.swift` (folder listing, filter, history via `ancestors`), `BrowserView.swift`
  (list and thumbnail layouts).

**`Sources/HyperImage/Convert/`:**
- Purpose: Batch settings panel and everything that reports on a batch.
- Contains: `SettingsPanel.swift` (right column, one section per mode), `ConversionRunner.swift` (`@Observable`
  batch state), `ConversionShared.swift` (`StatusBadge`, `OverwritePanel`), `ConversionPreviewSheet.swift`,
  `FormatSettingsSheet.swift`, `SummaryBox.swift` (size estimate), `CompletionFeedback.swift` (Dock progress,
  notifications, `ErrorListSheet`).

**`Sources/HyperImage/Advanced/`:**
- Purpose: Advanced Options editor, one file per step, selected by `AdvancedStep`.
- Contains: `AdvancedOptionsSheet.swift` (container), `AdvancedStep.swift` (step enum), `ResizeStepView.swift`,
  `GeometryStepViews.swift` (flip/rotate, crop, canvas), `AdjustmentsStepView.swift`, `OverlayStepViews.swift`
  (text, watermark, border), `StepPreview.swift` (live preview through `ImagePipeline`), `Controls.swift` (shared
  controls).

**`Sources/HyperImage/Shared/`:**
- Purpose: Helpers shared by several screens.
- Contains: `FilePanels.swift` (`NSOpenPanel` / `NSSavePanel` wrappers), `Thumbnails.swift` (`ThumbnailCache.shared`,
  `ThumbnailView`), `ListEditorSheet.swift` (generic editor for resize presets and similar lists).

**`Sources/HyperImageCore/Batch/`:**
- Purpose: Turning a list of inputs and settings into outputs.
- Contains: `BatchConverter.swift` (concurrent run, overwrite decisions), `ConvertSettings.swift` (`ConvertSettings`,
  `InputItem`, `OutputPlanner`), `OutputRecipe.swift` (`ConvertMode`, format-per-file rules, `OutputEncoder` with
  file-size search, `effectiveAdvancedOptions`).

**`Sources/HyperImageCore/Pipeline/`:**
- Purpose: Ordered application of Advanced Options to a `CGImage`.
- Contains: `ImagePipeline.swift` (the step order), `LosslessCrop.swift` (block-level JPEG crop used instead of
  re-encoding when possible).

**`Sources/HyperImageCore/Imaging/`:**
- Purpose: Pixel-level implementations. Each file is a stateless `enum` namespace or a small struct.
- Contains: `Bitmap.swift` (RGBA8 buffer and `PixelSize` helpers, `ImagingError` declared here),
  `Resampler.swift` + `ResampleKernel.swift` (separable filters, the 12 original kernels), `Transforms.swift`
  (resize, flip, rotate, canvas, colour reduction), `ColorAdjuster.swift` + `HueRotation.swift` (Core Image),
  `TextOverlay.swift` + `Drawing.swift`, `WatermarkOverlay.swift`, `BorderEffect.swift`, `Quantizer.swift` (median cut).

**`Sources/HyperImageCore/Geometry/`:**
- Purpose: Size and rectangle calculations, kept separate from pixel code so they can be unit tested
  (`Tests/HyperImageCoreTests/GeometryTests.swift`).
- Contains: `Geometry.swift` (`PixelRect`, orientation helpers), `ResizeGeometry.swift`, `CropGeometry.swift`
  (block-aligned crops for JPEG), `CanvasGeometry.swift`.

**`Sources/HyperImageCore/Models/`:**
- Purpose: Option and format definitions. These types are the JSON schema for `.hyperoptions` and
  `PersistedState`, so renaming a field breaks saved files.
- Contains: `AdvancedOptions.swift` (the umbrella struct), `ResizeOptions.swift`, `TransformOptions.swift`
  (rotate, crop, canvas), `EffectOptions.swift` (colour depth, adjustments), `OverlayOptions.swift` (text, watermark),
  `Placement.swift`, `RGBAColor.swift`, `StandardSizes.swift` (resize presets), and `OutputFormat.swift` (formats,
  `FormatSettings`, JPEG/PNG/TIFF/WebP/… settings).

**`Sources/HyperImageCore/IO/`:**
- Purpose: Decoding and encoding.
- Contains: `ImageLoader.swift` (ImageIO decode with orientation), `ImageEncoder.swift` (format dispatch),
  `LibJPEG.swift` (Swift side of the CJPEG bridge), `WebPEncoder.swift`, `PDFEncoder.swift`, `BMPEncoder.swift`
  (palette BMP writer), `JPEGMetadataWriter.swift`, `JPEGQualityEstimator.swift`, `ImageMetadata.swift`,
  `ColorConversion.swift`.

**`Sources/HyperImageCore/Files/`:**
- Purpose: File-type rules and list sorting.
- Contains: `ImageFileTypes.swift` (readable extension set, browser filters, folder scan), `FileSorting.swift`
  (`InputSort`, `SortKeyCache.shared`).

**`Sources/HyperImageCore/Options/`:**
- Purpose: Reading the original FastStone `.ccf` format.
- Contains: `CCFImporter.swift`, `DelphiStream.swift` (Delphi binary reader), `TolerantJSON.swift` (decode with
  defaults for missing keys, used by `PersistedState`).

**`Sources/HyperImageCore/Naming/`:**
- Purpose: Text variables for overlays and names.
- Contains: `TextVariables.swift`.

**`Sources/HyperImageCore/Upscale/`:**
- Purpose: The AI upscale adapter.
- Contains: `Upscaler.swift` (`UpscaleModel`, `UpscaleFormat`, `UpscaleSettings`, `Upscaler`).

**`Sources/CWebP/` and `Sources/CJPEG/`:**
- Purpose: Vendored C sources. Treat as third-party code: do not edit files under `libwebp/` or `libjpeg/`. Put
  project-specific C in `CJPEG/shim/` only.
- Generated: No. Committed: Yes (vendored).

**`Tests/HyperImageCoreTests/`:**
- Purpose: Engine tests, one file per area. Names describe the behaviour (`PipelineTests`, `EncoderTests`,
  `JPEGTests`, `GeometryTests`, `CCFImportTests`, `UpscaleTests`, `RegressionTests`, `FormatSweepTests`,
  `PipelineSweepTests`, `UnusualInputTests`, `ReferenceComparison`, `GIFSpeedTests`).
- Key files: `Tests/HyperImageCoreTests/Fixtures/`

**`Tests/HyperImageAppTests/`:**
- Purpose: End-to-end app flows through `AppModel` and `ConversionRunner` (input list, overwrite prompt, cancel,
  virtual folders, lossless crop).
- Key files: `Tests/HyperImageAppTests/AppFlowTests.swift`

**`scripts/`:**
- Purpose: Developer tooling.
- Contains: `fetch-upscayl.sh` (downloads and SHA-256 checks `upscayl-bin` and models into `Vendor/Upscayl/`),
  `sync-strings.sh` (re-extracts strings into `Resources/Localizable.xcstrings`), `ui-smoke.sh` (opens every sheet
  and saves a screenshot), `debug-shot.sh` (screenshot one debug launch), `window-id.swift` (helper for the
  screenshot scripts), `make-icon.swift` (masks a source PNG into the macOS icon shape).

**`Resources/`:**
- Purpose: Bundle resources copied by `build-app.sh`.
- Contains: `Info.plist` (bundle id `com.hyperimage.converter`, minimum macOS 26.0, `CFBundleDocumentTypes`, and `NSServices` for the Finder action), `Localizable.xcstrings` (pt-BR source and en
  translations), `AppIcon-1024.png` (icon source), `icon-source.png`.

**`Vendor/Upscayl/`:**
- Purpose: The external AI engine. Not in git (`.gitignore`); fetched by `scripts/fetch-upscayl.sh`.
- Generated: Downloaded. Committed: No.

**`build/` and `.build/`:**
- Purpose: Build outputs. `.build/` is SwiftPM's scratch space; `build/` holds the `.app` bundle.
- Generated: Yes. Committed: No (both are gitignored).

## Key File Locations

**Entry Points:**
- `Sources/HyperImage/App/HyperImageApp.swift`: `@main` app, scenes, menus, Finder service, open-file handling.
- `build-app.sh`: produces the distributable `.app`.

**Configuration:**
- `Package.swift`: targets, C compiler flags (`-O3` in release only), `defaultIsolation(MainActor.self)` for the app.
- `Resources/Info.plist`: bundle identifier `com.hyperimage.converter`, minimum OS 26.0, document types, Finder service.
- `.gitignore`: ignores `.build/`, `build/`, `.swiftpm/`, `*.xcodeproj`, `DerivedData/`, `.DS_Store`, `Vendor/Upscayl/`.

**Core Logic:**
- `Sources/HyperImageCore/Batch/BatchConverter.swift`: batch run.
- `Sources/HyperImageCore/Pipeline/ImagePipeline.swift`: Advanced Options order.
- `Sources/HyperImageCore/IO/ImageEncoder.swift`: format dispatch.
- `Sources/HyperImageCore/Models/OutputFormat.swift`: formats and per-format settings.

**Testing:**
- `Tests/HyperImageCoreTests/`: engine.
- `Tests/HyperImageAppTests/`: app flows.
- `scripts/ui-smoke.sh`: manual visual smoke test.

## Naming Conventions

**Files:**
- One primary type per file, named after it: `ConversionRunner.swift` contains `ConversionRunner`,
  `ImagePipeline.swift` contains `ImagePipeline`.
- Exception: `Shared/` and `Convert/` files that hold several small views, such as `ConversionShared.swift`
  (`StatusBadge`, `OverwritePanel`) and `Controls.swift`.
- SwiftUI views end in `View` (`MainView`, `FileCard` is an exception that stays unsuffixed). Step views end in
  `StepView` (`ResizeStepView`, `AdjustmentsStepView`).
- Test files end in `Tests` (`PipelineTests.swift`). Two exceptions exist: `ReferenceComparison.swift` (no suffix)
  and `GIFSpeedTests.swift`, which measures GIF palette reduction speed on a noisy photo-like image. Every test file uses the Swift Testing framework (`import Testing`, `@Test`).

**Types:**
- Option bundles end in `Options` (`ResizeOptions`, `CropOptions`, `TextOptions`, `AdvancedOptions`) when they are
  Advanced Options steps, and in `Settings` (`JPEGSettings`, `PNGSettings`, `FormatSettings`, `ConvertSettings`) when
  they configure an encoder or the batch.
- Engine namespaces are caseless `enum`s with static functions: `ImageLoader`, `ImageEncoder`, `OutputEncoder`,
  `OutputPlanner`, `ResizeGeometry`, `Transforms`, `ColorAdjuster`, `ImageFileTypes`.
- Format and mode enums use lowerCamelCase cases that are also the raw values: `OutputFormat.jpeg2000`,
  `ConvertMode.compress`, `JPEGSubsampling.high`.
- C-facing symbols use the prefix `HIJ` (libjpeg bridge, `HIJColorSpace`, `HIJ_GRAY`) and `hij_` (functions).

**Functions and properties:**
- Standard Swift API Design Guidelines. Static factories use `.bundled()`, `.load(_:)`, `.encode(_:…)`.
- Predicates use `is…`/`is` (`ImageFileTypes.isImage`, `TIFFCompression.isFax`).

**Directories:**
- Feature folders under `Sources/HyperImage/` are singular nouns for the feature area (`Browser`, `Convert`,
  `Advanced`, `Input`). Engine folders under `Sources/HyperImageCore/` are grouped by responsibility (`IO`,
  `Imaging`, `Models`, `Geometry`).
- The app and the engine follow the same split (`App/`, `Shared/`) but only the app uses UI folders.

**Strings:**
- UI strings are Portuguese source text inside `String(localized:)`, for example
  `String(localized: "Converter com HyperImage")`. English translations come from `Resources/Localizable.xcstrings`.

## Where to Add New Code

**New output format:**
- Enum case and settings: `Sources/HyperImageCore/Models/OutputFormat.swift` (`OutputFormat`, `FormatSettings`)
- Encoder: `Sources/HyperImageCore/IO/` (new `<Name>Encoder.swift`). Dispatch it in `ImageEncoder.encode` and
  `ImageEncoder.prepare`.
- Format UI: `Sources/HyperImage/Convert/FormatSettingsSheet.swift`
- Input extension (if it is readable): `Sources/HyperImageCore/Files/ImageFileTypes.swift`
- Tests: `Tests/HyperImageCoreTests/EncoderTests.swift` or `FormatSweepTests.swift`

**New Advanced Options step:**
- Options struct: `Sources/HyperImageCore/Models/` (add to an existing file if it matches the group, otherwise a new
  file). Add a property to `AdvancedOptions` in `Sources/HyperImageCore/Models/AdvancedOptions.swift`.
- Pixel code: `Sources/HyperImageCore/Imaging/<Name>.swift` (an `enum` namespace with a static `apply`).
- Pipeline position: `Sources/HyperImageCore/Pipeline/ImagePipeline.swift` (keep the documented order).
- UI: `Sources/HyperImage/Advanced/<Name>StepView.swift`, plus a case in `AdvancedStep.swift`.
- Tests: `Tests/HyperImageCoreTests/PipelineTests.swift`.

**New batch-level setting:**
- Field in `Sources/HyperImageCore/Batch/ConvertSettings.swift`. Decoding stays tolerant, so give it a default.
- UI in `Sources/HyperImage/Convert/SettingsPanel.swift`.

**New window, sheet, or menu command:**
- Sheet: add a case to `SheetRoute` in `Sources/HyperImage/App/MainView.swift` and a branch in `sheetView(_:)`.
  Put the view in `Sources/HyperImage/Convert/` or `Sources/HyperImage/Advanced/`.
- Menu command: `AppCommands` in `Sources/HyperImage/App/HyperImageApp.swift`.
- Separate window: add a `Window` scene in `HyperImageApp.body` (see the About window).

**New engine utility:**
- Pure geometry: `Sources/HyperImageCore/Geometry/`
- Pixel operation on a `Bitmap` or `CGImage`: `Sources/HyperImageCore/Imaging/`
- Format or metadata I/O: `Sources/HyperImageCore/IO/`

**New app feature with state:**
- Shared state: a property on `AppModel` (`Sources/HyperImage/App/AppModel.swift`) if it spans windows,
  or on the view's model (`ConversionRunner`, `BrowserModel`) if it belongs to one flow.
- Persisted: add a field to `PersistedState` (`Sources/HyperImage/App/PersistedState.swift`) with a default.

**Shared UI helper:**
- `Sources/HyperImage/Shared/`

**Tests for the app layer:**
- `Tests/HyperImageAppTests/AppFlowTests.swift` (or a new file in that folder). Use the `Fixtures/` images there.

**Vendored library updates:**
- Replace the whole upstream tree in `Sources/CWebP/libwebp/` or `Sources/CJPEG/libjpeg/`. Keep project code out of
  those folders. Shim changes go in `Sources/CJPEG/shim/hij.c` and `Sources/CJPEG/include/CJPEG.h`.

## Special Directories

**`Vendor/Upscayl/`:**
- Purpose: External AI engine binary and models.
- Generated: Yes, by `scripts/fetch-upscayl.sh` (also run automatically by `build-app.sh` when files are missing).
- Committed: No (gitignored). The licence file `LICENSE-AGPL-3.0.txt` is copied into `Contents/Resources/Licenses/`.

**`build/`:**
- Purpose: `HyperImage Converter.app` output.
- Generated: Yes, by `build-app.sh`.
- Committed: No.

**`.build/`:**
- Purpose: SwiftPM build directory.
- Generated: Yes.
- Committed: No.

**`.planning/`:**
- Purpose: Planning and codebase analysis documents.
- Generated: Yes (by GSD commands).
- Committed: Follows the project's git policy (currently untracked).

**`Resources/Localizable.xcstrings`:**
- Purpose: String catalog. Edit it in Xcode or regenerate with `scripts/sync-strings.sh`.
- Generated: Partly (via `sync-strings.sh`). Committed: Yes.

---

*Structure analysis: 2026-10-20*
