---
phase: 02-recursos-e-ciclo-de-vida
plan: 02
subsystem: upscale, app-lifecycle
tags: [process, lifecycle, security, warnings, ROB-04, ROB-05, CORR-04]
requires: [02-01]
provides: [ProcessRegistry, Upscaler.registry]
affects: [Upscaler.run, Upscaler.bundled, AppDelegate.applicationWillTerminate, ConversionRunner.start]
key-files:
  created:
    - Sources/HyperImageCore/Upscale/ProcessRegistry.swift
    - Tests/HyperImageCoreTests/ProcessRegistryTests.swift
  modified:
    - Sources/HyperImageCore/Upscale/Upscaler.swift
    - Sources/HyperImageCore/Batch/BatchConverter.swift
    - Sources/HyperImage/App/HyperImageApp.swift
    - Sources/HyperImage/Convert/ConversionRunner.swift
decisions:
  - "Upscaler takes an injectable `registry: ProcessRegistry = .shared` so tests never touch the shared singleton"
  - "After registering, Upscaler unregisters immediately if the process already exited, so a fast exit cannot leave a stale entry"
  - "Release-build `Stale file ... outside of the allowed root paths` messages come from the build system (repo moved from /Users/... to /Volumes/...), not from source; not counted as code warnings"
metrics:
  completed: 2026-10-22
  tasks: 2
---

# Phase 2 Plan 02: Process lifecycle, debug-only override, zero warnings Summary

Quitting the app now SIGTERMs every running upscayl-bin through a lock-protected `ProcessRegistry` (waits up to 1 s) before state is saved; `HYPERIMAGE_UPSCAYL` is compiled in only for DEBUG; the Swift build has 0 warnings.

## Tasks

| Task | Commits |
|------|---------|
| 1. ProcessRegistry + Upscaler registration + quit hook (ROB-04) | 26e4ac9 (RED), 68a5d1e (GREEN) |
| 2. Debug-only env override (CORR-04) + zero warnings (ROB-05) | 28d0ab9 |

### ROB-04
- `ProcessRegistry` (`@unchecked Sendable`, all state behind `NSLock`): `register`, `unregister`, `count`, `terminateAll(timeout: = 1.0)`. It snapshots and clears the registry under the lock, terminates the running processes outside the lock, then polls `isRunning` every 20 ms until the deadline.
- `Upscaler.run` registers after `process.run()` and unregisters in `terminationHandler`. Cancellation behaviour is unchanged.
- `AppDelegate.applicationWillTerminate` calls `ProcessRegistry.shared.terminateAll()` before `model?.saveNow()`. The file now imports `HyperImageCore` explicitly.

### CORR-04
- The `HYPERIMAGE_UPSCAYL` block in `Upscaler.bundled()` is inside `#if DEBUG`. The doc comments in `bundled()` and `BatchConverter.upscaler` say so. `fm` is still used by the bundle lookup, so release has no unused-variable warning.

### ROB-05
- `ConversionRunner` progress hop: `Task { @MainActor in self.report(fraction, run: run) }`.
- I touched all Swift files in Sources/HyperImage and Sources/HyperImageCore, then ran `swift build`: 0 `warning:` lines. The release build (`swift build -c release`, run once) had 0 compiler warnings. Its 472 `Stale file` lines are build-system path noise from the old /Users location. I deleted the release artifacts afterwards (about 148 MB).

## Tests

- ProcessRegistryTests has 7 XCTest cases: 5 for the registry and 2 for the Upscaler integration, which use a fake hanging backend and a fake failing backend with an injected registry.
- Full `swift test`: XCTest 17/17, swift-testing 115 tests (22 suites) + 9 tests (4 suites). All pass.

## Deviations from Plan

**1. [Rule 2 - Testability] Injectable registry on Upscaler**
- The plan called `ProcessRegistry.shared` directly from `Upscaler.run`. I added a defaulted `registry:` init parameter so the Upscaler-to-registry wiring could be tested without shared state. Existing call sites are unchanged.

**2. [Rule 1 - Race] Stale-entry guard**
- If the process exits before `register` runs, `terminationHandler` unregisters first and the registration would then linger. Upscaler now unregisters right after registering when `!process.isRunning`.

**3. Path note**
- The plan's verify commands use `/Users/macmini/Documents/VSCode Temp/HyperImage Converter`. I ran them in the actual repo at `/Volumes/MacMiniDev/Moved/VSCode Temp/HyperImage Converter`.

## Known Stubs

None.

## Self-Check: PASSED
- Files exist: ProcessRegistry.swift, ProcessRegistryTests.swift
- Commits exist: 26e4ac9, 68a5d1e, 28d0ab9
