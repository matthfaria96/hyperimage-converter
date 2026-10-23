---
phase: 02-recursos-e-ciclo-de-vida
plan: 01
subsystem: batch
tags: [concurrency, memory, ROB-03]
requires: []
provides: [ConcurrencyBudget, BatchConverter.workerLimit]
affects: [BatchConverter.run]
key-files:
  created:
    - Sources/HyperImageCore/Batch/ConcurrencyBudget.swift
    - Tests/HyperImageCoreTests/ConcurrencyBudgetTests.swift
  modified:
    - Sources/HyperImageCore/Batch/BatchConverter.swift
decisions:
  - "Worker budget sized by the largest source (any worker may hold it); unknown headers count as small"
  - "workerLimit tested with a 3 MP PNG and 64 MiB injected memory instead of a 50 MP image (disk/RAM)"
metrics:
  completed: 2026-10-22
  tasks: 2
---

# Phase 2 Plan 01: Memory-aware batch concurrency Summary

Batch workers are now capped by a pure `ConcurrencyBudget` policy that reads each source's pixel count from the ImageIO header (no decode): any source above 40 MP forces one worker, otherwise workers = clamp(25% of physical memory / (largest pixels x 4 B x 4 copies), 1, CPU cap).

## Tasks

| Task | Commits |
|------|---------|
| 1. ConcurrencyBudget policy + header reader | 65355b2 (RED), fd3d0a1 (GREEN) |
| 2. Wire into BatchConverter.run | 02295bb (RED), b27e479 (GREEN) |

- `BatchConverter.init` gained `physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory` as a trailing defaulted parameter; existing call sites unchanged.
- `workerLimit(for:)` (internal) returns 1 without reading headers when `maxConcurrency <= 1` (upscale or parallel=false).
- `run()` computes the limit once before the task group.

## Tests

ConcurrencyBudgetTests: 10 XCTest cases. Full `swift test`: XCTest 10/10, swift-testing 115 tests (22 suites) + 9 tests (4 suites), all passing.

## Deviations from Plan

- Task 2 test used the plan's fallback option: small PNG (2000x1500) + injected 64 MiB memory, rather than an 8000x6400 PNG, per disk/RAM constraints.
- `pixelCount(of:)` additionally guards width*height overflow (returns Int.max, which forces 1 worker) - Rule 2 hardening for hostile headers.

## Self-Check: PASSED
