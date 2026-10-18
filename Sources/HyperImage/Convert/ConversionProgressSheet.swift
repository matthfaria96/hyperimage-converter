import HyperImageCore
import SwiftUI

struct ConversionProgressSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Bindable var runner: ConversionRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(runner.isRunning ? "Convertendo…" : (runner.wasCancelled ? "Conversão cancelada" : "Conversão concluída"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(runner.finishedCount) de \(runner.records.count) arquivos")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: runner.progress)
            table
            footer
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 520)
        .overlay {
            if let prompt = runner.prompt { OverwritePanel(url: prompt.url, answer: runner.answer) }
        }
        .onChange(of: runner.isRunning) { _, running in
            if !running, runner.settings.showErrors, !runner.failures.isEmpty, !runner.wasCancelled {
                app.alert = AppAlert(title: String(localized: "\(runner.failures.count) arquivo(s) com erro"),
                                     message: runner.failures.prefix(8).map { r in
                                         "\(r.input.lastPathComponent): \(errorText(r.status))"
                                     }.joined(separator: "\n"))
            }
        }
        .onChange(of: runner.openFolderWhenDone) { _, value in app.state.convert.openFolderWhenDone = value }
        .interactiveDismissDisabled(runner.isRunning)
        .onDisappear { if runner.isRunning { runner.cancel() } }
    }

    private var table: some View {
        Table(runner.records) {
            TableColumn("Nº") { r in Text("\(r.id + 1)").monospacedDigit().foregroundStyle(.secondary) }
                .width(36)
            TableColumn("Entrada") { r in Text(r.input.lastPathComponent).help(r.input.path).lineLimit(1) }
            TableColumn("Saída") { r in Text(r.output.lastPathComponent).help(r.output.path).lineLimit(1) }
            TableColumn("Status") { r in StatusBadge(status: r.status) }
                .width(min: 90, ideal: 110)
            TableColumn("Original") { r in sizeText(r.oldSize) }.width(70)
            TableColumn("Novo") { r in sizeText(r.status == .done ? r.newSize : nil) }.width(70)
            TableColumn("Proporção") { r in
                Text(r.status == .done ? r.ratio.map { "\(Int(($0 * 100).rounded())) %" } ?? "—" : "")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .width(70)
        }
        .contextMenu(forSelectionType: ConversionRecord.ID.self) { ids in
            Button("Mostrar no Finder") {
                FilePanels.reveal(ids.compactMap { id in runner.records.first { $0.id == id && $0.status == .done }?.output })
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Original: \(formatBytes(runner.oldTotal))")
                Text("Novo: \(formatBytes(runner.newTotal))")
            }
            VStack(alignment: .leading, spacing: 2) {
                let ratio = runner.oldTotal > 0 ? Double(runner.newTotal) / Double(runner.oldTotal) : 0
                Text("Proporção: \(Int((ratio * 100).rounded())) %")
                Text("Economia: \(formatBytes(max(0, runner.oldTotal - runner.newTotal)))")
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Decorrido: \(duration((runner.endDate ?? context.date).timeIntervalSince(runner.startDate)))")
                    Text("Restante: \(runner.remaining(now: context.date).map(duration) ?? "—")")
                }
            }
            Spacer()
            Toggle("Abrir pasta ao concluir", isOn: $runner.openFolderWhenDone)
            if runner.isRunning {
                Button("Cancelar") { runner.cancel() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Concluído") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .font(.callout)
        .monospacedDigit()
    }

    private func sizeText(_ bytes: Int64?) -> some View {
        Text(bytes.map { formatBytes($0) } ?? "")
            .monospacedDigit().foregroundStyle(.secondary)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .hourMinuteSecond))
    }
}

func errorText(_ status: ConversionStatus) -> String {
    if case let .failed(message) = status { return message }
    return ""
}

struct StatusBadge: View {
    let status: ConversionStatus

    var body: some View {
        switch status {
        case .pending: Text("Na fila").foregroundStyle(.secondary)
        case .working: ProgressView().controlSize(.small)
        case .done: Label("OK", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped: Label("Pulado", systemImage: "forward.fill").foregroundStyle(.orange)
        case let .failed(message): Label("Erro", systemImage: "xmark.octagon.fill").foregroundStyle(.red).help(message)
        }
    }
}

/// Five-way overwrite question (a system alert only shows three buttons comfortably).
private struct OverwritePanel: View {
    let url: URL
    let answer: (OverwriteDecision) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Label("“\(url.lastPathComponent)” já existe", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
                Text("Na pasta \((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath). Deseja substituir?")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancelar Conversão", role: .cancel) { answer(.cancel) }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Pular Todos") { answer(.noToAll) }
                    Button("Pular") { answer(.no) }
                }
                HStack {
                    Spacer()
                    Button("Sobrescrever Todos") { answer(.yesToAll) }
                    Button("Sobrescrever") { answer(.yes) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 440)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .shadow(radius: 20)
        }
    }
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: bytes)
}
