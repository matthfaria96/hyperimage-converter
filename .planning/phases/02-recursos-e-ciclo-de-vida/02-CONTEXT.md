# Phase 2: Recursos e ciclo de vida - Context

**Gathered:** 2026-10-20 (auto-generated, user requested fully autonomous execution)
**Status:** Ready for planning

<domain>
## Phase Boundary
Heavy batches and app termination behave predictably, and the build is warning-free.
Requirements: ROB-03, ROB-04, ROB-05, CORR-04. No UI changes expected.
</domain>

<decisions>
## Implementation Decisions (Claude's discretion)

### ROB-03 — memory budget for batch concurrency
- D-01: Concurrency derived from source pixel counts (read via ImageIO properties, no full decode): pure function `ConcurrencyBudget` in HyperImageCore, unit-tested.
- D-02: Policy: base = min(activeProcessorCount, 6); estimated working set ≈ pixels * 4 bytes * ~4 copies per worker; cap concurrency so the sum fits a budget of ~25% of physicalMemory (min 1). Any source > 40 MP forces 1 worker as a hard rule. Unknown dimensions count as "small".
- D-03: Implement inside BatchConverter (BatchConverter.swift:39–40); keep existing API, add injectable budget/memory for tests.

### ROB-04 — kill upscayl-bin on quit
- D-04: Thread-safe `ProcessRegistry` (Core, lock-protected) that Upscaler registers/unregisters running `Process` in; `terminateAll()` called from `applicationWillTerminate` (HyperImageApp.swift:72–74), before saving state. Optionally wait briefly (≤1 s) for exit.
- D-05: Unit test registry with a real short `/bin/sleep` process.

### ROB-05 — zero build warnings
- D-06: Fix ConversionRunner.swift:49 by strong capture of self (runner owned by MainView) per CONCERNS; then fix any other warnings `swift build` reports. Verify with a clean grep of build output for "warning:".

### CORR-04 — HYPERIMAGE_UPSCAYL only in DEBUG
- D-07: Wrap env override in Upscaler.bundled() (Upscaler.swift:85–90) with `#if DEBUG`. Tests run in debug so existing test hook keeps working.

### Claude's Discretion
- File layout, naming, exact thresholds within the policy above.
</decisions>

<canonical_refs>
- .planning/codebase/CONCERNS.md (sections "Concurrency and Lifecycle", "Security Considerations")
- .planning/REQUIREMENTS.md, .planning/ROADMAP.md Phase 2
</canonical_refs>

<constraints>
- Build/test: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build / swift test. Disk tight (~4 GB): no worktrees, no extra build dirs. Plans executed sequentially.
- New UI strings (if any) need pt+en entries in Resources/Localizable.xcstrings.
</constraints>

<deferred>
- Upscaler pipe drain on termination, cancel check around decode, main-thread record building: later phases/backlog.
</deferred>
