# Coding Conventions

**Analysis Date:** 2026-10-20

## Naming Patterns

**Files:**
- One primary type per file, named after it: `Sources/HyperImageCore/Pipeline/ImagePipeline.swift` holds `ImagePipeline`, `Sources/HyperImage/App/AppModel.swift` holds `AppModel`.
- Several small related types may share a file when they form one unit: `Sources/HyperImageCore/Imaging/Bitmap.swift` (`Bitmap` + `ImagingError`), `Sources/HyperImage/Convert/ConversionShared.swift` (`OverwriteDecision`, `ConversionStatus`, `ConversionRecord`, `StatusBadge`, `OverwritePanel`).
- SwiftUI views end in `View` or a noun describing the panel: `SettingsPanel.swift`, `DropZoneViews.swift`, `ResizeStepView.swift`, `ConversionPreviewSheet.swift`.
- Test files end in `Tests.swift` (`PipelineTests.swift`, `EncoderTests.swift`), except helper or comparison files: `ReferenceComparison.swift`, `TextVariableTests.swift`.
- Scripts in `scripts/` are kebab-case shell files (`ui-smoke.sh`, `sync-strings.sh`) or small Swift tools (`make-icon.swift`, `window-id.swift`).

**Types:**
- `UpperCamelCase` for structs, enums, classes, protocols. Domain value types are `struct`s with `Codable, Equatable, Sendable` conformances, e.g. `ResizeOptions` in `Sources/HyperImageCore/Models/ResizeOptions.swift`.
- Enums are `String`-backed when they are persisted, with `CaseIterable` for UI pickers: `ResizeMode`, `ResizeSide`, `ResizeFilter` in `Sources/HyperImageCore/Models/ResizeOptions.swift`; `AppearanceChoice`, `BrowserLayout` in `Sources/HyperImage/App/PersistedState.swift`.
- Errors are named `<Area>Error` or `ImagingError`: `DelphiStreamError` (`Sources/HyperImageCore/Options/DelphiStream.swift`), `UpscaleError` (`Sources/HyperImageCore/Upscale/Upscaler.swift`), `ImagingError` (`Sources/HyperImageCore/Imaging/Bitmap.swift`).
- Shared helpers are `enum` namespaces with `static` members (no instances): `ImageLoader`, `ColorAdjuster`, `Transforms`, `ResizeGeometry`, `CropGeometry`, `TolerantJSON`, `DebugLaunch`.

**Functions:**
- `lowerCamelCase` verbs for actions, nouns for accessors: `process(_:)` in `ImagePipeline`, `records(for:)` in `BatchConverter`, `hasFolderItems` as a computed property in `AppModel`.
- Label style follows Swift API guidelines: `add(_:)`, `remove(_:)`, `move(_:toFolder:)`, `start(items:settings:)`.
- Static factories are named `make(...)` (`StepPreview.make()`, `SummaryBox.make(urls:...)`, `ConversionPreviewSheet.make(url:...)`).
- Private helpers carry `private` or `private static`; no leading underscores.

**Variables and properties:**
- `lowerCamelCase`. Constants inside types use `private static let`: `PersistedState.key = "HyperImage.state.v1"` (`Sources/HyperImage/App/PersistedState.swift`).
- Short local names are acceptable inside numeric code: `let w = 400, h = 300`, `let o = options`, `let i = (y * bitmap.width + x) * 4` (`Sources/HyperImageCore/Pipeline/ImagePipeline.swift`, `Tests/HyperImageCoreTests/UnusualInputTests.swift`).
- Observable state is stored with `private(set)` when only the owner mutates it, e.g. `private(set) var inputs` in `AppModel`, `private(set) var records` in `ConversionRunner`.

**Identifiers in UI and data:**
- Source identifiers and comments are English. User-facing strings are Brazilian Portuguese (the app ships `pt-BR` as its source language, see `Resources/Localizable.xcstrings`).
- Some UI literals are passed straight to SwiftUI and therefore localized through the catalog: `Text("Na fila")`, `Button("Cancelar Conversão", role: .cancel)` in `Sources/HyperImage/Convert/ConversionShared.swift`.
- Core-layer messages use `String(localized:)` inside `LocalizedError.errorDescription`: see `ImagingError` in `Sources/HyperImageCore/Imaging/Bitmap.swift`.

## Code Style

**Formatting:**
- No formatter configuration is committed (no `.swiftformat`, `.editorconfig`, or `.prettierrc`). Follow the surrounding file.
- Indentation is 4 spaces. Lines are long where the content is a table or a one-line `switch`; wrap arguments onto continuation lines aligned under the first argument, as in `Sources/HyperImageCore/Batch/BatchConverter.swift` (`init(settings:...)`).
- Multiple short statements are often placed on one line with `;` when they are a logical group: `o.resize.enabled = true; o.resize.width = 800` (`Tests/HyperImageCoreTests/PipelineTests.swift`), `$0.rotate.enabled = true; $0.rotate.rotate = true` (`Tests/HyperImageCoreTests/ReferenceComparison.swift`).
- Trailing closures and `switch` expressions are used heavily in views and in the pipeline.

**Linting:**
- No SwiftLint or other linter configuration is present. The compiler, with Swift 6.2 strict concurrency (`swift-tools-version: 6.2` in `Package.swift`), is the only static gate.
- `.unsafeFlags` in `Package.swift` suppress specific C warnings for the vendored libraries only (`-Wno-shorten-64-to-32`, `-Wno-unused-function`, `-Wno-unused-parameter`, `-Wno-deprecated-non-prototype`). Do not extend these to Swift code.

**Swift language settings (from `Package.swift`):**
- `platforms: [.macOS(.v26)]`: APIs from macOS 26 may be used without availability checks.
- `HyperImage` and `HyperImageAppTests` set `swiftSettings: [.defaultIsolation(MainActor.self)]`: top-level app code is `@MainActor` by default. Mark background work explicitly with `nonisolated` or `Task.detached`.
- `HyperImageCore` does not use default isolation. Its public types that cross threads are `Sendable`, and types holding `CGImage` use `@unchecked Sendable`, e.g. `ProcessedImage` and `ImagePipeline` in `Sources/HyperImageCore/Pipeline/ImagePipeline.swift`.

## Access Control

- `HyperImageCore` is a library surface: every type and member meant for the app or tests is `public`, and the `public` modifier is written on each declaration, e.g. `public struct ResizeOptions` with `public var enabled = false`.
- `HyperImage` (the executable) uses internal access by default. Do not add `public` in the app target.
- `private` is used for implementation details (`private static func scan(...)`, `private var saveTask`, `private let watermark`).
- `@testable import` is used in every test file to reach internal members of `HyperImageCore` and `HyperImage`.

## Import Organization

**Order:**
1. Apple frameworks first, alphabetically: `import AppKit`, `import CoreGraphics`, `import Foundation`, `import ImageIO`, `import Observation`, `import SwiftUI`.
2. Project modules next: `import HyperImageCore`.
3. Test frameworks and `@testable` imports last: `import Testing`, `@testable import HyperImageCore`.

Examples: `Sources/HyperImage/App/AppModel.swift` (`AppKit`, `HyperImageCore`, `Observation`), `Tests/HyperImageCoreTests/PipelineTests.swift` (`CoreGraphics`, `Foundation`, `ImageIO`, `Testing`, `@testable HyperImageCore`).

**Path Aliases:**
- None. Swift modules are referenced by target name only.

## Error Handling

**Strategy:** Typed errors for domain failures, `try` propagation for I/O and image work, and `try?` only for best-effort side effects.

**Patterns:**
- Domain errors are `enum`s conforming to `LocalizedError` (and often `Equatable` so tests can match them): `ImagingError` in `Sources/HyperImageCore/Imaging/Bitmap.swift` with cases `cannotAllocate`, `unreadable`, `encodeFailed`, `watermarkMissing`; `DelphiStreamError` in `Sources/HyperImageCore/Options/DelphiStream.swift`.
- Failures are thrown, not returned as optionals, when the caller must know why: `ImagePipeline.init(options:) throws` checks for a missing watermark file and throws `ImagingError.watermarkMissing` (`Sources/HyperImageCore/Pipeline/ImagePipeline.swift`).
- Optionals are used for "absent" or "not applicable" results, not for errors: `ResizeGeometry.plan(...)` returns `nil` when no resize applies; `JPEGQualityEstimator` returns `nil` when the file cannot be read (`Sources/HyperImageCore/IO/JPEGQualityEstimator.swift`).
- Per-file batch failures are recorded, not thrown: a failing file becomes `ConversionStatus.failed(String)` on its `ConversionRecord` (`Sources/HyperImageCore/Batch/BatchConverter.swift`, `Sources/HyperImage/Convert/ConversionShared.swift`). The batch continues with the next file.
- `try?` is used for best-effort work only: cleanup (`defer { try? fm.removeItem(at: temp) }` in `Sources/HyperImageCore/Upscale/Upscaler.swift`), metadata reads (`try? url.resourceValues(...)` in `Sources/HyperImageCore/IO/ImageLoader.swift`), and persistence decode fallback (`PersistedState.decode` in `Sources/HyperImage/App/PersistedState.swift`). Do not use `try?` where a failed write must be reported to the user.
- Force unwraps appear only where the value is a constant that cannot fail: `CGColorSpace(name: CGColorSpace.sRGB)!` and `baseAddress!` on non-empty buffers. Prefer `guard let ... else` or `try #require` in tests for anything that depends on input files.
- Settings decoding is tolerant: `TolerantJSON.decode(_:from:defaults:)` (`Sources/HyperImageCore/Options/TolerantJSON.swift`) merges the incoming JSON over defaults so older or partial saved state still loads. New persisted fields must have default values in their struct declaration.

**Example (throwing domain error, from `Sources/HyperImageCore/Pipeline/ImagePipeline.swift`):**
```swift
guard FileManager.default.fileExists(atPath: url.path) else {
    throw ImagingError.watermarkMissing(options.watermark.imagePath)
}
```

## Logging

**Framework:** None. There is no `print`, `NSLog`, `os.Logger`, or `console.log` in `Sources/`. Diagnostics are surfaced to the user through `ConversionRecord.status`, `ConversionRunner.failure`, and `AppAlert`.

**Patterns:**
- Debug-only hooks are compiled under `#if DEBUG` and read `HYPERIMAGE_*` environment variables: `Sources/HyperImage/App/DebugLaunch.swift`. Keep new debug hooks in that file and document them in its header comment.
- The `Upscaler` captures the backend's output in a private `LogBuffer` class (`Sources/HyperImageCore/Upscale/Upscaler.swift`) rather than printing it.

## Comments

**When to Comment:**
- Explain *why* a non-obvious choice was made, especially for image-processing and ordering constraints: `// Block alignment only means something while the pixels are still the JPEG's own grid.` (`Sources/HyperImageCore/Pipeline/ImagePipeline.swift`); `// The GPU already parallelises one upscale; running several at once only fights over VRAM.` (`Sources/HyperImageCore/Batch/BatchConverter.swift`).
- Explain UI workarounds in one line: `// terminate(_:) can be held up by an open sheet` (`Sources/HyperImage/App/DebugLaunch.swift`).
- Reference the external spec or reference app by section when a behaviour is copied: `/// Runs the real pipeline on the reference inputs and checks the reference output sizes (SPEC §8).` (`Tests/HyperImageCoreTests/PipelineTests.swift`).
- Do not comment obvious code.

**Doc comments:**
- Use `///` on types and on non-trivial functions. The first sentence is the summary. Examples: `/// Shared window state: the input list and all persisted settings.` (`AppModel`), `/// Mean absolute RGB difference (0–255) when sizes match.` (`ReferenceComparison`).
- Use `// MARK:` to section long types. Two forms exist: `// MARK: Input list` (in `Sources/HyperImage/App/AppModel.swift`) and `// MARK: - Building blocks` (in `Sources/HyperImage/Convert/SettingsPanel.swift`). Prefer the form with ` - ` for new code in files that already use it.
- Put a usage line in the header of script-like or opt-in files, e.g. `/// REF_OUTPUT_DIR=<...> swift test --filter ReferenceComparison` (`Tests/HyperImageCoreTests/ReferenceComparison.swift`).

## Function Design

**Size:** Pipeline and geometry functions are short, delegating to one helper per step. `ImagePipeline.process` (`Sources/HyperImageCore/Pipeline/ImagePipeline.swift`) is about 40 lines and calls one `Transforms`, `ColorAdjuster`, `TextOverlay`, `WatermarkOverlay`, or `BorderEffect` per enabled step. Largest source files: `Sources/HyperImage/Convert/SettingsPanel.swift` (483 lines), `Sources/HyperImage/Input/WorkspaceView.swift` (355 lines). Keep new files under about 400 lines and split views into sections (see `SettingsPanel.swift`'s `// MARK: - Convert / Compress`).

**Parameters:**
- Pass option structs whole, not individual fields: `Transforms.resize(_ image, plan:, filter:, fill:)`, `ColorAdjuster.apply(_ options, to:)`.
- Use argument labels that name the source and destination: `ResizeGeometry.plan(source:options:sourceDPI:)`, `CropGeometry.rect(source:options:sourceDPI:jpegBlock:)`.
- Use closures with `inout` for test configuration: `run({ $0.resize.enabled = true }, on: image)` (`Tests/HyperImageCoreTests/PipelineTests.swift`).

**Return Values:**
- Return value types (`struct`) from pure functions: `ProcessedImage`, `LoadedImage`, `ConversionRecord`.
- Return `[ConversionRecord]` (not a stream) from `BatchConverter.records(for:)`; progress is reported via the `fileProgress` callback.

## Module Design

**Exports:**
- Public surface is declared per declaration with `public`. Public initialisers are written explicitly when a default is needed: `public init() {}` in `ResizeOptions`.
- Options structs use `public var` with default values, so `ResizeOptions()` is always a valid configuration.

**Models and state:**
- Options and persisted settings are `struct`s with `var` fields that are mutated in place by the UI through `@Bindable` bindings or `inout`. This is the established pattern; it differs from the immutability preference in the user's global rules, so when you add to these models, follow the existing `var`-with-defaults shape rather than introducing copy-on-write helpers.
- UI state lives in `@Observable` classes: `AppModel`, `ConversionRunner`, `BrowserModel` (`Sources/HyperImage/Browser/BrowserModel.swift`). Use `@ObservationIgnored` for stored properties that should not trigger view updates (`ConversionRunner.indexByURL`, `AppModel.totalTask`).
- Views receive models through the environment: `@Environment(AppModel.self) private var app`, then `@Bindable var app = app` inside `body` to create bindings (`Sources/HyperImage/Convert/SettingsPanel.swift`).

**Barrel Files:**
- Not used. Each target's sources are imported by module name.

**C targets:**
- `CWebP` (`Sources/CWebP`) and `CJPEG` (`Sources/CJPEG`) are vendored third-party C code with their own public headers in `include/` (`Sources/CWebP/include/CWebP.h`, `Sources/CJPEG/include/CJPEG.h`). Swift wrappers live in `Sources/HyperImageCore/IO/` (`WebPEncoder.swift`, `LibJPEG.swift`). Do not edit files under `Sources/CWebP/libwebp/` or `Sources/CJPEG/libjpeg/`; add Swift-side wrappers instead.

---

*Convention analysis: 2026-10-20*
