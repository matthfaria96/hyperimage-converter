---
phase: 01-seguranca-de-dados-e-entradas-hostis
plan: 01
subsystem: batch-output, upscale
tags: [data-safety, SAFE-01, SAFE-02, SAFE-03]
requires: []
provides: [in-place-protection, safe-overwrite-default, atomic-upscale-swap]
affects: [OutputPlanner, OverwritePanel, Upscaler]
key-files:
  created: [Tests/HyperImageCoreTests/DataSafetyTests.swift]
  modified:
    - Sources/HyperImageCore/Batch/ConvertSettings.swift
    - Sources/HyperImage/Convert/ConversionShared.swift
    - Sources/HyperImageCore/Upscale/Upscaler.swift
    - Tests/HyperImageCoreTests/EncoderTests.swift
decisions:
  - "Outputs never equal any input path; same-format in-place runs use the existing -N scheme (a-2.png)"
  - "Pular is the overwrite prompt default action; Sobrescrever requires a click"
  - "Upscale output swapped with FileManager.replaceItemAt"
metrics:
  completed: 2026-10-20
  tasks: 2
---

# Phase 1 Plan 01: Data Safety Summary

OutputPlanner now reserves every input (including the item's own file), so outputs never overwrite originals. Return in the overwrite prompt now means Pular. The final upscale swap uses `replaceItemAt`, so the old file is never deleted before the new one is in place.

## Commits
- 7e2f550 test: add failing tests for never writing outputs over inputs (RED)
- f55b272 fix: never plan an output over an input and make Pular the default overwrite answer (GREEN)
- e29a3f8 test: cover upscale temp cleanup and output replacement
- a5eb675 fix: replace existing upscale output atomically

## Tests
DataSafetyTests (5): in-place compress/convert, extension case, neighbouring `a-2.png` inputs, different format keeps the plain name.
UpscaleCleanupTests (4, serialized, uses a fake shell backend): missing backend, cancelled run, success replacing an existing output, failing backend keeping the old output. All 4 check that no `hyperimage-upscale-*` dir is left behind.
Full suite: 106 tests passed, plus 9 tests in the second test target.

## Deviations from Plan
1. **[Rule 1] Updated `OutputSafetyTests.outputNeverLandsOnAnotherInput`** (EncoderTests.swift). It expected `/f/x.jpg` to be written over the input `x.jpg`, which is the old unsafe behaviour. It now expects `x-3.jpg`. Commit f55b272.
2. **Task 2 had no RED stage.** The existing `defer` already cleaned up the temp dir, so the cleanup tests passed before the change. Without fault injection, the tests also cannot tell delete-then-move apart from `replaceItemAt`. They are kept as regression tests, and the swap change was checked by grep (no `removeItem(at: output)` remains).
3. The fixtures are JPEGs (there is no PNG fixture), so the success test copies `paisagem.jpg` through the fake backend.

## Known Stubs
None.

## Self-Check: PASSED
