import AppKit
import HyperImageCore
import SwiftUI
@preconcurrency import UserNotifications

/// Percentage on the Dock icon while a batch runs.
enum DockProgress {
    static func show(_ fraction: Double?) {
        NSApp.dockTile.badgeLabel = fraction.map { "\(Int(($0 * 100).rounded()))%" }
    }
}

/// When the batch ends with the app in the background: a system notification (asked once) and a Dock bounce.
enum CompletionNotifier {
    static func notify(done: Int, failed: Int, saved: Int64, mode: ConvertMode) {
        guard !NSApp.isActive else { return }
        NSApp.requestUserAttention(.informationalRequest)
        // The notification centre aborts the process when it runs outside an app bundle (swift run, tests).
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let content = UNMutableNotificationContent()
        content.title = failed == 0 ? String(localized: "Pronto!") : String(localized: "Concluído com erros")
        var body = done == 1 ? String(localized: "1 imagem processada") : String(localized: "\(done) imagens processadas")
        if failed > 0 { body += String(localized: " · \(failed) com erro") }
        if mode != .upscale, saved > 0 { body += String(localized: " · economia de \(formatBytes(saved))") }
        content.body = body
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

/// Every failed file with its reason, copyable.
struct ErrorListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let failures: [ConversionRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(failures.count == 1 ? "1 arquivo não foi processado" : "\(failures.count) arquivos não foram processados",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .symbolRenderingMode(.multicolor)
            List(failures) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.input.lastPathComponent).font(.callout.weight(.medium))
                    Text(errorText(record.status)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .contextMenu { Button("Mostrar no Finder") { FilePanels.reveal([record.input]) } }
            }
            .frame(minHeight: 180)
            HStack {
                Button("Copiar lista") {
                    let text = failures.map { "\($0.input.path): \(errorText($0.status))" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Spacer()
                Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 380)
    }
}
