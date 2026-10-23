---
phase: 02-recursos-e-ciclo-de-vida
fixed_at: 2026-10-23T02:45:00Z
review_path: .planning/phases/02-recursos-e-ciclo-de-vida/02-REVIEW.md
iteration: 1
findings_in_scope: 12
fixed: 6
skipped: 6
status: partial
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-10-23T02:45:00Z
**Source review:** .planning/phases/02-recursos-e-ciclo-de-vida/02-REVIEW.md
**Iteration:** 1

**Scope:** The requested scope was HI-01, ME-01, ME-02 and ME-03, plus LO-02 and LO-03 if they were cheap and safe. Info items were to be fixed only if trivial. All 12 findings are listed below.

**Summary:**
- Findings in scope: 12
- Fixed: 6 (HI-01, ME-01, ME-02, ME-03, LO-02, LO-03)
- Skipped: 6 (LO-01, LO-04, IN-01 to IN-04)

**Verification:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` reports 0 warnings, and so does `swift build --build-tests`. `swift test` passes all tests: 30 XCTest (17 before), 115 Swift Testing tests in the core target and 9 in the app target. There are 0 failures.

## Fixed Issues

### HI-01: Worker budget ignores output size (resize/canvas enlargement)

**Files modified:** `Sources/HyperImageCore/Batch/ConcurrencyBudget.swift`, `Sources/HyperImageCore/Batch/BatchConverter.swift`, `Tests/HyperImageCoreTests/ConcurrencyBudgetTests.swift`
**Commit:** 78077f7
**Applied fix:**
- New `ConcurrencyBudget.plannedPeakPixels(source:sourceDPI:options:)` returns the largest image the pipeline will hold. It applies `ResizeGeometry.plan`, then `CanvasGeometry.plan`, then `BorderEffect.layout` to the upright header size. Crop is ignored because it only shrinks.
- `workerLimit` now uses `settings.effectiveAdvancedOptions`, so `hardLimitPixels` also applies to planned outputs.
- Tests cover these cases:
  - with no size steps, the peak equals the source size
  - enlargement through resize
  - shrinking keeps the source size
  - canvas after resize
  - wiring: small sources with a 1000% resize drop to 1 worker.

**Status:** fixed: requires human verification. This is budget logic, so check that it is conservative enough.

### ME-03: `bytesPerPixel = 4` underestimates 16-bit and float sources

**Files modified:** `Sources/HyperImageCore/Batch/ConcurrencyBudget.swift`, `Sources/HyperImageCore/Batch/BatchConverter.swift`, `Tests/HyperImageCoreTests/ConcurrencyBudgetTests.swift`
**Commit:** 0e858d2
**Applied fix:**
- The header read now includes `kCGImagePropertyDepth` and `kCGImagePropertyIsFloat`. The result is 4 × bytes-per-channel, clamped to 4…16.
- New `ConcurrencyBudget.Footprint` (pixels and bytes per pixel) and `workers(footprints:)`. `workers(pixelCounts:)` is kept as an 8-bit wrapper.
- Tests cover the depth-to-bytes mapping, a 16-bit footprint shrinking the worker count, and a 16-bit PNG header read as 8 B/px.

### ME-01: Backend launched after the `terminateAll` snapshot is orphaned

**Files modified:** `Sources/HyperImageCore/Upscale/ProcessRegistry.swift`, `Sources/HyperImageCore/Upscale/Upscaler.swift`, `Tests/HyperImageCoreTests/ProcessRegistryTests.swift`
**Commit:** a1ca74b
**Applied fix:**
- `terminateAll` now latches the registry closed.
- `register` returns `Bool`. After shutdown it kills the late process with SIGKILL instead of tracking it.
- `Upscaler.run` checks `isAcceptingLaunches` before `process.run()` and throws `CancellationError`. The register-after-run path covers the remaining gap between that check and the launch.
- Tests check two things: a late registration is refused and killed, and an `Upscaler` with a closed registry never starts the backend (checked with a marker file).
- Not done: the review's optional extra step of cancelling the running batch in `applicationWillTerminate`. That needs the runner moved out of `MainView` `@State`. The latch alone already prevents the orphan.

### ME-02: SIGTERM only, no SIGKILL escalation

**Files modified:** `Sources/HyperImageCore/Upscale/ProcessRegistry.swift`, `Tests/HyperImageCoreTests/ProcessRegistryTests.swift`
**Commit:** 85f9038
**Applied fix:**
- After the SIGTERM timeout, `terminateAll` sends SIGKILL to every child still running. It then waits up to 0.5 s (`killGrace`) for them to be reaped.
- The new test uses a child that runs `trap '' TERM; exec sleep`. It asserts that the child is gone and ended with `terminationReason == .uncaughtSignal` and status `SIGKILL`.
- The test `tearDown` now uses SIGKILL, so the stubborn child cannot leak.

### LO-02: Header pre-scan ignores cancellation and covers records that will be skipped

**Files modified:** `Sources/HyperImageCore/Batch/BatchConverter.swift`, `Tests/HyperImageCoreTests/ConcurrencyBudgetTests.swift`
**Commit:** 9727910
**Applied fix:**
- `workerLimit(for:)` now `throws` and calls `Task.checkCancellation()` every 16 headers.
- With `skipExisting` on, it leaves out records whose output already exists.
- Tests check that a cancelled task throws `CancellationError`, and that a big file whose output exists no longer shrinks the budget.
- Not done: progress feedback during the scan.

### LO-03: Strong `self` capture in the progress callback

**Files modified:** `Sources/HyperImage/Convert/ConversionRunner.swift`
**Commit:** 4a10df8
**Applied fix:**
- Restored `[weak self]` on the `fileProgress` closure, with `self?.report(...)` inside the MainActor task. The app builds with 0 warnings.
- No test was added. The retain cycle cannot be observed, because the running batch `Task` holds the runner strongly until it finishes anyway.

## Skipped Issues

### LO-01: Children outlive a crash or force quit

**File:** `Sources/HyperImage/App/HyperImageApp.swift:73-77`
**Reason:** This was not in the requested scope, and it is not cheap. It needs a parent-watching wrapper process (a kqueue `NOTE_EXIT` on the parent, or a `getppid()` poll). Recommended next step: record it as a known limitation in 02-02-SUMMARY.
**Original issue:** `applicationWillTerminate` is not called on a crash, `kill -9` or Force Quit, so upscayl-bin is reparented to launchd and keeps running.

### LO-04: Timing-based assertions can be flaky on loaded CI machines

**File:** `Tests/HyperImageCoreTests/ProcessRegistryTests.swift:29,49,93`
**Reason:** This was not in the requested scope, and it only hardens tests. The new wiring tests added here already guard with `XCTSkipIf(maxConcurrency < 2)`. The existing latency bounds were left as they are.
**Original issue:** The wall-clock bounds (`< 0.1`, `< 1.5`) can fail on a busy runner, and two wiring tests pass trivially when only one CPU is active.

### IN-01: Duplicate header reader

**File:** `Sources/HyperImageCore/Batch/ConcurrencyBudget.swift`
**Reason:** This is Info and not trivial. The budget's header reader now also returns DPI and bit depth, which `ImageLoader.pixelSize` does not. Merging the two would mean changing the `ImageLoader` API.
**Original issue:** `pixelCount(of:)` duplicates `ImageLoader.pixelSize(_:)`.

### IN-02: Unknown sizes count as zero

**File:** `Sources/HyperImageCore/Batch/ConcurrencyBudget.swift`
**Reason:** This is Info and a policy change (failing closed instead of open). It changes the existing `testUnknownAndEmptyCountsKeepBase` contract, so it is left for a deliberate decision.
**Original issue:** A header without a pixel size is treated as small and keeps the full CPU cap.

### IN-03: `applicationWillTerminate` blocks the main thread for up to 1 s

**File:** `Sources/HyperImage/App/HyperImageApp.swift:75`
**Reason:** This is Info, and the review notes it is acceptable and not a deadlock. With ME-02, the worst case is now about 1.5 s, which is still acceptable. Moving to `.terminateLater` is a larger change to the app lifecycle.
**Original issue:** A cleaner approach would be `applicationShouldTerminate` returning `.terminateLater`.

### IN-04: `HYPERIMAGE_UPSCAYL` debug override does not validate its path

**File:** `Sources/HyperImageCore/Upscale/Upscaler.swift:95-100`
**Reason:** This is Info, applies to debug builds only, and has no security impact. `run()` already reports `backendMissing`.
**Original issue:** In debug builds the override accepts any path, without an `isExecutableFile` check.

---

_Fixed: 2026-10-23T02:45:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
