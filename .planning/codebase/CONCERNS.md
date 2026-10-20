# Codebase Concerns

**Analysis Date:** 2026-10-20

Scope: `Sources/HyperImage` (SwiftUI app), `Sources/HyperImageCore` (engine), `Tests/`, `build-app.sh`, `scripts/`. Vendored code under `Sources/CWebP/libwebp`, `Sources/CJPEG/libjpeg` and `Vendor/` was not audited line by line. Findings come from reading the code; nothing below was reproduced by running the app, so each item states its confidence where it matters.

## Priority Summary

| # | Severity | Area | Short description |
|---|----------|------|-------------------|
| 1 | High | Crash | Crafted `.ccf` / `.hyperoptions` can trap the app (NaN/Inf to `Int`) |
| 2 | High | Data loss | In-place overwrite of source files is possible and the overwrite prompt defaults to "Sobrescrever" |
| 3 | Medium | Correctness | "Limit file size" is silently not enforced for lossless formats and lossless JPEG crop |
| 4 | Medium | Memory | Up to 6 full-resolution decodes run at once with no memory budget |
| 5 | Medium | Stale UI | Results (badges, sizes, Finder links) survive changes to format/mode/quality |
| 6 | Medium | Lifecycle | Quitting during an AI Upscale does not stop `upscayl-bin` |
| 7 | Medium | UX | Undo can wipe files added after a removal, and works during a batch |
| 8 | Medium | Correctness | Compress mode silently converts some formats to JPEG |
| 9 | Low | Build warning | `ConversionRunner.swift:49` weak-self warning (known) |
| 10 | Low | Silent failures | Animated GIF/TIFF flattened to one frame; settings reset on decode error; missing browser folder shows nothing |
| 11 | Low | Security | `HYPERIMAGE_UPSCAYL` env var redirects the backend in release builds |
| 12 | Low | Tests | Parser, overwrite-in-place, undo-after-add and size-limit edge cases untested |

---

## Crashes and Input Robustness

**Delphi value conversion traps on non-finite or out-of-range doubles:**
- Issue: `DelphiValue.int` converts a `.double` with `Int(v.rounded())`. `Int(Double)` traps at runtime when the value is NaN, infinite, or outside `Int`'s range. The `.double` case is produced by the 80-bit extended (tag 5) and 32-bit float (tag 15) decoders in `Sources/HyperImageCore/Options/DelphiStream.swift` (`Reader.extended`, `case 15`), and the 80-bit decoder can return infinity for exponent `0x7FFF`.
- Files: `Sources/HyperImageCore/Options/DelphiStream.swift:16`, reached from `Sources/HyperImageCore/Options/CCFImporter.swift` through `Fields.int` (lines 20, 39–48, 71, 73–76, 81, 91–92, 101, 107, 154–155, 173–174, 188–189, 194–195).
- Impact: Opening a crafted or corrupted `.ccf` from the file panel (`Sources/HyperImage/Shared/FilePanels.swift:44–51`) crashes the whole app instead of showing `DelphiStreamError`.
- Fix approach: In `DelphiValue.int`, return nil unless `v.isFinite` and `abs(v) < 2^53`. Add a test in `Tests/HyperImageCoreTests/CCFImportTests.swift` that feeds a TPF0 stream with a NaN/Inf extended value for an integer property.

**Oversized dimensions from option files are not bounded:**
- Issue: `CCFImporter` accepts any positive `Int` for resize, canvas, crop and border sizes. `AdvancedOptions.validationError()` (`Sources/HyperImageCore/Models/AdvancedOptions.swift:24–53`) only checks `> 0`, never an upper bound. `Bitmap` allocates `width * height * 4` bytes without an overflow or size check (`Sources/HyperImageCore/Imaging/Bitmap.swift:24`, `:33`).
- Files: `Sources/HyperImageCore/Options/CCFImporter.swift:39–40`, `:91–92`; `Sources/HyperImageCore/Models/AdvancedOptions.swift:24–53`; `Sources/HyperImageCore/Imaging/Bitmap.swift:24`, `:33`.
- Impact: A crafted option file, or a hand-edited `.hyperoptions`, can request a canvas of billions of pixels and exhaust memory or trap on overflow.
- Fix approach: Add a maximum (for example 30 000 px per side and a total pixel cap) to `validationError()` and clamp at import. Use `multipliedReportingOverflow` in `Bitmap` and throw `ImagingError.cannotAllocate` before allocating.

**Bitmap uses `precondition` for internal invariants:**
- Files: `Sources/HyperImageCore/Imaging/Bitmap.swift:14`.
- Impact: Low. Only reachable from internal callers, but any future caller bug crashes instead of throwing.
- Fix approach: Throw `ImagingError.cannotAllocate` instead, or keep it and document it as an internal invariant.

**Misleading error for crop failure:**
- Files: `Sources/HyperImageCore/Imaging/Transforms.swift:40` throws `cannotAllocate` when `CGImage.cropping(to:)` returns nil. The user sees "Memória insuficiente…" for what is really an out-of-bounds rectangle.
- Fix approach: Add an `ImagingError.cropOutOfBounds` case.

**Tiny percentages silently produce 1-pixel images:**
- Files: `Sources/HyperImageCore/Geometry/Geometry.swift:34` (`roundedPixels` clamps to 1), `Sources/HyperImageCore/Geometry/ResizeGeometry.swift:45`.
- Issue: `validationError()` rejects percentages `<= 0` but not values such as `0.001`. The result is silently a 1×1 image.
- Fix approach: Reject resized sizes that round below 1 px in `validationError()` or report them in `convert`.

## Data Safety

**In-place overwrite of the source file is possible:**
- Issue: `OutputPlanner.destinations` lets an output path equal the input's own path (`candidate.standardizedFileURL.path.lowercased() != own`). With no output folder, no suffix, and the same format (for example Compress mode on a PNG, or Convert to JPEG on a JPEG), the output is the input file. `BatchConverter.convert` then writes over it with `.atomic`.
- Files: `Sources/HyperImageCore/Batch/ConvertSettings.swift:82–90`; `Sources/HyperImageCore/Batch/BatchConverter.swift:92–93`.
- Impact: The original file is replaced by the re-encoded version. With "Perguntar antes de sobrescrever" off, this happens silently. With it on, the prompt appears, but see the next item.
- Fix approach: When `candidate == own` and the output is the input, either force a suffix or refuse with a clear message. Do not allow an in-place write unless the user checked an explicit option.

**Overwrite prompt defaults to destructive action:**
- Issue: In `OverwritePanel`, the "Sobrescrever" button carries `.keyboardShortcut(.defaultAction)`, so Return overwrites. "Cancelar Conversão" is bound to Esc.
- Files: `Sources/HyperImage/Convert/ConversionShared.swift:43–49`.
- Fix approach: Make "Pular" the default action, or require an explicit click for overwrite.

**Stale temp output on upscale replace:**
- Issue: `Upscaler.upscale` deletes an existing output before `moveItem`. If the move fails, the previous file is already gone.
- Files: `Sources/HyperImageCore/Upscale/Upscaler.swift:131–133`.
- Fix approach: Use `FileManager.replaceItemAt(_:withItemAt:)`, which swaps atomically where supported.

**Privacy: metadata carried into outputs by default paths:**
- Issue: `carriedMetadata` copies the EXIF, IPTC, GPS and TIFF dictionaries whenever `keepMetadata` is on. The text overlay can also print the folder path (`$C3`, `TextVariables.swift`).
- Files: `Sources/HyperImageCore/IO/ImageEncoder.swift:153–168`; `Sources/HyperImageCore/Naming/TextVariables.swift:92`.
- Impact: GPS coordinates survive into shared outputs when the user keeps metadata. This is intended behaviour, but it is not surfaced in the UI.
- Fix approach: Show a note near the "keep metadata" toggle when GPS is present in the source.

## Correctness

**Size limit silently not enforced:**
- Issue: `OutputEncoder.encode` returns the first attempt without checking the limit in three cases:
  1. Formats without a quality knob (PNG, TIFF, BMP, GIF, PDF, lossless WebP) return `nil` from `quality(for:)`, so the search never runs (`OutputRecipe.swift:34–43`, `:105–106`).
  2. Lossless JPEG crop returns `EncodedOutput.image == nil`, so the `guard ... let image = first.image` exits early (`LosslessCrop.swift:18`, `OutputRecipe.swift:106`).
  3. When even quality 5 is above the limit, the over-limit data is returned as success (`OutputRecipe.swift:117`).
- Impact: A user who sets "Limitar tamanho" to 500 KB gets larger files with no warning. The summary's estimate and the notification still report success.
- Fix approach: Return a flag (`limitMet: Bool`) in `EncodedOutput`, and surface a per-file warning (the `ConversionStatus` could carry a note) when the limit is not met.

**Lossless JPEG crop uses DPI 0 when the source has none:**
- Issue: `losslessCrop` passes `source.metadata.dpiX ?? 0` to libjpeg, while the regular path uses 72 (`ImagePipeline.process`, `ImagePipeline.swift:64–65`).
- Files: `Sources/HyperImageCore/Pipeline/LosslessCrop.swift:33`.
- Fix approach: Use the same fallback (72) or confirm that the shim treats 0 as "no density" (`Sources/CJPEG/shim/hij.c`). This was not verified.

**Lossless crop re-reads the whole file:**
- Issue: After `ImageLoader.load` has already read and decoded the file, `LosslessCrop.losslessCrop` reads it again with `Data(contentsOf:)`. A file changed between the two reads produces an output that does not match the loaded metadata.
- Files: `Sources/HyperImageCore/Pipeline/LosslessCrop.swift:32`.
- Fix approach: Read the bytes once in `ImageLoader.load` and pass them through `LoadedImage`.

**Compress mode silently converts some formats to JPEG:**
- Issue: `OutputFormat.matching(_:)` covers the writable formats only. For TGA, PSD, ICO/CUR, EXR, and camera RAW, `ConvertSettings.outputFormat(for:)` falls back to `.jpeg`. The UI text says "Cada imagem mantém o próprio formato".
- Files: `Sources/HyperImageCore/Batch/OutputRecipe.swift:9–21`, `:64`; `Sources/HyperImage/Convert/SettingsPanel.swift:173–175` (the text).
- Fix approach: Either document the fallback in the subtitle, or pick a lossless format (PNG) for sources that have alpha and JPEG otherwise, and say so.

**WebP size limit gives a generic error:**
- Issue: libwebp rejects images larger than 16 383 px per side. `WebPEncoder` maps every failure to `encodeFailed("WebP")` ("Falha ao gravar no formato WebP").
- Files: `Sources/HyperImageCore/IO/WebPEncoder.swift:24–25`, `:37`.
- Fix approach: Check the dimensions up front and report "WebP aceita no máximo 16 383 px por lado".

**PDF page size may exceed PDF limits:**
- Issue: With "usar DPI original", a low-DPI image of many pixels becomes a page wider than the PDF maximum (14 400 pt). Viewers clip or reject the page.
- Files: `Sources/HyperImageCore/IO/PDFEncoder.swift:9–10`.
- Fix approach: Clamp the page box and warn, or fall back to 72 dpi above the limit.

**Animated GIF and multi-page TIFF become a single frame:**
- Issue: `ImageLoader.load` always decodes index 0. Animations are output as the first frame with no warning.
- Files: `Sources/HyperImageCore/IO/ImageLoader.swift:39–45`; `Sources/HyperImageCore/IO/ImageEncoder.swift:70–71` (GIF output path).
- Fix approach: Document this in the format help, or warn when the source frame count is greater than 1.

**Preview and conversion can disagree on animated/multi-frame sources:**
- Files: `Sources/HyperImage/Convert/ConversionPreviewSheet.swift:110`, `:127–128`.
- Impact: Low, follows from the item above.

## Concurrency and Lifecycle

**Known build warning (ConversionRunner.swift:49):**
- Issue: The `fileProgress` closure passed to `BatchConverter` creates `Task { @MainActor [weak self] in self?.report(fraction, run: run) }`. The compiler reports the `[weak self]` capture as differing from the implicit strong capture used elsewhere in the same class. The known warning is at this line.
- Files: `Sources/HyperImage/Convert/ConversionRunner.swift:48–50`.
- Fix approach (not compiled or verified): Drop `[weak self]` and capture `self` strongly. The runner is owned by `MainView` for the window's lifetime and the closure is short-lived, so a strong capture is safe. Alternatively, route progress through an `AsyncStream` consumed inside `start`.

**Concurrency is capped at six, but each worker holds a full-resolution decode:**
- Issue: `BatchConverter` runs up to `min(activeProcessorCount, 6)` conversions. Each `convert` call decodes the full source (`ImageLoader.load`), builds a 4-byte-per-pixel `Bitmap` (`Bitmap.init(image:)`), possibly a resized copy, a `CGImage`, a flattened copy, and the encoder's output. A 50 MP photo needs roughly 200 MB per copy, so several copies per worker multiply quickly. The size-limit search also re-encodes up to seven times, reusing the processed image.
- Files: `Sources/HyperImageCore/Batch/BatchConverter.swift:39–40`, `:87–101`; `Sources/HyperImageCore/Imaging/Bitmap.swift:31–43`; `Sources/HyperImageCore/Batch/OutputRecipe.swift:112–122`.
- Impact: Batches of large RAW or 50 MP files can exhaust memory, which shows up as slowdown or termination.
- Fix approach: Derive the concurrency from the largest pending source pixel count (for example, one worker when any source exceeds 40 MP), or use a memory-based semaphore.

**Quitting during AI Upscale leaves the engine running:**
- Issue: `applicationWillTerminate` only saves state (`Sources/HyperImage/App/HyperImageApp.swift:72–74`). The `upscayl-bin` child process is cancelled only through task cancellation, which does not run on quit. `Process` children are not terminated automatically when the parent exits.
- Files: `Sources/HyperImage/App/HyperImageApp.swift:72–74`; `Sources/HyperImageCore/Upscale/Upscaler.swift:136–174`.
- Impact: Confidence medium. The orphaned engine keeps writing to the temp directory until it finishes, and the output is never moved.
- Fix approach: Track the running process in a shared registry and call `terminate()` on every running child from `applicationWillTerminate`.

**Upscale input is decoded on the batch's cancellation path:**
- Issue: `Upscaler.upscale` converts non-JPEG/PNG/WebP inputs through `ImageLoader.load` before the `checkCancellation` that follows it. A cancel during a long HEIC/RAW decode is noticed only after the decode finishes.
- Files: `Sources/HyperImageCore/Upscale/Upscaler.swift:106–119`.
- Fix approach: Check cancellation immediately before and after the decode, and avoid the decode entirely by launching with the original file when the backend can read it.

**Main-thread file I/O when building the batch:**
- Issue: `ConversionRunner.start` calls `BatchConverter.records(for:)` on the main actor. That reads the size of every queued file (`resourceValues`) and runs `OutputPlanner.destinations`, so Start blocks the UI on large lists.
- Files: `Sources/HyperImage/Convert/ConversionRunner.swift:53`; `Sources/HyperImageCore/Batch/BatchConverter.swift:43–48`.
- Fix approach: Compute records in a detached task, or reuse the sizes already cached in `SortKeyCache` / `AppModel.totalBytes`.

**Sort key cache is never invalidated or pruned:**
- Issue: `SortKeyCache` keeps a size and date per URL for the whole session. Files replaced on disk keep their old values, and the dictionary only grows.
- Files: `Sources/HyperImageCore/Files/FileSorting.swift:54–68`.
- Fix approach: Key the cache by URL plus modification date, or clear it when the list is emptied.

**Undo and removal:**
- Issue: `WorkspaceView.removeWithUndo` registers an undo that restores the full pre-removal list (`app.restore(before)`). Files added after the removal are dropped when Undo runs. The guard only stops registration during a batch, so Cmd+Z still changes the list while `runner.isRunning` is true.
- Files: `Sources/HyperImage/Input/WorkspaceView.swift:199–209`; `Sources/HyperImage/App/AppModel.swift:124–127`.
- Fix approach: Undo should re-insert only the removed items (for example, by URL), and undo should be disabled while `isRunning`.

**Stale results after settings changes:**
- Issue: `ConversionRunner.clearResults()` runs only when the input list changes (`SummaryBox.swift:93`). Changing the format, mode, quality, suffix or output folder keeps the previous batch's OK badges, sizes, totals and "Mostrar no Finder" targets. Those targets point at files written under the old settings.
- Files: `Sources/HyperImage/Convert/SummaryBox.swift:93`; `Sources/HyperImage/Convert/ConversionRunner.swift:147–155`.
- Fix approach: Store a settings snapshot with the results and clear (or mark as outdated) when the current `ConvertSettings` differs from it.

**Overwrite prompt can sit behind a sheet:**
- Issue: The overwrite question is an `.overlay` on `MainView`, but route sheets are presented over it. If a sheet is open when a batch starts, the batch waits for an answer the user cannot see. The start paths (Cmd+Return menu, Start button) do not check `app.route`.
- Files: `Sources/HyperImage/App/MainView.swift:53–56`, `:89–101`.
- Fix approach: Refuse to start while `app.route != nil`, or present the overwrite question as a sheet with a higher priority.

**Batch completion can replace an open sheet:**
- Issue: `batchFinished()` assigns `app.route = .errors` even if another sheet is open.
- Files: `Sources/HyperImage/App/MainView.swift:109–111`.
- Fix approach: Only set the route when `app.route == nil`, or queue it.

## Error Handling and Silent Failures

**Upscale backend missing is reported per file:**
- Issue: `MainView.startConversion` does not check `Upscaler.bundled()` before starting AI Upscale. Each file then fails with "O motor de IA (Upscayl) não foi encontrado" and the error sheet lists every file.
- Files: `Sources/HyperImage/App/MainView.swift:89–101`; `Sources/HyperImageCore/Batch/BatchConverter.swift:105`.
- Fix approach: Check the backend up front and show one alert.

**Persisted settings reset silently on decode error:**
- Issue: `PersistedState.decode` returns defaults on any failure. The next save overwrites the stored data, so a single bad value wipes every setting without notice.
- Files: `Sources/HyperImage/App/PersistedState.swift:31–33`.
- Fix approach: Keep the raw data under a backup key before overwriting, or log the failure.

**Missing browser folder shows an empty list with no message:**
- Issue: `BrowserModel.list` swallows the `contentsOfDirectory` error (`try?`). A saved folder on an unmounted drive is indistinguishable from an empty folder.
- Files: `Sources/HyperImage/Browser/BrowserModel.swift:72`; `Sources/HyperImage/Browser/BrowserView.swift` (no error state).
- Fix approach: Return the error and show "Pasta não encontrada" with a button to go to the home folder.

**Process output is truncated on termination:**
- Issue: `Upscaler.run` clears `readabilityHandler` right after the termination continuation resumes, so trailing progress lines can be lost, and the failure tail may be incomplete.
- Files: `Sources/HyperImageCore/Upscale/Upscaler.swift:145–173`.
- Fix approach: Drain the pipe with `readDataToEndOfFile()` after termination before reading the log.

## Security Considerations

**Backend override by environment variable in release builds:**
- Risk: `Upscaler.bundled()` honours `HYPERIMAGE_UPSCAYL` in every build, not only DEBUG. Any process that can set the app's environment can point the backend at an arbitrary executable, which the app then runs with the user's privileges.
- Files: `Sources/HyperImageCore/Upscale/Upscaler.swift:85–90`.
- Current mitigation: The variable is documented as a test hook; the release app is ad-hoc signed.
- Recommendations: Wrap the override in `#if DEBUG` or check that the executable's team/hash matches the bundled one.

**Ad-hoc signing and no notarization:**
- Risk: `build-app.sh` signs with `--sign -` (`build-app.sh:50–54`). Distributed builds will be quarantined by Gatekeeper and carry no integrity guarantee beyond the code hash.
- Current mitigation: Model and binary SHA-256 checks in `scripts/fetch-upscayl.sh` (`BIN_SHA`, `MODEL_SHA`), which run when the binary is missing.
- Recommendations: Sign with a Developer ID and notarise for distribution. The fetch script's check should also run when `Vendor/Upscayl/upscayl-bin` already exists (currently `build-app.sh:45` only checks it is executable).

**Shim error handling relies on `longjmp`:**
- Risk: `Sources/CJPEG/shim/hij.c` replaces libjpeg's `exit()` with `longjmp` to avoid terminating the app. Locals modified between `setjmp` and `longjmp` are indeterminate after the jump. The `row` and `dp` pointers are `volatile` for this reason; any new local added to these functions must follow the same rule.
- Files: `Sources/CJPEG/shim/hij.c:120–136`, `:196–212`.
- Recommendations: Add a comment at each `setjmp` listing the variables that must stay volatile.

## Performance Bottlenecks

**RAW and large-file thumbnails decode the full image:**
- Problem: Browser and list thumbnails pass `kCGImageSourceCreateThumbnailFromImageAlways: true`, which forces ImageIO to decode the full raw image rather than use the embedded preview.
- Files: `Sources/HyperImageCore/IO/ImageLoader.swift:61–69`; `Sources/HyperImage/Shared/Thumbnails.swift:15–28`.
- Cause: The flag is set so orientation is applied to the thumbnail; it also disables the embedded-preview fast path.
- Improvement path: Try the embedded thumbnail first (`kCGImageSourceCreateThumbnailFromImageIfAbsent`) and fall back to always-from-image only when the result is too small.

**Size-limit search re-encodes repeatedly:**
- Problem: `OutputEncoder.encode` runs up to about seven full encodes per file (binary search on quality), and `Estimate.make` runs three sample conversions for the summary.
- Files: `Sources/HyperImageCore/Batch/OutputRecipe.swift:112–122`; `Sources/HyperImage/Convert/SummaryBox.swift:196–213`.
- Improvement path: Estimate from a downscaled sample for the search, then encode once at full size.

**WebP copies the full image twice:**
- Problem: `WebPEncoder.straightRGBA` copies the whole `Bitmap` again to un-premultiply alpha, after `Bitmap(image:)` already made one copy.
- Files: `Sources/HyperImageCore/IO/WebPEncoder.swift:43–51`.
- Improvement path: Un-premultiply in place on the first buffer.

**Upscale log buffer:**
- Problem: `LogBuffer.appendLines` calls `String.count` on every chunk, which is O(n) on the stored text.
- Files: `Sources/HyperImageCore/Upscale/Upscaler.swift:199–203`.
- Improvement path: Track the byte count, or trim by `utf8.count`.

## Fragile Areas

**Lossless JPEG crop depends on several flags agreeing:**
- Files: `Sources/HyperImageCore/Pipeline/LosslessCrop.swift:38–47`; `Sources/HyperImageCore/Pipeline/ImagePipeline.swift:41–46`.
- Why fragile: The decision is made in two places (`losslessCropRect` and `ImagePipeline.process`'s `untouched` block) with the same intent but different inputs. The pipeline's `untouched` check only looks at pixel size and the resize/rotate/adjust flags. Steps such as text, watermark and border do not change size, so they are safe to ignore there, but any new step that resizes must be added to both checks.
- Safe modification: Change both together, and add a test for every step that disables the lossless path (`Tests/HyperImageCoreTests/JPEGTests.swift` has `otherStepsDisableLosslessCrop`; extend it).
- Test coverage: Good for the JPEG shim, weak for the decision logic.

**Format-specific names and suffixes:**
- Files: `Sources/HyperImageCore/Batch/OutputRecipe.swift:69–74`; `Sources/HyperImageCore/Batch/ConvertSettings.swift:82`.
- Why fragile: The suffix is localised in one branch (`-comprimido`, `-convertido`) and hard-coded in another (`-upscale-\(scale)x`). Changing either breaks the collision logic, which only checks names inside one batch.
- Safe modification: Route all suffixes through one localised helper.

**Overlay and sheet routing:**
- Files: `Sources/HyperImage/App/MainView.swift:53–56`, `:65–76`; `Sources/HyperImage/Input/WorkspaceView.swift:102`, `:107`, `:122`, `:142`, `:220`.
- Why fragile: `SheetRoute` is a single optional, and many places assign it directly. Two assignments in the same frame keep only the last one.
- Safe modification: Route all assignments through one `present(_:)` method that checks for an existing route.

## Scaling Limits

**Input list size:**
- Current capacity: The list is a `LazyVStack` of `FileCard`s. Each card starts a `.task` that reads its pixel size and file size (`Sources/HyperImage/Input/FileCard.swift:79–82`).
- Limit: Scrolling a list of thousands of files starts thousands of detached header reads.
- Scaling path: Cancel the task when the card leaves the view (already implicit with `.task(id:)`), and batch the reads.

**Output folder size on re-run:**
- Current capacity: `OutputPlanner` checks collisions only among the current batch. Existing files on disk are discovered one by one at write time (`BatchConverter.run`, `FileManager.fileExists` per record).
- Limit: Re-running a large batch into the same folder triggers one prompt per existing file unless "yes to all" is chosen.
- Scaling path: Scan the output folder once before starting and present a single summary question.

## Dependencies at Risk

**Upscayl engine (AGPL-3.0):**
- Risk: The bundled `upscayl-bin` is a third-party binary fetched from a pinned GitHub release (`scripts/fetch-upscayl.sh`). Updates require re-verifying the SHA-256 values and the license text.
- Impact: Shipping the app binds the distribution to AGPL obligations for the engine (the README already states the separation).
- Migration plan: Keep the process boundary; pin versions in one place.

**libwebp 1.6.0 and libjpeg 9f (vendored):**
- Risk: Both are old-style vendored trees under `Sources/CWebP/libwebp` and `Sources/CJPEG/libjpeg`. Security fixes must be applied by hand.
- Impact: Decoder code paths are not used by the app (only encoders and the JPEG transform), reducing exposure. `CWebP` still builds decoder sources.
- Migration plan: Consider excluding unused decoder sources from the target, or record the upstream version and the list of patched files next to the vendored tree.

## Missing Critical Features

**No progress or cancel for a single long file outside AI Upscale:**
- Problem: Only the upscale path reports per-file progress (`BatchConverter.upscale`). A 200 MP conversion shows no progress and cannot be cancelled until the file finishes.
- Blocks: Reliable cancel for very large files in Convert and Compress mode.

**No record of settings used for a batch:**
- Problem: Results are not tied to the settings that produced them (see Stale results above), so the user cannot tell which batch an output came from.
- Blocks: Re-running or auditing a batch.

## Test Coverage Gaps

**Parser robustness:**
- What's not tested: `DelphiStream` with non-finite values, truncated strings, and bad lengths. Only `truncated` on a two-byte stream is covered (`Tests/HyperImageCoreTests/CCFImportTests.swift:73`).
- Files: `Sources/HyperImageCore/Options/DelphiStream.swift`, `Sources/HyperImageCore/Options/CCFImporter.swift`.
- Risk: The crash in item 1 under Crashes and Input Robustness goes unnoticed.
- Priority: High.

**Overwrite and in-place output:**
- What's not tested: `OutputPlanner` when the output equals the input, and what happens when `askBeforeOverwrite` is off.
- Files: `Sources/HyperImageCore/Batch/ConvertSettings.swift:67–93`; `Tests/HyperImageAppTests/AppFlowTests.swift` covers the prompt only.
- Risk: Silent loss of originals.
- Priority: High.

**Size limit edge cases:**
- What's not tested: Limit unreachable at quality 5, lossless formats with a limit, lossless JPEG crop with a limit. `fileSizeTargetIsMet` (in the Core tests) covers only the reachable case.
- Files: `Sources/HyperImageCore/Batch/OutputRecipe.swift:99–124`.
- Priority: Medium.

**Undo and list mutation:**
- What's not tested: Undo after adding files, and undo during a run. `undoRestoresRemovedFiles` (in `Tests/HyperImageAppTests/AppFlowTests.swift`) covers only the simple case.
- Files: `Sources/HyperImage/Input/WorkspaceView.swift:199–209`.
- Priority: Medium.

**Upscale cancellation and cleanup:**
- What's not tested: Cancelling a running `upscayl-bin` and the temp-directory cleanup. `Tests/HyperImageCoreTests/UpscaleTests.swift` covers a missing backend, percentage parsing and a full upscale, but the real-backend test is skipped without `Vendor/Upscayl`.
- Files: `Sources/HyperImageCore/Upscale/Upscaler.swift:99–174`.
- Priority: Medium.

**UI flows:**
- What's not tested: Sheet routing conflicts, error sheet after a batch, and the Finder service entry point. These are exercised only by `scripts/ui-smoke.sh`, which is manual.
- Priority: Low.

**Format edge cases:**
- What's not tested: WebP above 16 383 px, PDF pages above 14 400 pt, animated GIF/TIFF frame count, and TGA/PSD/ICO in Compress mode.
- Files: `Sources/HyperImageCore/IO/WebPEncoder.swift`, `Sources/HyperImageCore/IO/PDFEncoder.swift`, `Sources/HyperImageCore/IO/ImageLoader.swift`, `Sources/HyperImageCore/Batch/OutputRecipe.swift`.
- Priority: Low.

---

*Concerns audit: 2026-10-20*
