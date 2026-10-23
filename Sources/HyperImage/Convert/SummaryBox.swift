import HyperImageCore
import SwiftUI

/// Floating glass summary: estimated (or actual) result, progress, the main action and a status line.
struct SummaryBox: View {
    @Environment(AppModel.self) private var app
    let runner: ConversionRunner
    let start: () -> Void
    @State private var estimate: Estimate?

    private var finished: Bool { runner.hasResults && !runner.isRunning }

    var body: some View {
        let mode = app.state.convert.mode
        VStack(alignment: .leading, spacing: 12) {
            if !app.inputs.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(finished ? "Resultado" : "Estimativa").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text(countText).font(.subheadline).foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    Text(headline).font(.title.weight(.semibold)).monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: headline)
                        .redacted(reason: estimate == nil && !finished ? .placeholder : [])
                    Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        .contentTransition(.opacity)
                        .animation(.snappy, value: detail)
                }
                .accessibilityElement(children: .combine)
                .transition(.blurReplace)
            }

            if runner.isRunning || runner.hasResults {
                ProgressStats(runner: runner)
                    .transition(.blurReplace)
            }

            if runner.isRunning {
                Button(role: .cancel) { runner.cancel() } label: {
                    Label("Cancelar", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                .transition(.blurReplace)
            } else {
                Button(action: start) {
                    Label(mode.actionTitle, systemImage: mode.symbol)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(app.inputs.isEmpty)
                .help("⌘↩")
                .transition(.blurReplace)
                if finished && !runner.wasCancelled {
                    HStack(spacing: 16) {
                        if runner.doneCount > 0 {
                            Button("Mostrar no Finder", systemImage: "folder") {
                                FilePanels.reveal(runner.records.filter { $0.status == .done }.map(\.output))
                            }
                        }
                        if !runner.failures.isEmpty {
                            Button("Ver erros (\(runner.failures.count))", systemImage: "exclamationmark.triangle") {
                                app.route = .errors
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity)
                    .transition(.blurReplace)
                }
            }
            StatusLine(runner: runner, hasInputs: !app.inputs.isEmpty)
        }
        .animation(.snappy, value: runner.isRunning)
        .animation(.snappy, value: runner.hasResults)
        .animation(.snappy, value: app.inputs.isEmpty)
        .sensoryFeedback(.success, trigger: runner.completionID) { _, _ in finished && runner.failures.isEmpty && !runner.wasCancelled }
        .task(id: EstimateKey(app.state.convert, revision: app.inputsRevision)) {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            let settings = app.state.convert
            let urls = app.inputs.map(\.url)
            let work = Task.detached(priority: .utility) { Estimate.make(urls: urls, settings: settings) }
            let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            estimate = result
        }
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
        guard !app.inputs.isEmpty, let estimate else { return "≈ 000 KB" }
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
            .font(.callout)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
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
private struct EstimateKey: Equatable {
    let mode: ConvertMode
    let format: OutputFormat
    let formatSettings: FormatSettings
    let advanced: AdvancedOptions
    let resize: [Int]
    let reduction: [Int]
    let upscale: UpscaleSettings
    let revision: Int

    init(_ s: ConvertSettings, revision: Int) {
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

/// Converts a few sample files in memory and scales the result to the whole batch.
struct Estimate: Sendable {
    var bytes: Int64?
    var originalBytes: Int64 = 0
    var originalSize: PixelSize?
    var upscaledSize: PixelSize?

    nonisolated static func make(urls: [URL], settings: ConvertSettings) -> Estimate {
        guard !urls.isEmpty else { return Estimate() }
        let total = urls.reduce(Int64(0)) { $0 + BatchConverter.fileSize($1) }
        if settings.mode == .upscale {
            let size = ImageLoader.pixelSize(urls[0])
            return Estimate(originalBytes: total, originalSize: size,
                            upscaledSize: size.map { PixelSize(width: $0.width * settings.upscale.scale, height: $0.height * settings.upscale.scale) })
        }
        guard let pipeline = try? ImagePipeline(options: settings.effectiveAdvancedOptions) else { return Estimate(originalBytes: total) }
        var sampleIn: Int64 = 0, sampleOut: Int64 = 0
        for url in urls.prefix(3) {
            if Task.isCancelled { return Estimate(originalBytes: total) }
            guard let loaded = try? ImageLoader.load(url),
                  let output = try? OutputEncoder.encode(loaded, pipeline: pipeline, settings: settings) else { continue }
            sampleIn += BatchConverter.fileSize(url)
            sampleOut += Int64(output.data.count)
        }
        guard sampleIn > 0 else { return Estimate(originalBytes: total) }
        return Estimate(bytes: Int64(Double(total) * Double(sampleOut) / Double(sampleIn)), originalBytes: total)
    }
}
