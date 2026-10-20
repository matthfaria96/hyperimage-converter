---
phase: 01-seguranca-de-dados-e-entradas-hostis
fixed_at: 2026-10-20T00:00:00Z
review_path: .planning/phases/01-seguranca-de-dados-e-entradas-hostis/01-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 1: Code Review Fix Report

**Summary:** 5 findings in scope, 5 fixed, 0 skipped. Full `swift test`: 115 tests in 22 suites plus 9 tests in 4 suites, all passed.

## Fixed Issues

### CR-01: `abs(Int.min)` traps in the border validation
**Commit:** f82b855. **Files:** `AdvancedOptions.swift`, `HostileOptionsTests.swift`.
The check now uses a range comparison (`> maxSide || < -maxSide`) instead of `abs`. The new regression test `borderValidationSurvivesIntMin` covers this.

### WR-01: Percentage and expand sizes are not validated
**Commit:** 9367e9c. **Files:** `AdvancedOptions.swift`, `HostileOptionsTests.swift`.
**Status:** fixed, requires human verification of the logic.
- Resize percentage and canvas percentage are capped at `maxSide * 100`.
- Resize print size is converted to pixels and capped at `maxSide`.
- Canvas expand is capped at `maxSide` px, or at `maxSide * 100` when the unit is %.
- NaN and infinity are rejected.
- `oneSide <= 0` was already rejected by `validationError`.
- Crop print size is not capped, because a crop cannot be larger than the source.

The messages reuse existing strings, so no new localisation entries were needed. The new test is `validationRejectsOversizedRelativeSizes`.

### WR-02: Cross-volume swap
**Commit:** 17dd6d8. **Files:** `Upscaler.swift`, `DataSafetyTests.swift`.
`tempRoot` is now `URL?`:
- `nil` (the default) uses `.itemReplacementDirectory` appropriate for the nearest existing ancestor of the output. If that fails, it falls back to the system temp directory.
- An injected `tempRoot` keeps the old behaviour.

The new test is `defaultWorkFolderSwapsOnOutputVolume`.

### WR-03: Cancellation check after `createDirectory`
**Commit:** c1d8e48. **File:** `Upscaler.swift`. `Task.checkCancellation()` now runs before the output folder is created.

### IN-01: The `Int(safe:)` comment
**Commit:** 177c03b. **File:** `SafeLimits.swift`. The doc comment now says callers must clamp the result.

---
_Fixer: Claude (gsd-code-fixer), iteration 1_
