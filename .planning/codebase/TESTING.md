# Testing Patterns

**Analysis Date:** 2026-10-20

## Test Framework

**Runner:**
- Swift Testing (the `Testing` module), not XCTest. No file under `Tests/` imports `XCTest`.
- Toolchain: Swift 6.2 (`swift-tools-version: 6.2` in `Package.swift`), Xcode at `/Applications/Xcode.app/Contents/Developer`.
- Config: `Package.swift` declares two test targets (`HyperImageAppTests`, `HyperImageCoreTests`); there is no separate test config file.

**Assertion Library:**
- Swift Testing macros only: `#expect(...)`, `#expect(throws: ImagingError.self) { ... }`, `#require(...)`, `Issue.record(...)`.

**Run Commands:**
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test                       # Run all tests (core + app, takes minutes)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PipelineTests  # One suite
REF_OUTPUT_DIR=<FSResizer-spec/ref-output> swift test --filter ReferenceComparison        # Opt-in comparison with reference renders
sh scripts/ui-smoke.sh [output-dir]                                                       # UI smoke test (debug build, PNG snapshots)
LANG_ARGS="-AppleLanguages (en)" sh scripts/ui-smoke.sh                                   # UI smoke test in English
```

Expected baseline: 97 core tests and 9 app tests pass (per project notes). Do not run the full suite just to check a small change; run the matching `--filter` first.

**Watch mode:** Not configured. No coverage tooling is configured in the repo (no `.xctestplan`, no coverage script).

## Test File Organization

**Location:**
- Separate directory tree from sources: `Tests/HyperImageCoreTests/` for `HyperImageCore`, `Tests/HyperImageAppTests/` for the `HyperImage` executable's models and flows.
- Co-location with sources is not used.

**Naming:**
- Files: `<Area>Tests.swift` (`PipelineTests.swift`, `GeometryTests.swift`, `EncoderTests.swift`, `CCFImportTests.swift`, `JPEGTests.swift`, `UpscaleTests.swift`, `GIFSpeedTests.swift`, `SimpleModeTests.swift`, `TextVariableTests.swift`).
- Non-suite support files: `Tests/HyperImageCoreTests/ReferenceComparison.swift` (opt-in comparison harness, a `struct` named `ReferenceComparison`).
- Suites: `struct <Area>Tests` (`struct PipelineTests`, `struct UpscaleTests`). App flows: `struct InputListFlowTests`, `struct ConversionFlowTests` (`Tests/HyperImageAppTests/AppFlowTests.swift`).
- Test functions: descriptive camelCase verbs or statements with no `test` prefix: `fixturesLoad`, `everyFilterProducesTargetSize`, `rotationIsClockwise`, `twoColorDepthIsPureBlackAndWhite`, `missingWatermarkIsReported`, `existingOutputsAskBeforeOverwriting`.

**Structure:**
```
Tests/
├── HyperImageCoreTests/
│   ├── Fixtures/                 # paisagem.jpg (1200x800), retrato.jpg (600x900), exemplo-opcoes.ccf
│   ├── PipelineTests.swift       # Fixtures enum + end-to-end ImagePipeline checks
│   ├── PipelineSweepTests.swift
│   ├── GeometryTests.swift
│   ├── EncoderTests.swift
│   ├── FormatSweepTests.swift
│   ├── JPEGTests.swift
│   ├── UnusualInputTests.swift   # 16-bit, gray, CMYK, alpha inputs
│   ├── RegressionTests.swift
│   ├── SimpleModeTests.swift
│   ├── CCFImportTests.swift
│   ├── GIFSpeedTests.swift
│   ├── TextVariableTests.swift   # also defines TemporaryDirectory
│   ├── UpscaleTests.swift        # skipped unless Vendor/Upscayl is present
│   └── ReferenceComparison.swift # opt-in
├── HyperImageAppTests/
│   ├── Fixtures/                 # retrato.jpg, paisagem.jpg (copies)
│   └── AppFlowTests.swift        # Workspace class + InputListFlowTests + ConversionFlowTests
```

**Resources:**
- Both test targets declare `resources: [.copy("Fixtures")]` in `Package.swift`; load them through `Bundle.module`, never through a hard-coded path. `UpscaleTests` is the one exception and derives the `Vendor/Upscayl` path from `#filePath`.

## Test Structure

**Suite organization:**
```swift
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import HyperImageCore

/// Runs the real pipeline on the reference inputs and checks the reference output sizes (SPEC §8).
struct PipelineTests {
    func run(_ configure: (inout AdvancedOptions) -> Void, on loaded: LoadedImage) throws -> ProcessedImage {
        var options = AdvancedOptions()
        configure(&options)
        return try ImagePipeline(options: options).process(loaded)
    }

    @Test func fixturesLoad() throws {
        #expect(try Fixtures.landscape().image.pixelSize == PixelSize(width: 1200, height: 800))
    }

    @Test(arguments: ResizeFilter.allCases)
    func everyFilterProducesTargetSize(filter: ResizeFilter) throws {
        let out = try run({ $0.resize.enabled = true; $0.resize.filter = filter }, on: Fixtures.landscape())
        #expect(out.image.pixelSize == PixelSize(width: 800, height: 533))
    }
}
```

**Patterns:**
- **Setup:** A `run(_:on:)` helper in the suite takes an `inout` configuration closure, builds `AdvancedOptions()`, and returns the processed result. Use it for every pipeline test instead of constructing `ImagePipeline` by hand.
- **Teardown:** Temporary state is cleaned up in `deinit`: `TemporaryDirectory` (`Tests/HyperImageCoreTests/TextVariableTests.swift`) and `Workspace` (`Tests/HyperImageAppTests/AppFlowTests.swift`) both call `try? FileManager.default.removeItem(at:)` in `deinit`. Use a class (not struct) for any helper that owns a directory, so `deinit` runs when the test ends.
- **Assertions:** Plain `#expect` for values; `#require` (or `try #require(...)`) for optionals the rest of the test depends on: `let url = try #require(Bundle.module.url(...))`.
- **Parameterised tests:** `@Test(arguments: ResizeFilter.allCases)` to cover every enum case; pair tuples for expected outcomes: `@Test(arguments: [(OverwriteDecision.yesToAll, ConversionStatus.done), (.noToAll, .skipped)])`.
- **Conditional tests:** `@Test(.enabled(if: UpscaleTests.available))` skips the test when the Upscayl binary is absent. Use this for any test that needs an external artifact that may not be downloaded.
- **Serialisation:** App-flow suites use `@Suite(.serialized)` because they share `AppModel`/`ConversionRunner` state and the filesystem (`Tests/HyperImageAppTests/AppFlowTests.swift`).
- **Opt-in tests:** Tests that require a local reference directory return early when the env var is unset (`guard let refDir = ProcessInfo.processInfo.environment["REF_OUTPUT_DIR"] else { return }` in `ReferenceComparison.swift`). They pass by default and only run their work when the env var is set.

## Mocking

**Framework:** None. No mocking library is used (no Mockable, no Cuckoo, no protocol-based stubs).

**Patterns:**
- Dependencies are injected as values or closures, not mocks:
  - `BatchConverter(settings:upscaler:fileProgress:)` takes an optional `upscaler` (pass `nil` to disable AI upscale) and a `fileProgress` closure to observe progress (`Sources/HyperImageCore/Batch/BatchConverter.swift`).
  - `Upscaler(executable:modelsFolder:)` takes explicit paths, so tests point it at `Vendor/Upscayl` (`Tests/HyperImageCoreTests/UpscaleTests.swift`).
  - `ImagePipeline(options:)` takes a plain `AdvancedOptions` struct: build it, mutate it, pass it in.
- Test-only collectors use an `actor` to gather results from concurrent callbacks: `actor Collector { var items: [ConversionRecord] = []; func add(_:) }` (`Tests/HyperImageCoreTests/UnusualInputTests.swift`).
- Test inputs are generated in code rather than mocked: `CGContext` draws are converted to `CGImage` and written with `CGImageDestinationCreateWithURL` to produce TIFF, PNG, gray JPEG, and CMYK JPEG inputs (`UnusualInputTests.make(_:bitsPerComponent:info:)`, `UpscaleTests` TIFF setup).

**What to Mock:**
- Nothing is mocked today. When a new test needs a dependency, prefer a closure or an optional parameter on the production type (the pattern used by `BatchConverter.fileProgress` and `upscaler`).
- Filesystem: use real temporary directories (`TemporaryDirectory()` or `Workspace()`), never mocked file managers.

**What NOT to Mock:**
- Image decoding, encoding, and resampling: the tests verify real output sizes and pixel values against the fixtures.
- `ImageIO`, `CoreGraphics`, and the vendored `CWebP`/`CJPEG` encoders: test through the Swift wrappers in `Sources/HyperImageCore/IO/`.

## Fixtures and Factories

**Test Data:**
Shared helpers for loaded images and pixel reads (`Tests/HyperImageCoreTests/PipelineTests.swift`):
```swift
enum Fixtures {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Fixtures")!
    }
    static func landscape() throws -> LoadedImage { try ImageLoader.load(url("paisagem")) }
    static func portrait() throws -> LoadedImage { try ImageLoader.load(url("retrato")) }
    static func rgba(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] { ... }
}
```
- Reference sizes are hard-coded in assertions: landscape resized to 800 wide yields 800×533; a 150% upscale of the portrait yields 900×1350; border grows the landscape by 41 px in each dimension (1241×841). When a pipeline change legitimately alters sizes, update these numbers together with the spec reference in the suite's doc comment.

**Location:**
- Core fixtures: `Tests/HyperImageCoreTests/Fixtures/` (`paisagem.jpg`, `retrato.jpg`, `exemplo-opcoes.ccf`).
- App fixtures: `Tests/HyperImageAppTests/Fixtures/` (`paisagem.jpg`, `retrato.jpg`). The two copies are separate; keep them identical if you change one.
- Generated inputs (TIFF, PNG, CMYK) are created per test inside a temporary directory, not stored.

**Pixel helpers:**
- `Fixtures.rgba(_:x:y:)` and `Bitmap(image:colorSpace:)` (`Sources/HyperImageCore/Imaging/Bitmap.swift`) return RGBA bytes. Compare colour values with a tolerance: `abs(Int(a) - Int(b)) < 6` (see `rotationIsClockwise`, `flipHorizontalMirrors`). Exact equality is used only where the pipeline writes exact values (`canvas` background `[255, 255, 255, 255]`).

## Coverage

**Requirements:** None enforced. No coverage threshold is configured, and the project's Swift targets have no coverage gate in `Package.swift` or `scripts/`.

**View Coverage:**
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --enable-code-coverage
```
Note: this runs the full suite (several minutes). Use it only for a deliberate coverage check.

**Coverage by layer (observed):**
- `HyperImageCore` pipeline, geometry, encoders, format sweeps, CCF import, and JPEG handling each have a dedicated suite.
- `HyperImage` (the executable) has no unit tests for SwiftUI views. Its tested surface is `AppModel` (input list, virtual folders) and `ConversionRunner` (batch flow, overwrite prompts, cancel). Views are covered only by `scripts/ui-smoke.sh`.
- `Sources/HyperImage/Browser/`, `Sources/HyperImage/Advanced/` views, and `PersistedState` decode edge cases have no direct tests.

## UI Smoke Test

`scripts/ui-smoke.sh` is the only test of SwiftUI rendering:
- Builds the debug app with `swift build`, then launches `.build/debug/HyperImage` once per screen with `HYPERIMAGE_*` environment variables (`HYPERIMAGE_SHEET`, `HYPERIMAGE_STEP`, `HYPERIMAGE_WINDOW`, `HYPERIMAGE_SNAPSHOT`). These hooks are defined in `Sources/HyperImage/App/DebugLaunch.swift` under `#if DEBUG`.
- Each run writes PNGs to the output directory; a run fails when fewer PNG files than `EXPECT` appear. The main window is one PNG, a sheet adds another.
- Screens covered: `main`, `format`, `about`, every `advanced-<step>` (resize, rotate, crop, canvas, colorDepth, adjustments, dpi, text, watermark, border), `preview`, `progress`.
- Adds a new screen: add a `shot <name>` line with `EXPECT=2` (sheet or extra window) or `EXPECT=1` (main window only), and the matching `HYPERIMAGE_*` hook in `DebugLaunch.swift`.
- Does not need Screen Recording permission (the app draws its own views via `cacheDisplay`).

## Test Types

**Unit Tests:**
- Scope: pure value logic: geometry (`GeometryTests.swift`), text variables (`TextVariableTests.swift`), and simple-mode settings (`SimpleModeTests.swift`).
- Approach: call the static function or struct method directly, assert on the returned value.

**Integration Tests:**
- Scope: real image pipeline on fixtures (`PipelineTests.swift`, `PipelineSweepTests.swift`, `RegressionTests.swift`), real encoders across all output formats (`EncoderTests.swift`, `FormatSweepTests.swift`), unusual inputs (`UnusualInputTests.swift`), and batch conversion through the app model (`AppFlowTests.swift`).
- Approach: real files in temporary directories; real `ImageIO`/`libjpeg`/`libwebp` calls.

**E2E Tests:**
- Not automated with XCUITest or Playwright. The closest equivalent is `scripts/ui-smoke.sh`, which is a screenshot smoke test and does not drive user interactions.

**Opt-in comparison:**
- `ReferenceComparison` compares output against the original FSResizer app's reference renders when `REF_OUTPUT_DIR` is set. It prints a per-case mean absolute difference table; it does not assert thresholds.

## Common Patterns

**Async Testing:**
Use `async throws` test functions and poll with a bounded loop when a runner is asynchronous. The `waitUntilDone` helper in `Tests/HyperImageAppTests/AppFlowTests.swift`:
```swift
func waitUntilDone(_ runner: ConversionRunner, answering decision: OverwriteDecision? = nil) async throws {
    for _ in 0..<600 {
        if let decision, runner.prompt != nil { runner.answer(decision) }
        if !runner.isRunning { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("conversion did not finish")
}
```
- Bounded loop (600 × 50 ms = 30 s) with `Issue.record` on timeout, so a hang fails the test instead of blocking the run.
- Prefer this polling helper to `Task.sleep` with fixed delays in tests that assert final state.
- `@MainActor` test targets: `HyperImageAppTests` uses `defaultIsolation(MainActor.self)`, so test methods that touch `AppModel` or `ConversionRunner` run on the main actor without extra annotation.

**Error Testing:**
```swift
@Test func missingWatermarkIsReported() {
    var options = AdvancedOptions()
    options.watermark.enabled = true
    options.watermark.imagePath = "/nonexistent/logo.png"
    #expect(throws: ImagingError.self) { try ImagePipeline(options: options) }
}
```
- Use `#expect(throws: <ErrorType>.self) { ... }` to check the error type. `ImagingError` and `DelphiStreamError` conform to `Equatable`, so an exact case can also be compared when needed.
- For batch outcomes, assert on the record status instead of throwing: `#expect(runner.records.map(\.status) == [expected, expected])`.

**Concurrency-sensitive tests:**
- `ImagePipeline` and `BatchConverter` are `Sendable`; tests may run them concurrently. Use `actor Collector` (shown above) to collect records from `@Sendable` callbacks.

## Adding New Tests

1. Choose the existing suite file that matches the area (`PipelineTests.swift` for a new pipeline step, `EncoderTests.swift` for an encoder, `AppFlowTests.swift` for app-model behaviour). Create a new `<Area>Tests.swift` only for a new area.
2. Use `Fixtures.landscape()` / `Fixtures.portrait()` for inputs. Generate other inputs with `CGContext` into a `TemporaryDirectory()`.
3. Configure options through the `run({ $0.... }, on:)` helper; do not construct `ImagePipeline` directly unless you need the thrown error from `init`.
4. Assert exact sizes for geometry, a tolerance (`< 6`) for pixel colour after resampling, and exact values only where the pipeline is exact.
5. Use `@Test(arguments:)` for enum-wide coverage. Use `.enabled(if:)` for tests that need `Vendor/` artifacts.
6. Run the matching `--filter` first, then the full `swift test` once before handing off.

---

*Testing analysis: 2026-10-20*
