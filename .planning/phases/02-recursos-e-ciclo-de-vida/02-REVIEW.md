---
phase: 02-recursos-e-ciclo-de-vida
reviewed: 2026-10-23T02:26:37Z
depth: deep
diff_range: adfba37..HEAD -- Sources Tests (phase 02.1 commits and .planning excluded)
files_reviewed: 8
files_reviewed_list:
  - Sources/HyperImageCore/Batch/ConcurrencyBudget.swift
  - Sources/HyperImageCore/Batch/BatchConverter.swift
  - Sources/HyperImageCore/Upscale/ProcessRegistry.swift
  - Sources/HyperImageCore/Upscale/Upscaler.swift
  - Sources/HyperImage/App/HyperImageApp.swift
  - Sources/HyperImage/Convert/ConversionRunner.swift
  - Tests/HyperImageCoreTests/ConcurrencyBudgetTests.swift
  - Tests/HyperImageCoreTests/ProcessRegistryTests.swift
findings:
  critical: 0
  high: 1
  medium: 3
  low: 4
  info: 4
  total: 12
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-10-23T02:26:37Z
**Depth:** deep
**Files Reviewed:** 8
**Status:** issues_found

## Summary

I reviewed the phase 02 source and test changes: the memory-aware worker budget (02-01) and the upscayl-bin lifecycle registry (02-02). The 17 phase tests (`ProcessRegistryTests`, `ConcurrencyBudgetTests`) pass when run with the Xcode toolchain (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).

**Deadlock check (`terminateAll` on the main thread in `applicationWillTerminate`):** I found no deadlock.
- `terminateAll` takes the snapshot under the lock, then releases it before it sends signals or polls. The background `terminationHandler` (`registry.unregister`) therefore never waits on a lock that the main thread holds.
- `Process.isRunning` updates without the main run loop. The synchronous XCTest, which runs on the main thread, passes in about 20 ms.
- During shutdown, the batch task's `update` hop to the MainActor is held back by the blocked main thread. `group.next()` therefore cannot return, and no new upscale is queued before `exit()`.
- The main thread blocks for at most about 1 s, and only when a child is actually running.

**Main concerns:**
- The memory budget looks only at *source* pixels. It ignores resize and canvas enlargement, which can grow an output up to 400 MP, and it assumes 8-bit sources. This leaves the out-of-memory scenario that the phase was meant to remove.
- The registry is not a shutdown latch. A backend launched after the `terminateAll` snapshot is orphaned.
- Shutdown sends only SIGTERM. A child that survives the 1 s timeout, or any child left behind by a crash or force quit, outlives the app.

## High

### HI-01: Worker budget ignores output size (resize/canvas enlargement), so a batch can still run out of memory

**File:** `Sources/HyperImageCore/Batch/ConcurrencyBudget.swift:16-25`, `Sources/HyperImageCore/Batch/BatchConverter.swift:48-52`
**Issue:** `workerLimit` sizes workers from `pixelCount(of: record.input)` only. The convert pipeline (`ImagePipeline.swift:35-48`) can resize by percentage or side length and can expand the canvas up to `SafeLimits.maxPixels = 400_000_000` per image.

Example: a batch of 2 MP photos with "resize 1000%" produces 200 MP outputs. The budget sees 2 MP sources and keeps all 6 workers. The real cost is about 6 × 200 MP × 4 B × several copies, which is tens of GB, and macOS jetsam kills the app. This is the OOM case phase 2 was meant to prevent, and the hard limit (`hardLimitPixels`) never triggers because it is also applied to the sources.
**Fix:** Size the budget by the largest pixel count in the pipeline (source, after resize, after canvas):
```swift
// BatchConverter.workerLimit
let counts = records.map { r -> Int? in
    guard let src = ImageLoader.pixelSize(r.input) else { return nil }
    let out = pipeline.plannedOutputSize(for: src)   // ResizeGeometry.plan + CanvasGeometry.plan, no decode
    return max(src.width * src.height, out.width * out.height)
}
```
Add a test where small sources plus a large enlargement percentage produce fewer workers.

## Medium

### ME-01: A backend launched after the `terminateAll` snapshot is orphaned (the registry is not a shutdown latch)

**File:** `Sources/HyperImageCore/Upscale/ProcessRegistry.swift:31-45`, `Sources/HyperImageCore/Upscale/Upscaler.swift:196-201`, `Sources/HyperImage/App/HyperImageApp.swift:73-77`
**Issue:** `terminateAll` empties the dictionary and returns, but later `register` calls are accepted silently. Consider a quit that happens while `Upscaler.upscale` is still before `process.run()`. For example, it might be in the HEIC/TIFF/rotated-JPEG to PNG pre-conversion at `Upscaler.swift:121-127`, which can take seconds on large files. `terminateAll` then finds an empty registry and returns at once. The background task then calls `process.run()` before `exit()`, while `saveNow()` is running. The new upscayl-bin is reparented to launchd and keeps the GPU busy. That is exactly the bug 02-02 was meant to fix. The batch task is also never cancelled on quit, so nothing stops this launch.
**Fix:** Make the registry latch closed on shutdown, and terminate (or refuse) late registrations:
```swift
private var closed = false
public func register(_ p: Process) {
    lock.lock(); let isClosed = closed
    if !isClosed { processes[ObjectIdentifier(p)] = p }
    lock.unlock()
    if isClosed, p.isRunning { p.terminate() }
}
public func terminateAll(timeout: TimeInterval = 1.0) {
    let snapshot: [Process] = { lock.lock(); defer { lock.unlock() }; closed = true; ... }()
    ...
}
```
In `applicationWillTerminate`, also cancel the running batch first. The runner lives in `MainView` `@State`, so move it to `AppModel`, or post a notification that it observes.

### ME-02: SIGTERM only, with no SIGKILL escalation; timed-out children are dropped from tracking

**File:** `Sources/HyperImageCore/Upscale/ProcessRegistry.swift:40-44`
**Issue:** After the 1 s deadline, `terminateAll` returns even if children are still running. The registry was already cleared at line 35, so nothing tracks them any more and the app exits. A backend stuck in a GPU driver call, or one that handles or ignores SIGTERM, survives the quit. The test uses `/bin/sleep`, which exits on SIGTERM right away, so this path is never exercised.
**Fix:** After the deadline, send SIGKILL to anything that is still running:
```swift
for p in running where p.isRunning { kill(p.processIdentifier, SIGKILL) }
```
Optionally, launch each child in its own process group (`posix_spawnattr_setpgroup`) and signal the group.

### ME-03: `bytesPerPixel = 4` underestimates 16-bit and float sources by 2-4x

**File:** `Sources/HyperImageCore/Batch/ConcurrencyBudget.swift:7`
**Issue:** `ImageLoader.uprightImage` returns ImageIO's native decode. For 16-bit PNG/TIFF this is 8 B/px, and for RAW/HDR/EXR float it is up to 16 B/px. A batch of 30 MP 16-bit TIFFs on an 8 GB Mac is budgeted at about 4 workers, but needs about twice the memory the budget assumes.
**Fix:** Read `kCGImagePropertyDepth` (or `kCGImagePropertyIsFloat`) from the header in `pixelCount(of:)` and return a byte estimate instead of a pixel count. Alternatively, return `(pixels, bytesPerPixel)` and weight each entry by it.

## Low

### LO-01: Children outlive a crash or force quit

**File:** `Sources/HyperImage/App/HyperImageApp.swift:73-77`
**Issue:** `applicationWillTerminate` is not called on a crash, `kill -9`, or a Force Quit through Activity Monitor or the Dock. upscayl-bin then keeps running with launchd as its parent.
**Fix:** Have the child watch its parent. For example, run it through a tiny wrapper that uses a kqueue `NOTE_EXIT` on the parent PID, or poll `getppid() == 1` in a helper. Otherwise, document this as a known limitation in 02-02-SUMMARY.

### LO-02: Header pre-scan runs over every record before any work starts and ignores cancellation

**File:** `Sources/HyperImageCore/Batch/BatchConverter.swift:68`, `:48-52`
**Issue:** `workerLimit(for:)` opens a `CGImageSource` for every record before the first task starts. With thousands of files or a slow network or USB volume, the progress sheet sits at 0 with no feedback, and `cancel()` has no effect until the scan ends because there is no `Task.checkCancellation()`. The scan also covers records that the overwrite or skip-existing logic will skip, which can shrink the budget for no reason.
**Fix:** Call `try Task.checkCancellation()` every N files inside the scan, or compute the limit lazily (for example, re-evaluate it as records are dispatched). This is optional: you could also skip records whose output already exists when `skipExisting` is on.

### LO-03: Strong `self` capture reintroduced in the progress callback

**File:** `Sources/HyperImage/Convert/ConversionRunner.swift:49`
**Issue:** `[weak self]` was removed, apparently to silence a warning, so `ConversionRunner` → `task` → `converter.fileProgress` → `self` is now a retain cycle until the task finishes. Today this is harmless, because the runner is a `@State` that lives as long as the app. However, the change was not related to the phase goal, and it removes protection if the runner is ever scoped to a window.
**Fix:** Keep the weak capture in a way that compiles cleanly:
```swift
let converter = BatchConverter(settings: settings, fileProgress: { [weak self] _, fraction in
    Task { @MainActor in self?.report(fraction, run: run) }
})
```

### LO-04: Timing-based assertions can be flaky on loaded CI machines

**File:** `Tests/HyperImageCoreTests/ProcessRegistryTests.swift:29,49,93`
**Issue:** `XCTAssertLessThan(elapsed, 0.1)` and `< 1.5` are wall-clock bounds. On a busy runner, process spawn and SIGTERM delivery can exceed them. Also, `testWorkerLimitShrinksForLargeSourceUnderSmallMemory` and `testWorkerLimitKeepsCPUCapForSmallImages` (`ConcurrencyBudgetTests.swift:88-97`) pass trivially when `activeProcessorCount == 1`, because `maxConcurrency` is already 1.
**Fix:** Relax the bounds (for example `< timeout + 2`) and assert behaviour (`!isRunning`) instead of latency. Guard the wiring tests with `try XCTSkipIf(converter.maxConcurrency < 2)`.

## Info

### IN-01: Duplicate header reader

**File:** `Sources/HyperImageCore/Batch/ConcurrencyBudget.swift:28-37`
**Issue:** This duplicates `ImageLoader.pixelSize(_:)` (`ImageLoader.swift:73-79`), with slightly different handling (`NSNumber` versus `Int` casts, and an overflow guard).
**Fix:** Reuse `ImageLoader.pixelSize` and multiply with an overflow guard in one place.

### IN-02: Unknown sizes count as zero

**File:** `Sources/HyperImageCore/Batch/ConcurrencyBudget.swift:15-21`
**Issue:** A source that ImageIO can decode but whose header lacks `PixelWidth`/`PixelHeight` is treated as "small" and keeps the full CPU cap. This is documented, but it fails open.
**Fix:** Consider treating `nil` as `hardLimitPixels / 4` instead of 0.

### IN-03: `applicationWillTerminate` blocks the main thread for up to 1 s

**File:** `Sources/HyperImage/App/HyperImageApp.swift:75`
**Issue:** This is acceptable and is not a deadlock (see the summary). A cleaner approach is `applicationShouldTerminate` returning `.terminateLater`, which waits off the main thread and then calls `reply(toApplicationShouldTerminate:)`.

### IN-04: The `HYPERIMAGE_UPSCAYL` debug override does not validate its path

**File:** `Sources/HyperImageCore/Upscale/Upscaler.swift:95-100`
**Issue:** Release builds correctly ignore the environment variable (`build-app.sh` uses `-c release`, and SwiftPM defines `DEBUG` only in debug builds). In debug builds, any path is accepted without an `isExecutableFile` check. `run()` checks later, so the only effect is the error message (`backendMissing` instead of falling back to the bundled copy). There is no security impact.

---

_Reviewed: 2026-10-23T02:26:37Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
