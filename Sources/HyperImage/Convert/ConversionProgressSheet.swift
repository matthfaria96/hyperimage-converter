import HyperImageCore
import SwiftUI

struct ConversionProgressSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Bindable var runner: ConversionRunner
    @State private var sheetAlert: AppAlert?
    @State private var reportedID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressHeader(runner: runner)
            ProgressView(value: runner.progress)
                .tint(runner.isRunning ? .accentColor : ProgressHeader.Outcome(runner).tint)
                .animation(.easeInOut(duration: 0.3), value: runner.progress)
            table
            footer
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 520)
        .overlay {
            if let prompt = runner.prompt { OverwritePanel(url: prompt.url, answer: runner.answer) }
        }
        .onChange(of: runner.completionID, initial: true) { _, id in reportIfNeeded(id) }
        .alert(item: $sheetAlert) { Alert(title: Text($0.title), message: Text($0.message)) }
        .onChange(of: runner.openFolderWhenDone) { _, value in app.state.convert.openFolderWhenDone = value }
        .interactiveDismissDisabled(runner.isRunning)
        .onDisappear { if runner.isRunning { runner.cancel() } }
    }

    private func reportIfNeeded(_ id: Int) {
        guard id != reportedID, !runner.isRunning else { return }
        reportedID = id
        if let failure = runner.failure {
            sheetAlert = AppAlert(title: String(localized: "Falha na conversão"), message: failure)
        } else if runner.settings.showErrors, !runner.failures.isEmpty, !runner.wasCancelled {
            sheetAlert = AppAlert(title: String(localized: "\(runner.failures.count) arquivo(s) com erro"),
                                  message: runner.failures.prefix(8).map { r in
                                      "\(r.input.lastPathComponent): \(errorText(r.status))"
                                  }.joined(separator: "\n"))
        }
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

/// Title row: a status symbol that pops when the batch ends, plus the space saved.
private struct ProgressHeader: View {
    enum Outcome {
        case running, success, partial, cancelled, failed

        init(_ runner: ConversionRunner) {
            if runner.isRunning { self = .running }
            else if runner.failure != nil { self = .failed }
            else if runner.wasCancelled { self = .cancelled }
            else if !runner.failures.isEmpty { self = .partial }
            else { self = .success }
        }

        var tint: Color {
            switch self {
            case .running: .accentColor
            case .success: .green
            case .partial, .cancelled: .orange
            case .failed: .red
            }
        }
    }

    let runner: ConversionRunner

    var body: some View {
        let outcome = Outcome(runner)
        HStack(spacing: 10) {
            Image(systemName: symbol(outcome))
                .font(.title2)
                .foregroundStyle(outcome.tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: runner.completionID)
                .symbolEffect(.rotate, isActive: outcome == .running)
            Text(title(outcome)).font(.title3.weight(.semibold))
            if outcome != .running, runner.oldTotal > runner.newTotal, runner.oldTotal > 0 {
                let saved = runner.oldTotal - runner.newTotal
                Label("Economia de \(formatBytes(saved)) (\(Int((Double(saved) / Double(runner.oldTotal) * 100).rounded())) %)",
                      systemImage: "arrow.down.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.green.opacity(0.14), in: .capsule)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Spacer()
            Text("\(runner.finishedCount) de \(runner.records.count) arquivos")
                .foregroundStyle(.secondary).monospacedDigit()
                .contentTransition(.numericText())
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: outcome == .running)
        .animation(.default, value: runner.finishedCount)
    }

    private func symbol(_ outcome: Outcome) -> String {
        switch outcome {
        case .running: "arrow.triangle.2.circlepath"
        case .success: "checkmark.circle.fill"
        case .partial: "exclamationmark.triangle.fill"
        case .cancelled: "stop.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private func title(_ outcome: Outcome) -> LocalizedStringKey {
        switch outcome {
        case .running: "Convertendo…"
        case .success: "Conversão concluída"
        case .partial: "Concluída com erros"
        case .cancelled: "Conversão cancelada"
        case .failed: "Falha na conversão"
        }
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
