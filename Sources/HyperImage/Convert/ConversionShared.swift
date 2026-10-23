import HyperImageCore
import SwiftUI

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
struct OverwritePanel: View {
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
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.glassProminent)
                }
                HStack {
                    Spacer()
                    Button("Sobrescrever Todos") { answer(.yesToAll) }
                    Button("Sobrescrever") { answer(.yes) }
                }
            }
            .buttonStyle(.glass)
            .padding(22)
            .frame(width: 460)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: bytes)
}
