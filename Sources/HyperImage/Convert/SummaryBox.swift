import HyperImageCore
import SwiftUI

/// Bottom bar of the options panel: estimated (or actual) result, progress, the main action and a status line.
struct SummaryBox: View {
    @Environment(AppModel.self) private var app
    let runner: ConversionRunner
    let start: () -> Void
    let estimate: Estimate?

    private var finished: Bool { runner.hasResults && !runner.isRunning }
    /// Text starts where the text inside the form's cards does; the button spans the full card width.
    private static let textInset: CGFloat = 10

    var body: some View {
        let mode = app.state.convert.mode
        // Every row is always present (empty rows keep their height), so the bar never changes size.
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(finished ? "Resultado" : "Estimativa")
                    Spacer()
                    Text(countText).contentTransition(.numericText())
                }
                .font(.subheadline).foregroundStyle(.secondary)
                Text(headline).font(.title2.weight(.semibold)).monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: headline)
                    .redacted(reason: !app.inputs.isEmpty && estimate == nil && !finished ? .placeholder : [])
            }
            .padding(.horizontal, Self.textInset)
            .accessibilityElement(children: .combine)

            // One fixed-height slot: the explanation while idle, the progress once a batch starts.
            ZStack(alignment: .topLeading) {
                if runner.isRunning || runner.hasResults {
                    ProgressStats(runner: runner).transition(.blurReplace)
                } else {
                    Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                        .animation(.snappy, value: detail)
                        .transition(.blurReplace)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .topLeading)
            .padding(.horizontal, Self.textInset)

            Group {
                if runner.isRunning {
                    Button(role: .cancel) { runner.cancel() } label: {
                        Label("Cancelar", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button(action: start) {
                        Label(mode.actionTitle, systemImage: mode.symbol)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(app.inputs.isEmpty)
                    .help("⌘↩")
                }
            }
            .controlSize(.large)
            .transition(.blurReplace)

            HStack(spacing: 8) {
                StatusLine(runner: runner, hasInputs: !app.inputs.isEmpty)
                Spacer(minLength: 4)
                if finished && !runner.wasCancelled {
                    if !runner.failures.isEmpty {
                        Button("Ver erros (\(runner.failures.count))") { app.route = .errors }
                            .foregroundStyle(.orange)
                    } else if runner.doneCount > 0 {
                        Button("Mostrar no Finder") {
                            FilePanels.reveal(runner.records.filter { $0.status == .done }.map(\.output))
                        }
                    }
                }
            }
            .buttonStyle(.link)
            .font(.callout)
            .frame(height: 18)
            .padding(.horizontal, Self.textInset)
        }
        .animation(.snappy, value: runner.isRunning)
        .animation(.snappy, value: runner.hasResults)
        .sensoryFeedback(.success, trigger: runner.completionID) { _, _ in finished && runner.failures.isEmpty && !runner.wasCancelled }
        .onChange(of: app.inputsRevision) { runner.clearResults() }
    }

    private var countText: String {
        if finished {
            let done = runner.doneCount
            return done == 1 ? String(localized: "1 imagem pronta") : String(localized: "\(done) imagens prontas")
        }
        return app.inputs.count == 1 ? String(localized: "1 imagem") : String(localized: "\(app.inputs.count) imagens")
    }

    // MARK: Text

    private var headline: String {
        if finished && runner.newTotal > 0 { return formatBytes(runner.newTotal) }
        guard !app.inputs.isEmpty else { return "—" }
        guard let estimate else { return "≈ 000 KB" }
        if let size = estimate.upscaledSize { return "\(String(size.width)) × \(String(size.height))" }
        return estimate.bytes.map { "≈ " + formatBytes($0) } ?? "—"
    }

    private var detail: String {
        if finished && runner.oldTotal > 0 {
            let saved = runner.oldTotal - runner.newTotal
            return saved >= 0
                ? String(localized: "Original \(formatBytes(runner.oldTotal)) · economia de \(formatBytes(saved)) (\(percent(saved, of: runner.oldTotal)) %)")
                : String(localized: "Original \(formatBytes(runner.oldTotal)) · \(percent(-saved, of: runner.oldTotal)) % maior")
        }
        guard !app.inputs.isEmpty, let estimate else { return String(localized: "Adicione imagens para estimar o resultado.") }
        if let original = estimate.originalSize, estimate.upscaledSize != nil {
            let dims = "\(String(original.width)) × \(String(original.height))"
            return String(localized: "Primeira imagem: \(dims) → ampliada \(app.state.convert.upscale.scale)×")
        }
        guard let bytes = estimate.bytes else { return String(localized: "Não foi possível estimar.") }
        let saved = estimate.originalBytes - bytes
        return saved >= 0
            ? String(localized: "Original \(formatBytes(estimate.originalBytes)) · economia estimada de \(percent(saved, of: estimate.originalBytes)) %")
            : String(localized: "Original \(formatBytes(estimate.originalBytes)) · cerca de \(percent(-saved, of: estimate.originalBytes)) % maior")
    }

    private func percent(_ part: Int64, of total: Int64) -> Int {
        total > 0 ? Int((Double(part) / Double(total) * 100).rounded()) : 0
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return String(localized: "\(max(s, 1)) s") }
        if s < 3600 { return String(localized: "\(s / 60) min \(s % 60) s") }
        return String(localized: "\(s / 3600) h \(s % 3600 / 60) min")
    }
}

/// One line with a symbol: what the batch is doing or how it ended.
private struct StatusLine: View {
    let runner: ConversionRunner
    let hasInputs: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let (symbol, text, color) = status(now: context.date)
            Label {
                Text(text).contentTransition(.opacity)
            } icon: {
                Image(systemName: symbol)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: symbol)
            }
            .foregroundStyle(color)
            .lineLimit(1)
            .animation(.snappy, value: text)
        }
    }

    private func status(now: Date) -> (String, String, Color) {
        if runner.isRunning {
            // Outputs are still being planned: there is no count to show yet.
            if runner.records.isEmpty { return ("hourglass", String(localized: "Preparando arquivos…"), .secondary) }
            let step = String(localized: "Processando \(min(runner.finishedCount + 1, runner.records.count)) de \(runner.records.count)")
            guard let left = runner.remaining(now: now) else { return ("hourglass", step + "…", .secondary) }
            return ("hourglass", step + " · " + String(localized: "≈ \(SummaryBox.duration(left)) restantes"), .secondary)
        }
        if let failure = runner.failure { return ("xmark.octagon.fill", failure, .red) }
        // Checked before `hasResults`: a run cancelled while planning ends with no records.
        if runner.wasCancelled { return ("stop.circle.fill", String(localized: "Cancelado."), .orange) }
        if runner.hasResults {
            let done = runner.doneCount
            if !runner.failures.isEmpty {
                return ("exclamationmark.triangle.fill", String(localized: "\(done) concluídas · \(runner.failures.count) com erro."), .orange)
            }
            let text = done == 1 ? String(localized: "1 imagem processada.") : String(localized: "\(done) imagens processadas.")
            return ("checkmark.circle.fill", text, .green)
        }
        return hasInputs ? ("circle.dotted", String(localized: "Pronto para processar."), .secondary)
                         : ("photo.badge.plus", String(localized: "Adicione imagens para começar."), .secondary)
    }
}

/// Only what changes the output bytes; folder, overwrite and message options must not re-encode samples.
struct EstimateKey: Equatable {
    let mode: ConvertMode
    let format: OutputFormat
    let formatSettings: FormatSettings
    let advanced: AdvancedOptions
    let resize: [Int]
    let reduction: [Int]
    let upscale: UpscaleSettings
    let revision: Int

    let quality: [Int]

    init(_ s: ConvertSettings, revision: Int) {
        quality = [s.fullQuality ? 1 : 0, s.compressQuality]
        mode = s.mode
        format = s.format
        formatSettings = s.effectiveFormatSettings
        advanced = s.effectiveAdvancedOptions
        resize = [s.keepDimensions ? 0 : s.maxLongSide]
        reduction = [s.maxFileSizeBytes ?? 0]
        upscale = s.upscale
        self.revision = revision
    }
}

/// Shared by the summary and Comprimir's preview, so the samples are encoded once per change.
@Observable
final class EstimateStore {
    private(set) var estimate: Estimate?

    func refresh(urls: [URL], settings: ConvertSettings) async {
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        let work = Task.detached(priority: .utility) { Estimate.make(urls: urls, settings: settings) }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled else { return }
        withAnimation(.snappy) { estimate = result }
    }
}

/// Converts one sample per file type in memory and scales each result to the files of that type.
struct Estimate: Sendable {
    var bytes: Int64?
    var originalBytes: Int64 = 0
    var originalSize: PixelSize?
    var upscaledSize: PixelSize?

    /// File types sampled at most; the rest follow the overall ratio of the samples.
    nonisolated static let maxSamples = 4

    nonisolated static func make(urls: [URL], settings: ConvertSettings) -> Estimate {
        guard !urls.isEmpty else { return Estimate() }
        let sizes = urls.map { ($0, BatchConverter.fileSize($0)) }
        let total = sizes.reduce(Int64(0)) { $0 + $1.1 }
        if settings.mode == .upscale {
            let size = ImageLoader.pixelSize(urls[0])
            return Estimate(originalBytes: total, originalSize: size,
                            upscaledSize: size.map { PixelSize(width: $0.width * settings.upscale.scale, height: $0.height * settings.upscale.scale) })
        }
        guard let pipeline = try? ImagePipeline(options: settings.effectiveAdvancedOptions) else { return Estimate(originalBytes: total) }
        var estimated = 0.0, covered: Int64 = 0, sampleIn: Int64 = 0, sampleOut: Int64 = 0
        for group in sampleGroups(sizes) {
            if Task.isCancelled { return Estimate(originalBytes: total) }
            guard group.sampleBytes > 0, let loaded = try? ImageLoader.load(group.sample),
                  let output = try? OutputEncoder.encode(loaded, pipeline: pipeline, settings: settings) else { continue }
            let written = Int64(output.data.count)
            estimated += Double(group.totalBytes) * Double(written) / Double(group.sampleBytes)
            covered += group.totalBytes
            sampleIn += group.sampleBytes
            sampleOut += written
        }
        guard sampleIn > 0 else { return Estimate(originalBytes: total) }
        estimated += Double(total - covered) * Double(sampleOut) / Double(sampleIn)
        return Estimate(bytes: Int64(estimated.rounded()), originalBytes: total)
    }

    /// Files grouped by type (JPEG, HEIC, TIFF…), heaviest groups first; each is represented by its largest file,
    /// which weighs the most in the total. A list that starts with small JPEGs and ends in big TIFFs is still right.
    nonisolated static func sampleGroups(_ sizes: [(URL, Int64)]) -> [(sample: URL, sampleBytes: Int64, totalBytes: Int64)] {
        let groups = Dictionary(grouping: sizes) { entry in
            OutputFormat.matching(entry.0)?.rawValue ?? entry.0.pathExtension.lowercased()
        }
        return groups.values
            .compactMap { files -> (sample: URL, sampleBytes: Int64, totalBytes: Int64)? in
                guard let largest = files.max(by: { $0.1 < $1.1 }) else { return nil }
                return (largest.0, largest.1, files.reduce(Int64(0)) { $0 + $1.1 })
            }
            .sorted { $0.totalBytes > $1.totalBytes }
            .prefix(maxSamples)
            .map { $0 }
    }
}
