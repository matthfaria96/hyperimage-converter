<!-- refreshed: 2026-10-20 -->
# Architecture

**Analysis Date:** 2026-10-20

## System Overview

```text
┌──────────────────────────────────────────────────────────────────────────┐
│                    SwiftUI app target  `Sources/HyperImage`               │
│  App shell · Input list · Browser · Settings panel · Advanced/Format sheets│
├───────────────────────┬──────────────────────┬───────────────────────────┤
│ AppModel (@Observable)│ ConversionRunner     │ BrowserModel              │
│ `App/AppModel.swift`  │ `Convert/ConversionRunner.swift` │ `Browser/BrowserModel.swift` │
└───────────┬───────────┴──────────┬───────────┴─────────────┬─────────────┘
            │ InputItem / ConvertSettings / PersistedState     │ ConversionRecord
            ▼                      ▼                          ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                  Engine target  `Sources/HyperImageCore` (no UI)          │
│  Batch/BatchConverter · Batch/OutputRecipe (OutputEncoder, OutputPlanner) │
│  Pipeline/ImagePipeline + LosslessCrop · Imaging/* · Geometry/* · Models/*│
│  IO/ImageLoader · IO/ImageEncoder · IO/LibJPEG · IO/WebPEncoder · IO/PDF  │
│  Upscale/Upscaler · Options/CCFImporter · Naming/TextVariables           │
└───────────┬───────────────────────────────┬──────────────────────────────┘
            │                               │
            ▼                               ▼
┌──────────────────────────┐   ┌──────────────────────────────────────────┐
│ System frameworks         │   │ Vendored C targets                        │
│ ImageIO · CoreGraphics ·  │   │ `Sources/CWebP` (libwebp 1.6.0, encoder)  │
│ Core Image · CoreGraphics PDF ·     │   │ `Sources/CJPEG` (libjpeg 9f + `shim/hij.c`)│
│ UniformTypeIdentifiers    │   └──────────────────────────────────────────┘
└──────────────────────────┘
            ▲
            │ spawns as a child process (stdout parsed for percentages)
┌──────────────────────────────────────────────────────────────┐
│ `upscayl-bin` + models (`Vendor/Upscayl/`, copied into the .app) │
└──────────────────────────────────────────────────────────────┘
```

## Pattern Overview

**Overall:** Two-layer modular monolith. A pure, UI-free image engine (`HyperImageCore`) sits under a SwiftUI
application target (`HyperImage`). The engine is a set of value types and stateless `enum` namespaces, the app layer
holds all mutable state in `@Observable` classes. Two C libraries are vendored as SwiftPM targets for encoders
that ImageIO cannot provide.

**Key Characteristics:**
- Dependency direction is one-way: `HyperImage` → `HyperImageCore` → `CWebP`, `CJPEG`. Nothing in `HyperImageCore`
  imports SwiftUI or AppKit (it does use `String(localized:)` and Foundation). Declared in `Package.swift`.
- Engine types are `public` value types marked `Codable, Equatable, Sendable` (for example `AdvancedOptions`,
  `ConvertSettings`, `FormatSettings`). They double as the persisted JSON schema.
- Swift 6.2 language mode with strict concurrency. The `HyperImage` and `HyperImageAppTests` targets use
  `defaultIsolation(MainActor.self)`, so app code is main-actor by default and heavy work is moved off it with
  `Task.detached`. `HyperImageCore` has no default isolation and uses `Sendable` values.
- The app is a single window (`Window("HyperImage Converter", id: "main")`) with a `NavigationSplitView` whose detail
  column is an `HStack` of workspace + settings panel. Modal flows are `SheetRoute` values on `AppModel.route`.
- Batch concurrency is a `ThrowingTaskGroup` capped by `BatchConverter.maxConcurrency`: `1` for AI Upscale
  (GPU-bound), otherwise `min(activeProcessorCount, 6)` when "parallel" is on, else `1`.

## Layers

**Engine (`Sources/HyperImageCore`):**
- Purpose: Everything needed to turn a file into a converted file, with no UI.
- Location: `Sources/HyperImageCore/`
- Contains: options models (`Models/`), geometry math (`Geometry/`), pixel operations (`Imaging/`), encoders and
  decoders (`IO/`), the step pipeline (`Pipeline/`), batch orchestration and output naming (`Batch/`), file-type
  and sorting helpers (`Files/`), text-variable expansion (`Naming/`), legacy `.ccf` import (`Options/`), AI upscale
  driver (`Upscale/`).
- Depends on: `CWebP`, `CJPEG`, ImageIO, CoreGraphics, CoreImage, UniformTypeIdentifiers.
- Used by: `HyperImage` app target and `HyperImageCoreTests` / `HyperImageAppTests`.

**App (`Sources/HyperImage`):**
- Purpose: SwiftUI presentation, window/menu wiring, user-facing state, persistence of UI state.
- Location: `Sources/HyperImage/`
- Contains: `App/` (scene, app model, persisted state, debug hooks), `Input/` (queue and drop zone),
  `Browser/` (folder tree sidebar), `Convert/` (settings panel, runner, progress/summary, previews),
  `Advanced/` (Advanced Options sheet and per-step views), `Shared/` (file panels, thumbnails, list editor).
- Depends on: `HyperImageCore` (imports `HyperImageCore` in nearly every file).
- Used by: end users; the `HyperImageAppTests` target drives `AppModel` and `ConversionRunner` directly.

**C bridges (`Sources/CWebP`, `Sources/CJPEG`):**
- Purpose: Provide encoders not available through ImageIO.
- Location: `Sources/CWebP/` (header `include/CWebP.h`, sources in `libwebp/`), `Sources/CJPEG/` (header
  `include/CJPEG.h`, IJG sources in `libjpeg/`, bridge `shim/hij.c`).
- Contains: C only. `CJPEG.h` exposes a narrow API (`hij_encode_rgba`, a lossless crop function) so Swift never sees
  libjpeg macros or `setjmp`.
- Used by: `Sources/HyperImageCore/IO/LibJPEG.swift` (JPEG writing, lossless crop) and `IO/WebPEncoder.swift`.

## Data Flow

### Primary Request Path: Batch Convert

1. A user adds files or folders. `AppModel.addInBackground(_:)` (`Sources/HyperImage/App/AppModel.swift`) scans
   off the main actor with `AppModel.scan`, which uses `ImageFileTypes.images(in:)` and `ImageFileTypes.isImage`
   (`Sources/HyperImageCore/Files/ImageFileTypes.swift`). The result is merged into `AppModel.inputs: [InputItem]`
   and sorted by `InputSort` (`Sources/HyperImageCore/Files/FileSorting.swift`).
2. The Convert button or the ⌘Return menu command bumps `AppModel.startRequest` (`App/MainView.swift`). `MainView.startConversion()`
   validates Advanced Options (`AdvancedOptions.validationError()`), asks for an output folder if needed, and calls
   `ConversionRunner.start(items:settings:)`.
3. `ConversionRunner.start` (`Sources/HyperImage/Convert/ConversionRunner.swift`) creates a `BatchConverter` with a
   progress callback, calls `converter.records(for:)` (which calls `OutputPlanner.destinations` in
   `Sources/HyperImageCore/Batch/ConvertSettings.swift` to resolve each output URL), and starts a `Task` that
   calls `BatchConverter.run`.
4. `BatchConverter.run` (`Sources/HyperImageCore/Batch/BatchConverter.swift`) builds one `ImagePipeline` from
   `settings.effectiveAdvancedOptions` (`Batch/OutputRecipe.swift`) and iterates records in a task group. When an
   output exists and "ask before overwrite" or "skip existing" is set, it awaits `askOverwrite`. The runner
   answers through a `CheckedContinuation` that drives `OverwritePanel` in the UI.
5. Each record runs `convert(_:pipeline:)` (or `upscale(_:)` in AI Upscale mode):
   - `ImageLoader.load(_:)` (`Sources/HyperImageCore/IO/ImageLoader.swift`) decodes through ImageIO, applies EXIF
     orientation, and reads metadata. JPEG quality is estimated by `JPEGQualityEstimator`.
   - `OutputEncoder.encode(_:pipeline:settings:)` (`Batch/OutputRecipe.swift`) calls `ImagePipeline.encode`. That
     either performs a lossless JPEG crop (`Pipeline/LosslessCrop.swift`) or runs `ImagePipeline.process`
     followed by `ImageEncoder.encode`. If a file-size cap is set, it binary-searches the quality value.
   - `ImageEncoder.encode` (`Sources/HyperImageCore/IO/ImageEncoder.swift`) dispatches by `OutputFormat`: JPEG to
     `LibJPEG.encode`, WebP to `WebPEncoder`, PDF to `PDFEncoder`, palette BMP to `BMPEncoder`, everything else to
     `CGImageDestination`.
   - The result is written with `Data.write(options: .atomic)` and dates are copied from the input.
6. Each finished record goes back through `update` to `ConversionRunner.apply(_:run:)`, which stores it in
   `records` and calls `recount()` to refresh cached totals. Views observe these stored aggregates.
7. On completion `ConversionRunner.finish()` bumps `completionID`. `MainView.batchFinished()` shows the error list
   or an alert, updates the Dock progress, and posts a `CompletionNotifier` notification.

### AI Upscale Path

1. `BatchConverter.upscale(_:)` calls `Upscaler.upscale(_:to:settings:progress:)`
   (`Sources/HyperImageCore/Upscale/Upscaler.swift`). Inputs ImageIO can not hand straight to the binary (HEIC, TIFF,
   RAW, or any rotated JPEG) are first written to a temporary PNG.
2. `Upscaler.run` launches `upscayl-bin` from the app bundle (`Contents/MacOS/upscayl-bin`) with the models folder
   from `Contents/Resources/Upscayl/models`. It parses percentages from stdout/stderr through `LogBuffer` and
   reports them via `progress`. Cancellation terminates the process.
3. The output is written to a temp path and then moved into place, so cancelled runs leave no partial file.

### Preview Path

`ConversionPreviewSheet` and `SummaryBox` call `OutputEncoder.encode` on the same engine path so the preview and
size estimate match the real output. `StepPreview` (`Advanced/StepPreview.swift`) runs `ImagePipeline` on a
downscaled image for the Advanced Options steps.

### Browser Path

`BrowserModel` (`Sources/HyperImage/Browser/BrowserModel.swift`) lists a folder off the main actor with
`contentsOfDirectory`, filters by `FileTypeFilter`, and sorts folders first. Its `folder` is persisted as
`PersistedState.browserPath`.

**State Management:**
- Persisted UI and settings: `PersistedState` (`Sources/HyperImage/App/PersistedState.swift`) is stored as JSON in
  `UserDefaults` under the key `HyperImage.state.v1`. `AppModel.state` has a `didSet` that schedules a save 400 ms
  later (`scheduleSave`). `applicationWillTerminate` flushes it through `AppModel.saveNow()`.
- Tolerant decoding: `TolerantJSON.decode` (`Sources/HyperImageCore/Options/TolerantJSON.swift`) fills missing keys
  from defaults, so older saved state still loads. Several settings types (for example `JPEGSettings`,
  `PNGSettings`) also implement their own `init(from:)` with `decodeIfPresent`.
- Input queue: `AppModel.inputs` is the single source of truth. It is frozen while a batch runs
  (`MainView`/`WorkspaceView` check `runner.isRunning`).
- Batch state: `ConversionRunner` (`@Observable`) holds `records`, aggregates, `prompt`, and `failures`. Late updates
  from a cancelled run are dropped by comparing a `generation` counter.
- Advanced Options: a value type (`AdvancedOptions`) held in `ConvertSettings.advanced`. It is exported and imported
  as `.hyperoptions` JSON. Legacy `.ccf` files are read-only through `CCFImporter`.
- Process-wide singletons: `ThumbnailCache.shared` (`Sources/HyperImage/Shared/Thumbnails.swift`) and
  `SortKeyCache.shared` (`Sources/HyperImageCore/Files/FileSorting.swift`).

## Key Abstractions

**`LoadedImage`:**
- Purpose: A decoded, upright source with its URL, metadata, ImageIO properties and file dates.
- Examples: `Sources/HyperImageCore/IO/ImageLoader.swift`
- Pattern: Immutable `Sendable` value passed through the pipeline.

**`ImagePipeline` / `ProcessedImage`:**
- Purpose: Runs the enabled Advanced Options steps in the fixed order documented at the top of the type
  (adjustments, resize, rotate/flip, crop, canvas, adjustments, colour depth, DPI, text, watermark, border).
- Examples: `Sources/HyperImageCore/Pipeline/ImagePipeline.swift`, `Sources/HyperImageCore/Pipeline/LosslessCrop.swift`
- Pattern: Each step is a stateless `enum` namespace (`Transforms`, `ColorAdjuster`, `TextOverlay`,
  `WatermarkOverlay`, `BorderEffect`) that takes a `CGImage` and an options struct. Steps are skipped when
  `enabled` is false.

**`OutputFormat` + `FormatSettings`:**
- Purpose: The ten output formats (JPEG, BMP, GIF, PNG, JPEG 2000, TIFF, PDF, WebP, HEIC, AVIF) and their per-format
  settings.
- Examples: `Sources/HyperImageCore/Models/OutputFormat.swift`, `Sources/HyperImageCore/Batch/OutputRecipe.swift`
- Pattern: Format-specific behaviour is a `switch` over `OutputFormat`, used in `ImageEncoder.prepare` and in
  `OutputEncoder`. Adding a format means touching both places plus `ImageFileTypes`.

**`ConvertSettings` / `InputItem` / `ConversionRecord`:**
- Purpose: Settings for a batch, one queued file (with optional folder context and "virtual folder"), and the result
  of one conversion.
- Examples: `Sources/HyperImageCore/Batch/ConvertSettings.swift`, `Sources/HyperImageCore/Batch/BatchConverter.swift`
- Pattern: Value types. `ConversionRecord.with(status:)` returns a modified copy.

**`ConvertMode`:**
- Purpose: The three top-level modes, `convert`, `compress`, `upscale`. Each one changes output format selection,
  naming, and which controls are enabled.
- Examples: `Sources/HyperImageCore/Batch/OutputRecipe.swift`, `Sources/HyperImage/App/HyperImageApp.swift` (menu
  shortcuts ⌘1 to ⌘3)

**`Upscaler`:**
- Purpose: Process-boundary adapter to the external `upscayl-bin`.
- Examples: `Sources/HyperImageCore/Upscale/Upscaler.swift`, `scripts/fetch-upscayl.sh`
- Pattern: `Upscaler.bundled()` returns nil when the binary is absent. The `HYPERIMAGE_UPSCAYL` environment variable
  overrides the location in tests.

**`SheetRoute`:**
- Purpose: The one modal presented over the main window (format settings, advanced, preview, errors).
- Examples: `Sources/HyperImage/App/MainView.swift`
- Pattern: Enum with `Identifiable`. `AppModel.route` is set by views and by menu commands alike.

## Entry Points

**`HyperImageApp` (`@main`):**
- Location: `Sources/HyperImage/App/HyperImageApp.swift`
- Triggers: App launch. Registers `AppDelegate` through `@NSApplicationDelegateAdaptor`.
- Responsibilities: Builds the main `Window`, the About window (`AboutView`), the `AppCommands` menus, and applies the
  appearance (system, light, or dark) to `NSApp`.

**`AppDelegate`:**
- Location: `Sources/HyperImage/App/HyperImageApp.swift`
- Triggers: Files opened in Finder or dropped on the Dock icon (`application(_:open:)`), and the Finder service
  "Converter com HyperImage" (`addFilesService`, declared in `Resources/Info.plist`).
- Responsibilities: Queues URLs that arrive before `AppModel` exists (`pending`), flushes the model on terminate.

**`MainView`:**
- Location: `Sources/HyperImage/App/MainView.swift`
- Triggers: The main window.
- Responsibilities: Composes `BrowserView` (sidebar), `WorkspaceView`, and `SettingsPanel`; owns the
  `ConversionRunner`; routes sheets and the overwrite overlay; starts and finishes batches.

**Debug hooks (DEBUG builds only):**
- Location: `Sources/HyperImage/App/DebugLaunch.swift`
- Triggers: `HYPERIMAGE_*` environment variables, used by `scripts/debug-shot.sh` and `scripts/ui-smoke.sh`.

**Build entry:**
- Location: `build-app.sh` (release, universal, ad hoc signed, produces `build/HyperImage Converter.app`).

## Architectural Constraints

- **Threading:** The app target defaults to `MainActor`. Image work runs in `Task.detached` (for example
  `ThumbnailCache.image`, `AppModel.addInBackground`, `BrowserModel.reload`) or in `BatchConverter`'s task group.
  Inside the engine, `Resampler` and `FileSorting` use `DispatchQueue.concurrentPerform` with
  `nonisolated(unsafe)` pointers (`Sources/HyperImageCore/Imaging/Resampler.swift`). Upscale runs one file at a time
  because the GPU is already saturated.
- **Global state:** `ThumbnailCache.shared` (`Sources/HyperImage/Shared/Thumbnails.swift`), `SortKeyCache.shared`
  (`Sources/HyperImageCore/Files/FileSorting.swift`), `PersistedState.key` in `UserDefaults`,
  `NSApp.servicesProvider` set in `AppDelegate.applicationDidFinishLaunching`, and `NSApp.appearance`.
- **Circular imports:** None. The target graph in `Package.swift` is acyclic.
- **Engine has no UI dependencies:** `HyperImageCore` must not import SwiftUI or AppKit. Keep it that way so the engine
  stays testable through `HyperImageCoreTests`.
- **Ordering rules:** Pipeline step order is fixed (see `ImagePipeline.process`). Lossless JPEG crop is only valid when
  crop is the only pixel-changing step (`ImagePipeline.encode`, `LosslessCrop.swift`).
- **Output name collisions:** `OutputPlanner.destinations` reserves all input paths first, so an output never
  overwrites an input that has not been read yet.
- **Licensing boundary:** `upscayl-bin` (AGPL-3.0) runs as a separate process. The engine links only to libwebp (BSD)
  and libjpeg (IJG). Vendored code lives in `Sources/CWebP` and `Sources/CJPEG`; the binary and models live in the
  gitignored `Vendor/Upscayl/`.

## Anti-Patterns

### Duplicated source of truth for "open folder when done"

**What happens:** `ConversionRunner.openFolderWhenDone` and `ConvertSettings.openFolderWhenDone` both hold the same
flag. `MainView` copies it back with `.onChange(of: runner.openFolderWhenDone)`.
**Why it's wrong:** The two values can drift. Any new code that reads one but writes the other will desync.
**Do this instead:** Read and write `app.state.convert.openFolderWhenDone` only. Give `ConversionRunner` read access
through `settings`, which it already copies at `start`, as `finish()` already does for other settings.

### Upscale mode bypasses the Advanced pipeline

**What happens:** `BatchConverter.run` builds `ImagePipeline(options: settings.effectiveAdvancedOptions)` for every
mode, but `BatchConverter.upscale` never calls it. Upscale output is governed only by `UpscaleSettings`.
**Why it's wrong:** A reader of `ConvertSettings` may expect Advanced Options to apply in every mode. The `MainView`
validation (`settings.mode != .upscale`) and the menu disables are the only things keeping them consistent.
**Do this instead:** Keep the mode check in `BatchConverter.run` next to the pipeline construction, or move the
pipeline construction inside the `convert` branch so the dependency is obvious.

### Main-thread `FileManager` work in `ConversionRunner.start`

**What happens:** `ConversionRunner.start` calls `converter.records(for:)`, which calls `BatchConverter.fileSize` for
every item (`Sources/HyperImageCore/Batch/BatchConverter.swift`). This happens on the main actor.
**Why it's wrong:** For large lists this blocks the UI at the moment the user presses Convert.
**Do this instead:** Compute record sizes in the background, the way `AppModel.refreshTotal` already does with
`InputSort.cachedSize`.

## Error Handling

**Strategy:** Errors are values at the file level and exceptions at the batch level.

**Patterns:**
- `ImagingError` (defined in the engine) cases such as `unreadable`, `watermarkMissing`, and `encodeFailed` are thrown
  by the engine. `BatchConverter.convert` catches every error and stores `ConversionStatus.failed(message)` on the
  record, so one bad file does not stop the batch.
- `BatchConverter.run` throws only for batch-wide failures (`CancellationError` from the overwrite prompt, or a
  pipeline that cannot be built, such as a missing watermark file).
- `ConversionRunner` maps a thrown `CancellationError` to `wasCancelled` and any other error to `failure`. `MainView`
  shows that as an alert and lists per-file failures in `ErrorListSheet`.
- `UpscaleError` (`backendMissing`, `failed`) is a `LocalizedError`.

## Cross-Cutting Concerns

**Logging:** No logging framework. Debug output goes through `DebugLaunch` only in DEBUG builds.
**Validation:** Options validate through `AdvancedOptions.validationError()` before a batch starts. Filename parts are
validated by `InputItem.folderName(_:)`. Settings decode tolerantly from JSON.
**Localization:** Portuguese is the source language. Strings are wrapped with `String(localized:)` and stored in
`Resources/Localizable.xcstrings`, compiled by `build-app.sh`, and refreshed by `scripts/sync-strings.sh`.
**Authentication:** Not applicable. The app has no network access and no accounts.

---

*Architecture analysis: 2026-10-20*
