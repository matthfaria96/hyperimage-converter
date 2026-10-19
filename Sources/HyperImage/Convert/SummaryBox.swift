import HyperImageCore
import SwiftUI

/// Estimated (or actual) result, progress, the main action button and a status line.
struct SummaryBox: View {
    @Environment(AppModel.self) private var app
    let runner: ConversionRunner
    let start: () -> Void
    @State private var estimate: Estimate?

    var body: some View {
        let mode = app.state.convert.mode
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(runner.hasResults && !runner.isRunning ? "Resultado" : "Resumo estimado").font(.callout.weight(.semibold))
                    Spacer()
                    Text(app.inputs.count == 1 ? "1 imagem" : "\(app.inputs.count) imagens")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(headline).font(.title2.weight(.bold)).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                ProgressView(value: runner.isRunning || runner.hasResults ? runner.progress : 0)
                    .tint(runner.failures.isEmpty ? .green : .orange)
                    .animation(.easeInOut(duration: 0.3), value: runner.progress)
                    .padding(.top, 4)
            }
            .padding(12)
            .background(.background, in: .rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)) }

            if runner.isRunning {
                Button(role: .cancel) { runner.cancel() } label: {
                    Label("Cancelar", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
            } else {
                Button(action: start) {
                    Label(mode.actionTitle, systemImage: mode.symbol)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(app.inputs.isEmpty)
            }
            Text(status.text)
                .font(.caption).foregroundStyle(status.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
            Text("Seus arquivos não saem deste Mac.").font(.caption2).foregroundStyle(.tertiary)
        }
        .task(id: EstimateKey(app.state.convert, urls: app.inputs.map(\.url))) {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            let settings = app.state.convert
            let urls = app.inputs.map(\.url)
            let work = Task.detached(priority: .utility) { Estimate.make(urls: urls, settings: settings) }
            let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            estimate = result
        }
        .onChange(of: app.inputs.map(\.url)) { runner.clearResults() }
    }

    // MARK: Text

    private var headline: String {
        if runner.hasResults && !runner.isRunning && runner.newTotal > 0 { return formatBytes(runner.newTotal) }
        guard !app.inputs.isEmpty, let estimate else { return "—" }
        if let size = estimate.upscaledSize { return "\(String(size.width)) × \(String(size.height))" }
        return estimate.bytes.map { "≈ " + formatBytes($0) } ?? "—"
    }

    private var detail: String {
        if runner.hasResults && !runner.isRunning && runner.oldTotal > 0 {
            let saved = runner.oldTotal - runner.newTotal
            return saved >= 0
                ? String(localized: "Original: \(formatBytes(runner.oldTotal)) · Economia de \(percent(saved, of: runner.oldTotal)) %")
                : String(localized: "Original: \(formatBytes(runner.oldTotal)) · \(percent(-saved, of: runner.oldTotal)) % maior")
        }
        guard !app.inputs.isEmpty, let estimate else { return String(localized: "Adicione imagens para estimar o resultado.") }
        if let original = estimate.originalSize, estimate.upscaledSize != nil {
            let dims = "\(String(original.width)) × \(String(original.height))"
            return String(localized: "Primeira imagem: \(dims) → ampliada \(app.state.convert.upscale.scale)×")
        }
        guard let bytes = estimate.bytes else { return String(localized: "Não foi possível estimar.") }
        let saved = estimate.originalBytes - bytes
        return saved >= 0
            ? String(localized: "Original: \(formatBytes(estimate.originalBytes)) · Economia estimada de \(percent(saved, of: estimate.originalBytes)) %")
            : String(localized: "Original: \(formatBytes(estimate.originalBytes)) · cerca de \(percent(-saved, of: estimate.originalBytes)) % maior")
    }

    private func percent(_ part: Int64, of total: Int64) -> Int {
        total > 0 ? Int((Double(part) / Double(total) * 100).rounded()) : 0
    }

    private var status: (text: String, color: Color) {
        if runner.isRunning {
            return (String(localized: "Processando \(min(runner.finishedCount + 1, runner.records.count)) de \(runner.records.count)…"), .secondary)
        }
        if let failure = runner.failure { return (failure, .red) }
        if runner.hasResults {
            if runner.wasCancelled { return (String(localized: "Cancelado."), .orange) }
            let done = runner.records.filter { $0.status == .done }.count
            if !runner.failures.isEmpty { return (String(localized: "\(done) concluídas · \(runner.failures.count) com erro."), .orange) }
            return (done == 1 ? String(localized: "1 imagem processada.") : String(localized: "\(done) imagens processadas."), .green)
        }
        return app.inputs.isEmpty ? (String(localized: "Adicione imagens para começar."), .secondary)
            : (String(localized: "Pronto para processar."), .secondary)
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
    let urls: [URL]

    init(_ s: ConvertSettings, urls: [URL]) {
        mode = s.mode
        format = s.format
        formatSettings = s.effectiveFormatSettings
        advanced = s.effectiveAdvancedOptions
        resize = [s.keepDimensions ? 0 : s.maxLongSide]
        reduction = [s.maxFileSizeBytes ?? 0]
        upscale = s.upscale
        self.urls = urls
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
