# Deferred items (phase 01)

- [from 01-02] `UpscaleCleanupTests.failingBackendKeepsExistingOutput` (DataSafetyTests.swift:130, plan 01-01) failed once in the full parallel `swift test` run (`leftovers()` saw a temp entry), but passes with `--filter UpscaleCleanupTests`. It is probably affected by other suites' temp files when tests run in parallel. Out of scope for 01-02.
