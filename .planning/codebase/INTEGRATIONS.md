# External Integrations

**Analysis Date:** 2026-10-20

HyperImage Converter is a local, offline macOS app. It has no backend, no accounts and no network calls at runtime. The integrations below are (a) Apple system services, (b) one bundled child-process engine, (c) build-time downloads, and (d) local file formats.

## APIs & External Services

**Runtime network access:**
- None in app code. There is no `URLSession`, `URLRequest` or HTTP client anywhere under `Sources/`.
- Only outbound link: `Sources/HyperImage/Convert/SettingsPanel.swift` (line ~305) opens `https://github.com/upscayl/upscayl-ncnn` in the browser via SwiftUI `Link`, labelled "Ver código-fonte do motor".

**AI upscale engine (bundled, local):**
- Upscayl `upscayl-bin` (AGPL-3.0, Real-ESRGAN on the GPU) run as a separate process
  - Launcher: `Sources/HyperImageCore/Upscale/Upscaler.swift` (`Process`, `Pipe`, `terminationHandler`, `readabilityHandler`)
  - Location resolved by `Upscaler.bundled()`: `Contents/MacOS/upscayl-bin` inside the app bundle, models at `Contents/Resources/Upscayl/models`
  - Override for development and tests: env var `HYPERIMAGE_UPSCAYL` pointing to a folder containing `upscayl-bin` and `models/`
  - Arguments passed: `-i <input> -o <output> -m <models> -n <model> -s <2..4> -f <png|jpg|webp> -c <0..100>`
  - Progress: parses percentages from stdout/stderr lines (`Upscaler.percentage`)
  - Cancellation: `withTaskCancellationHandler` calls `process.terminate()`
  - Input normalisation: inputs the backend cannot read (HEIC, TIFF, RAW, or rotated JPEG/PNG/WebP) are first converted to a temporary PNG with ImageIO (`ImageLoader.load`)
  - Temporary files live in `FileManager.temporaryDirectory/hyperimage-upscale-<UUID>` and are removed in a `defer`
  - Concurrency: forced to one upscale at a time (`Sources/HyperImageCore/Batch/BatchConverter.swift`)
- Licensing: AGPL-3.0 licence text copied to `Contents/Resources/Licenses/upscayl-LICENSE-AGPL-3.0.txt`. Non-commercial models (Remacri, UltraSharp, Ultramix) are deliberately excluded (`README.md`, `scripts/fetch-upscayl.sh`).

## Build-Time Downloads

**`scripts/fetch-upscayl.sh`** (zsh, run manually or from `build-app.sh` when `Vendor/Upscayl/upscayl-bin` is missing):
- GitHub release asset: `https://github.com/upscayl/upscayl-ncnn/releases/download/20251207-174704/upscayl-bin-20251207-174704-macos.zip`
  - SHA-256 pinned: `BIN_SHA` in the script
  - Extracted with `ditto`, `xattr -c` applied, installed as `Vendor/Upscayl/upscayl-bin`
- Model files from `https://raw.githubusercontent.com/upscayl/upscayl/<pinned commit>/resources/models/`
  - Four files pinned by commit `a00d55fee90e0f9435d5eaa86e76700df8199af8`, each SHA-256 checked (`MODEL_SHA`)
  - Destination: `Vendor/Upscayl/models/`
- Licence: `https://raw.githubusercontent.com/upscayl/upscayl-ncnn/<commit 0beb39028a0ddd83250e845b4c3333c0675e3b97>/LICENSE`, SHA-256 checked, saved as `Vendor/Upscayl/LICENSE-AGPL-3.0.txt`
- Download pattern: fetch to `.part`, verify checksum, then move into place. A failed checksum exits non-zero.
- Downloaded artefacts are gitignored (`.gitignore`: `Vendor/Upscayl/`).

**Swift Package Manager:**
- No remote packages. `Package.swift` has no `dependencies:` entries and no `Package.resolved` exists. Vendored C sources (libwebp, libjpeg) are committed in-tree.

## Apple System Services Used

**Image codecs (ImageIO / Core Graphics):**
- Decode: `Sources/HyperImageCore/IO/ImageLoader.swift`, `Sources/HyperImageCore/Batch/BatchConverter.swift`, `Sources/HyperImage/Convert/ConversionPreviewSheet.swift`. Input types listed in `Sources/HyperImageCore/Files/ImageFileTypes.swift`.
- Encode: `Sources/HyperImageCore/IO/ImageEncoder.swift` (`CGImageDestinationCreateWithData` for JPEG, PNG, GIF, BMP, TIFF, JPEG 2000, HEIC, AVIF; UTI from `OutputFormat.utType`, AVIF is `UTType("public.avif")`)
- Metadata copy: `Sources/HyperImageCore/IO/JPEGMetadataWriter.swift` (`CGImageDestinationCopyImageSource`), `Sources/HyperImageCore/IO/ImageMetadata.swift`
- Thumbnails: `Sources/HyperImageCore/IO/ImageLoader.swift` (`CGImageSourceCreateThumbnailAtIndex`), `Sources/HyperImage/Shared/Thumbnails.swift`

**Core Image:** `Sources/HyperImageCore/Imaging/ColorAdjuster.swift` (shared `CIContext`), `Sources/HyperImageCore/Imaging/HueRotation.swift`.

**Core Graphics PDF:** output in `Sources/HyperImageCore/IO/PDFEncoder.swift` (`CGContext(consumer:mediaBox:_:)`). Input preview of PDFs via `CGPDFDocument` in `Sources/HyperImage/Convert/ConversionPreviewSheet.swift`.

**Vendored codecs (in-process C, not network):**
- libwebp 1.6.0 encoder - `Sources/HyperImageCore/IO/WebPEncoder.swift`
- IJG libjpeg 9f - `Sources/HyperImageCore/IO/LibJPEG.swift`, `Sources/HyperImageCore/Pipeline/LosslessCrop.swift`

## Operating System Integrations

**Finder Services (`NSServices`):**
- Declared in `Resources/Info.plist`: menu item "Converter com HyperImage", `NSMessage` `addFilesService`, `NSPortName` `HyperImage Converter`, accepts `public.image` and `public.folder`
- Handler: `addFilesService(_:userData:error:)` in `Sources/HyperImage/App/HyperImageApp.swift`, registered with `NSApp.servicesProvider` and `NSUpdateDynamicServices()`
- Dev/install step: `build-app.sh --install` runs `lsregister -f` on `/Applications/HyperImage Converter.app`

**Document types and UTIs (`Resources/Info.plist`):**
- Viewer role for `public.image` and `public.folder`
- Editor role for exported type `com.hyperimage.options` (`.hyperoptions`, conforms to `public.json`)
- Imported type `com.faststone.photoresizer.options` (`.ccf`), handled by `Sources/HyperImageCore/Options/CCFImporter.swift`

**File panels:** `NSOpenPanel` / `NSSavePanel` wrappers in `Sources/HyperImage/Shared/FilePanels.swift` (`chooseFolder`, options save/load, reveal in Finder).

**Workspace (`NSWorkspace`):**
- `activateFileViewerSelecting` to reveal output in Finder: `Sources/HyperImage/Convert/ConversionRunner.swift`, `Sources/HyperImage/Shared/FilePanels.swift`
- `open(url)` to open in the default viewer: `Sources/HyperImage/Browser/BrowserView.swift`, `Sources/HyperImage/Convert/SettingsPanel.swift`
- `icon(forFile:)` for browser entry icons: `Sources/HyperImage/Browser/BrowserView.swift` (lines ~143 and ~177). `Sources/HyperImage/Shared/Thumbnails.swift` uses an SF Symbol rather than `icon(forFile:)` for file cards, to avoid disk hits on the main thread (per its comment).

**Clipboard:** `NSPasteboard.general` writes error lists as plain text: `Sources/HyperImage/Convert/CompletionFeedback.swift` (`ErrorListSheet`).

**Notifications:**
- `UNUserNotificationCenter.current()` in `Sources/HyperImage/Convert/CompletionFeedback.swift`
- Authorization requested lazily (`.alert`, `.sound`) the first time a batch finishes while the app is in the background
- Skipped when running outside an `.app` bundle (`Bundle.main.bundleURL.pathExtension == "app"` guard)
- Also bounces the Dock icon (`NSApp.requestUserAttention(.informationalRequest)`) and sets a Dock badge with percent (`DockProgress` in the same file)

**Appearance:** `NSApp.appearance` set from user choice (`system`, `light`, `dark`) in `Sources/HyperImage/App/HyperImageApp.swift`.

## Data Storage

**Databases:** None. No SQL, no ORM, no key-value server.

**Local persistence:**
- `UserDefaults.standard` - key `HyperImage.state.v1`, JSON-encoded `PersistedState` (`Sources/HyperImage/App/PersistedState.swift`). Holds convert settings, appearance, browser path, sort order, presets.
- `.hyperoptions` files - user-chosen JSON files holding `AdvancedOptions`. Saved atomically (`Sources/HyperImageCore/Models/AdvancedOptions.swift`, `options: .atomic`). Loaded tolerantly (`TolerantJSON.swift`) so older files still open.
- FastStone `.ccf` - read-only import through a Delphi stream parser (`Sources/HyperImageCore/Options/DelphiStream.swift`, `CCFImporter.swift`). The watermark image path is not stored in `.ccf` and must be re-selected (`README.md`).

**Output files:** written to the user's chosen destination via `Data.write(to:options: .atomic)` in `Sources/HyperImageCore/Batch/BatchConverter.swift`. Output folder is set in the UI or with `HYPERIMAGE_OUT` in debug builds.

**File storage services:** none (local filesystem only).

**Caching:**
- In-memory only: `ImageLoader` uses `kCGImageSourceShouldCache: false` for one-shot reads; `Sources/HyperImageCore/Files/FileSorting.swift` keeps a size cache (`InputSort.cachedSize`) in memory. No disk cache.
- Temporary directories only for upscale intermediates.

## Authentication & Identity

**Auth provider:** None. No user accounts, no login, no tokens.

**Code signing:** ad hoc (`codesign --force --options runtime --sign -` in `build-app.sh`). No Developer ID certificate, no notarisation step, no keychain access. No `SecItem` or Keychain use.

**Permissions required at runtime:** none beyond normal user file access through `NSOpenPanel` and the Finder Services handoff. `scripts/debug-shot.sh` and `scripts/window-id.swift` need Screen Recording only for dev screenshot tooling, not for the app.

## Monitoring & Observability

**Error tracking:** None. No Sentry, Crashlytics or similar SDK.

**Logs:** No logging framework. Failures are surfaced in the UI (`ErrorListSheet` in `Sources/HyperImage/Convert/CompletionFeedback.swift`) and copied as plain text on request. Upscale engine stderr is captured through a pipe and only the last lines are kept for the error message (`Upscaler.run`).

**Analytics:** None.

## CI/CD & Deployment

**Hosting:** Not applicable. The app is a local bundle built on the developer's Mac.

**CI pipeline:** None detected. There is no `.github/` directory, no `.gitlab-ci.yml`, no `Makefile`, no `fastlane/`.

**Deployment path:** `./build-app.sh` produces `build/HyperImage Converter.app`. `./build-app.sh --install` copies it to `/Applications/HyperImage Converter.app` and refreshes Launch Services.

**Test runners used by hand:** `swift test`, `scripts/ui-smoke.sh` (renders every sheet and window to PNG via `HYPERIMAGE_SNAPSHOT`, no UI scripting permission needed).

## Environment Configuration

**Required env vars for normal use:** none.

**Optional env vars:**
- `DEVELOPER_DIR` - Xcode path for `build-app.sh`, `scripts/sync-strings.sh`, `scripts/ui-smoke.sh`
- `HYPERIMAGE_UPSCAYL` - alternative folder for the upscale engine (tests and dev)
- `REF_OUTPUT_DIR`, `REF_SAVE_DIR` - FastStone reference comparison (`Tests/HyperImageCoreTests/ReferenceComparison.swift`)
- Debug-only `HYPERIMAGE_*` hooks in `Sources/HyperImage/App/DebugLaunch.swift` (compiled only under `#if DEBUG`)
- `WAIT`, `PICK`, `LANG_ARGS`, `EXPECT` - script knobs in `scripts/*.sh`

**Secrets location:** No secrets are used or stored. No `.env` file is present. Upscayl and libraries are public, checksum-pinned downloads.

**External spec reference (documentation only, not code):** `README.md` points to `../Clones/FSResizer-spec/SPEC.md` (a sibling folder outside this repo) for the FastStone behaviour spec.

## Webhooks & Callbacks

**Incoming:** None. The app does not listen on any port.

**Outgoing:** None.

**URL schemes:** None registered in `Resources/Info.plist`.

## Inter-Process Communication

- Upscayl child process: stdin unused, stdout and stderr merged through one `Pipe`, exit status checked (`Sources/HyperImageCore/Upscale/Upscaler.swift`)
- Finder Services over `NSPortName` `HyperImage Converter` (`Resources/Info.plist`)
- No XPC services, no helper tools, no Mach ports beyond the system defaults

---

*Integration audit: 2026-10-20*
