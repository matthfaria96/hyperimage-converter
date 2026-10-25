import AppKit
import SwiftUI

/// "Sobre o HyperImage Converter": centered and quiet, like About This Mac.
struct AboutView: View {
    @State private var showLicenses = false

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.bottom, 18)
            Text(verbatim: "HyperImage Converter")
                .font(.system(size: 24, weight: .semibold))
            Text("Versão \(Self.marketing) (\(Self.build))")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)

            Text("O HyperImage Converter converte, redimensiona e comprime imagens em lote, com renomeação, ajustes, marcas d'água e recorte sem perdas de JPEG. Também amplia imagens com IA (AI Upscale).")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 460)
                .padding(.top, 26)

            Text("O HyperImage Converter é software livre sob a GNU GPL v3.0. Ele usa os projetos de código aberto listados nas licenças.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.top, 14)

            HStack(spacing: 18) {
                Link("witchmymac.com", destination: URL(string: "http://witchmymac.com")!)
                    .font(.system(size: 12))
                Button("Licenças de código aberto") { showLicenses = true }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            .padding(.top, 10)

            CheckForUpdatesButton()
                .controlSize(.small)
                .padding(.top, 14)
        }
        .frame(width: 560)
        .padding(.top, 36)
        .padding(.bottom, 32)
        .sheet(isPresented: $showLicenses) { OpenSourceLicensesView() }
    }

    private static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

/// The licences of the app and of the open-source work it ships, shown in full so the notices travel with it.
/// Third-party texts are read from `Contents/Resources/Licenses`, copied there by build-app.sh.
struct OpenSourceLicensesView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let license: String
        let header: String
        let files: [String]
    }

    private let entries = [
        Entry(
            id: "hyperimage",
            name: "HyperImage Converter",
            license: "GNU General Public License v3.0",
            header: """
            Copyright (C) 2026 Matheus Faria
            Source code: https://github.com/matthfaria96/hyperimage-converter

            HyperImage Converter is free software: you can redistribute it and/or modify it under \
            the terms of the GNU General Public License as published by the Free Software \
            Foundation, either version 3 of the License, or (at your option) any later version. \
            It is distributed WITHOUT ANY WARRANTY; without even the implied warranty of \
            MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

            Full license text: https://www.gnu.org/licenses/gpl-3.0.html
            """,
            files: []
        ),
        Entry(
            id: "libjpeg",
            name: "IJG libjpeg 9f",
            license: "IJG License",
            header: "This software is based in part on the work of the Independent JPEG Group.",
            files: ["libjpeg-README.txt"]
        ),
        Entry(
            id: "libwebp",
            name: "libwebp 1.6.0",
            license: "BSD 3-Clause License",
            header: "",
            files: ["libwebp-COPYING.txt", "libwebp-PATENTS.txt"]
        ),
        Entry(
            id: "upscayl",
            name: "Upscayl (upscayl-bin)",
            license: "GNU Affero General Public License v3.0",
            header: """
            The AI Upscale engine runs as a separate program (upscayl-bin), not linked into the app.
            Source code: https://github.com/upscayl/upscayl-ncnn
            """,
            files: ["upscayl-LICENSE-AGPL-3.0.txt"]
        ),
        Entry(
            id: "sparkle",
            name: "Sparkle 2",
            license: "MIT License",
            header: "In-app updates (Verificar Atualizações…). https://sparkle-project.org",
            files: ["Sparkle-LICENSE.txt"]
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Licenças de código aberto")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("O HyperImage Converter tem código aberto e usa os projetos abaixo. As licenças estão reproduzidas na íntegra.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: entry.name)
                                .font(.system(size: 13, weight: .semibold))
                            Text(verbatim: entry.license)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            Text(verbatim: text(for: entry))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 640, height: 580) // fits the 72-column licence texts
    }

    private func text(for entry: Entry) -> String {
        guard !entry.files.isEmpty else { return entry.header }
        let texts = entry.files.compactMap { name -> String? in
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("Licenses/\(name)") else { return nil }
            return (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        }
        let body = texts.isEmpty
            ? String(localized: "Texto da licença indisponível nesta compilação (gere o app com build-app.sh).")
            : texts.joined(separator: "\n\n")
        return entry.header.isEmpty ? body : entry.header + "\n\n" + body
    }
}
