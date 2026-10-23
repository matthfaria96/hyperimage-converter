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
        let showsProgress = runner.isRunning || runner.hasResults
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(runner.hasResults && !runner.isRunning ? "Resultado" : "Resumo estimado").font(.callout.weight(.semibold))
                    Spacer()
                    Text(countText).font(.caption).foregroundStyle(.secondary)
                }
                Text(headline).font(.title2.weight(.bold)).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if showsProgress {
                    ProgressView(value: runner.progress)
                        .tint(runner.failures.isEmpty ? .green : .orange)
                        .animation(.easeInOut(duration: 0.3), value: runner.progress)
                        .padding(.top, 4)
                        .transition(.opacity)
                    ProgressStats(runner: runner).transition(.opacity).padding(.top, 2)
                }
            }
            .padding(12)
            .background(.background, in: .rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)) }
            .accessibilityElement(children: .combine)

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
                .help("⌘↩")
                if runner.hasResults && !runner.wasCancelled {
                    HStack {
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
                    .font(.callout)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(statusText(now: context.date))
                    .font(.caption).foregroundStyle(statusColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.snappy, value: showsProgress)
        .animation(.snappy, value: runner.isRunning)
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
        if runner.hasResults && !runner.isRunning {
            let done = runner.doneCount
            return done == 1 ? String(localized: "1 imagem pronta") : String(localized: "\(done) imagens prontas")
        }
        return app.inputs.count == 1 ? String(localized: "1 imagem") : String(localized: "\(app.inputs.count) imagens")
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

    private func statusText(now: Date) -> String {
        if runner.isRunning {
            // Outputs are still being planned: there is no count to show yet.
            if runner.records.isEmpty { return String(localized: "Preparando arquivos…") }
            let step = String(localized: "Processando \(min(runner.finishedCount + 1, runner.records.count)) de \(runner.records.count)")
            guard let left = runner.remaining(now: now) else { return step + "…" }
            return step + " · " + String(localized: "≈ \(Self.duration(left)) restantes")
        }
        if let failure = runner.failure { return failure }
        // Checked before `hasResults`: a run cancelled while planning ends with no records.
        if runner.wasCancelled { return String(localized: "Cancelado.") }
        if runner.hasResults {
            let done = runner.doneCount
            if !runner.failures.isEmpty { return String(localized: "\(done) concluídas · \(runner.failures.count) com erro.") }
            return done == 1 ? String(localized: "1 imagem processada.") : String(localized: "\(done) imagens processadas.")
        }
        return app.inputs.isEmpty ? String(localized: "Adicione imagens para começar.") : String(localized: "Pronto para processar.")
    }

    private var statusColor: Color {
        if runner.isRunning { return .secondary }
        if runner.failure != nil { return .red }
        if runner.wasCancelled { return .orange }
        if runner.hasResults { return runner.failures.isEmpty ? .green : .orange }
        return .secondary
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return String(localized: "\(max(s, 1)) s") }
        if s < 3600 { return String(localized: "\(s / 60) min \(s % 60) s") }
        return String(localized: "\(s / 3600) h \(s % 3600 / 60) min")
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
