import AppKit
import SwiftUI

/// "Sobre o HyperImage Converter": version, credits and the third-party licences shipped in the bundle.
struct AboutView: View {
    private struct License: Identifiable {
        let id: String
        let title: String
        let files: [String]
    }

    private let licenses = [
        License(id: "libjpeg", title: "IJG libjpeg 9f", files: ["libjpeg-README.txt"]),
        License(id: "libwebp", title: "libwebp 1.6.0", files: ["libwebp-COPYING.txt", "libwebp-PATENTS.txt"]),
    ]
    @State private var selection = "libjpeg"

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text("HyperImage Converter").font(.title2.bold())
                Text("Versão \(Self.version)").foregroundStyle(.secondary)
            }
            Text("Conversor de imagens em lote para macOS.\nThis software is based in part on the work of the Independent JPEG Group.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Licença", selection: $selection) {
                ForEach(licenses) { Text($0.title).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ScrollView {
                Text(licenseText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(24)
        .frame(width: 620, height: 580) // fits the 72-column licence texts
    }

    private var licenseText: String {
        guard let license = licenses.first(where: { $0.id == selection }) else { return "" }
        let texts = license.files.compactMap { name -> String? in
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("Licenses/\(name)") else { return nil }
            return (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        }
        return texts.isEmpty ? String(localized: "Texto da licença indisponível nesta compilação (gere o app com build-app.sh).") : texts.joined(separator: "\n\n")
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}
