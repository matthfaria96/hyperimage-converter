---
phase: 01-seguranca-de-dados-e-entradas-hostis
plan: 02
subsystem: options-import / imaging
tags: [robustness, hostile-input, limits]
requires: []
provides: [SafeLimits, Int(safe:), Bitmap.checkedByteCount, AdvancedOptions dimension limits]
affects: [CCFImporter, DelphiStream, AdvancedOptions.validationError, Bitmap.init(image:)]
key-files:
  created: [Sources/HyperImageCore/Models/SafeLimits.swift, Tests/HyperImageCoreTests/HostileOptionsTests.swift]
  modified: [Sources/HyperImageCore/Options/DelphiStream.swift, Sources/HyperImageCore/Options/CCFImporter.swift, Sources/HyperImageCore/Models/AdvancedOptions.swift, Sources/HyperImageCore/Imaging/Bitmap.swift, Resources/Localizable.xcstrings]
decisions:
  - "SafeLimits lives in HyperImageCore/Models: 30 000 px per side and 400 MP total"
  - "Bitmap.checkedByteCount caps only the total area (plus overflow), not each side, so wide panoramas within 400 MP still decode"
  - "Bitmap.init(width:height:fill:) stays non-throwing. It has no direct callers, and its inputs are bounded by validationError"
  - "Border sizes (frame widths, inner frame, shadow) are clamped to ±maxSide on import and rejected above maxSide in validation"
metrics:
  completed: 2026-10-20
  tasks: 2
---

# Phase 1 Plan 02: Hostile option files and dimension limits Summary

Options files with bad values no longer crash the app. `DelphiValue.int` now ignores NaN, Inf and doubles of 2^53 or more instead of trapping. `CCFImporter` caps every imported pixel dimension at 30 000. `validationError()` rejects sizes above 30 000 px per side or 400 MP, with pt and en messages. `Bitmap` computes its buffer size with `multipliedReportingOverflow` and throws `cannotAllocate` instead of trapping.

## Commits
- 97f76b6 test: cover hostile Delphi values and huge option dimensions (RED)
- adba564 fix: never trap on NaN/Inf/huge Delphi values and clamp imported CCF dimensions (GREEN)
- 9003aa3 test: cover dimension limits in validation and Bitmap byte count (RED)
- e818547 fix: reject dimensions above 30 000 px or 400 MP and check Bitmap byte count (GREEN)

## Verification
- `swift test --filter "HostileOptionsTests|CCFImportTests"`: 9 tests passed.
- `swift build`: clean.
- Full `swift test`: 112 Swift Testing tests ran; 111 passed and 1 failed, plus 9 XCTest-style tests that all passed. The one failure, `UpscaleCleanupTests.failingBackendKeepsExistingOutput` from plan 01-01, passes on its own and is logged in deferred-items.md.
- Loading a `.hyperoptions` file with `"width": 1e300` does not trap. TolerantJSON falls back to the default width.

## Deviations from Plan
- **Strings catalog:** I did not run `scripts/sync-strings.sh`, because it runs `swift package clean` and a full rebuild, which is risky with only ~1.4 GB of free disk. I added the 4 new pt keys and their en translations to the catalog by hand, in the same JSON format. Xcode may move the entries when it re-sorts the catalog.
- **Border limits added (Rule 2):** border, inner-frame and shadow sizes are clamped on import and checked in validation. These values feed pixel sizes too.
- `Int(safe:)` is used only in `DelphiValue.int`. PersistedState and the .hyperoptions path decode through JSONDecoder, which throws rather than traps on out-of-range numbers.

## TDD Gate Compliance
A RED test commit came before each GREEN fix commit for both tasks.

## Self-Check: PASSED
