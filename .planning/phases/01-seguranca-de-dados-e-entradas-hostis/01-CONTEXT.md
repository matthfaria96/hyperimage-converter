# Phase 1: Segurança de dados e entradas hostis - Context

**Gathered:** 2026-10-20 (auto-generated, skip_discuss=true — Claude's discretion)
**Status:** Ready for planning

<domain>
## Phase Boundary
Originais nunca sobrescritos por engano; arquivos de opções malformados não derrubam o app.
Requirements: SAFE-01, SAFE-02, SAFE-03, ROB-01, ROB-02. Source: .planning/codebase/CONCERNS.md (Crashes and Input Robustness; Data Safety).
</domain>

<decisions>
## Implementation Decisions
- **D-01 (SAFE-01):** In `OutputPlanner.destinations` (Sources/HyperImageCore/Batch/ConvertSettings.swift), when the planned output equals the input path (case-insensitive, standardized), never write in place: pick the next free unique name (same scheme as existing collision handling, e.g. append " (1)") instead. No new UI option for in-place writes. Covered by unit tests.
- **D-02 (SAFE-02):** In `OverwritePanel` (Sources/HyperImage/Convert/ConversionShared.swift), "Pular" becomes `.defaultAction`; "Sobrescrever" requires an explicit click; Esc stays on cancel.
- **D-03 (SAFE-03):** `Upscaler` temp files/dirs are removed via `defer` on success, error and cancellation; replacing an existing output uses `FileManager.replaceItemAt` instead of delete-then-move. Test cleanup paths that do not need the real backend.
- **D-04 (ROB-01):** `DelphiValue.int` returns nil unless the double is finite and |v| < 2^53. Same guard for any other Double→Int conversion in options decoding (.hyperoptions / PersistedState paths). Malformed files surface an error (existing DelphiStreamError / decode error alert), never trap.
- **D-05 (ROB-02):** Safe limits: max 30 000 px per side and 400 MP total. `AdvancedOptions.validationError()` rejects values above the limit with a clear localized message (pt + en in Resources/Localizable.xcstrings). `CCFImporter` clamps on import. `Bitmap` uses `multipliedReportingOverflow` and throws `ImagingError.cannotAllocate` before allocating.

### Claude's Discretion
Exact naming, constant placement (single `SafeLimits` enum in HyperImageCore), test file layout.
</decisions>

<constraints>
- Build/test: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` / `swift test` (~2-3 min).
- New UI strings need pt + en entries (scripts/sync-strings.sh).
- Commits: `<type>: <description>` + `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No push.
</constraints>

<deferred>
- Crop out-of-bounds message, tiny percentage 1px, size-limit enforcement → Phase 3.
- Overwrite prompt behind sheets → Phase 4.
</deferred>
