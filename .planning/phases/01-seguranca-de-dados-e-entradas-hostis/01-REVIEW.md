---
phase: 01-seguranca-de-dados-e-entradas-hostis
reviewed: 2026-10-20T00:00:00Z
depth: standard
files_reviewed: 12
files_reviewed_list:
  - Resources/Localizable.xcstrings
  - Sources/HyperImage/Convert/ConversionShared.swift
  - Sources/HyperImageCore/Batch/ConvertSettings.swift
  - Sources/HyperImageCore/Imaging/Bitmap.swift
  - Sources/HyperImageCore/Models/AdvancedOptions.swift
  - Sources/HyperImageCore/Models/SafeLimits.swift
  - Sources/HyperImageCore/Options/CCFImporter.swift
  - Sources/HyperImageCore/Options/DelphiStream.swift
  - Sources/HyperImageCore/Upscale/Upscaler.swift
  - Tests/HyperImageCoreTests/DataSafetyTests.swift
  - Tests/HyperImageCoreTests/EncoderTests.swift
  - Tests/HyperImageCoreTests/HostileOptionsTests.swift
findings:
  critical: 1
  warning: 3
  info: 1
  total: 5
status: issues_found
---

# Phase 1: Code Review Report

**Depth:** standard | **Files Reviewed:** 12 | **Status:** issues_found

## Summary

The overflow-checked allocation, the default "Pular" button, and the output planner reserving every input path are correct. A crash path remains in the new validation code, and some size inputs are still unchecked.

## Critical Issues

### CR-01: `abs(Int.min)` traps in the border validation

**File:** `Sources/HyperImageCore/Models/AdvancedOptions.swift:73-75`
**Issue:** `sizes.contains(where: { abs($0) > SafeLimits.maxSide })` crashes when any value is `Int.min`. CCF import clamps these fields, but a hostile JSON options file loaded through `AdvancedOptions.load` / `TolerantJSON` does not. That means the validator added to block hostile input can itself crash the app (ROB-01).
**Fix:** `sizes.contains(where: { $0 > SafeLimits.maxSide || $0 < -SafeLimits.maxSide })`, plus a test that uses `Int.min`.

## Warnings

### WR-01: Percentage and expand sizes are not validated
**File:** `Sources/HyperImageCore/Models/AdvancedOptions.swift:58-72`
**Issue:** `limitError` checks only the `.pixels` and `.oneSide` modes. Resize percentage, print size×DPI, canvas percentage/expand and crop print size can be any size. The `Bitmap.checkedByteCount` backstop catches them only at allocation, so the user sees a generic per-file failure instead of a validation message. Intermediate CGContext/CIImage paths that do not go through `Bitmap` are not covered at all. `oneSide` also accepts sizes of 0 or below.
**Fix:** Work out the target size for each mode, or set upper bounds (for example percentage ≤ maxSide*100/1 px), and reject `sideLength <= 0`.

### WR-02: `replaceItemAt` / `moveItem` across volumes is not atomic or fails
**File:** `Sources/HyperImageCore/Upscale/Upscaler.swift:136-142`
**Issue:** `partial` is in `tempRoot`, which defaults to the system temp directory, while `output` is often on another volume (external drive). `moveItem` then falls back to copy+delete, which is not atomic. `replaceItemAt` can fail across volumes or leave a partial file, so the "previous output is never deleted" guarantee (SAFE-0x) does not hold.
**Fix:** By default, create the work folder on the output's volume: `FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: output, create: true)`.

### WR-03: Cancellation after the external process finishes is too late to stop the swap
**File:** `Sources/HyperImageCore/Upscale/Upscaler.swift:136`
**Issue:** `Task.checkCancellation()` runs after `createDirectory` for the output folder. A cancel that arrives during the replace is still ignored, and the output folder is created even when the task was cancelled. This is minor, but it contradicts the intent.
**Fix:** Check cancellation before `createDirectory`.

## Info

### IN-01: The `Int(safe:)` guard is looser than its comment says
**File:** `Sources/HyperImageCore/Models/SafeLimits.swift:16-18`
**Issue:** The guard checks `abs(value) < 2^53` before rounding. This is safe, but callers still get values up to about 9e15. That is fine because the CCF callers clamp afterwards. The comment "too large to convert safely" could still lead someone to treat the result as a valid dimension.
**Fix:** Document that callers must still clamp.

---
_Reviewer: Claude (gsd-code-reviewer) | Depth: standard_
