import HyperImageCore
import SwiftUI

/// The four formats people convert to most, as large tiles (Permute-style); the rest are in `OtherFormatsRow`.
struct FormatGrid: View {
    @Binding var format: OutputFormat
    @Namespace private var selection

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow { tile(.jpeg); tile(.heic) }
            GridRow { tile(.png); tile(.webp) }
        }
        .padding(.vertical, 4)
    }

    private func tile(_ option: OutputFormat) -> some View {
        let selected = option == format
        return Button { pick(option) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(option.displayName).font(.headline)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(option.tileHint).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .help(option.menuTitle)
    }

    private func pick(_ option: OutputFormat) {
        withAnimation(.snappy) { format = option }
    }
}

/// The less common formats, as a standard pop-up row like the panel's other choices.
struct OtherFormatsRow: View {
    @Binding var format: OutputFormat

    private static let others: [OutputFormat] = OutputFormat.allCases.filter { ![.jpeg, .heic, .png, .webp].contains($0) }

    var body: some View {
        Picker("Outros formatos", selection: Binding<OutputFormat?>(
            get: { Self.others.contains(format) ? format : nil },
            set: { if let picked = $0 { withAnimation(.snappy) { format = picked } } }
        )) {
            Text("Nenhum").tag(OutputFormat?.none)
            Divider()
            ForEach(Self.others, id: \.self) { Text($0.menuTitle).tag(OutputFormat?.some($0)) }
        }
    }
}

extension OutputFormat {
    /// One short line under the format name in the grid.
    var tileHint: LocalizedStringKey {
        switch self {
        case .jpeg: "Compatível com tudo"
        case .heic: "Padrão do iPhone"
        case .png: "Sem perdas"
        case .webp: "Para sites"
        default: help
        }
    }
}

/// iPhone photos (HEIC) going anywhere but JPEG get a one-click nudge toward the format everything opens.
struct HEICHint {
    let count: Int

    init?(inputs: [InputItem], format: OutputFormat) {
        guard format != .jpeg else { return nil }
        let heic = inputs.filter { ["heic", "heif", "hif"].contains($0.url.pathExtension.lowercased()) }.count
        guard heic > 0, heic * 2 >= inputs.count else { return nil }
        count = heic
    }

    func view(useJPEG: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone").foregroundStyle(.tint)
            Text("Fotos do iPhone (HEIC)? JPEG abre em qualquer computador e site.").font(.callout)
            Spacer(minLength: 4)
            Button("Usar JPEG", action: useJPEG).buttonStyle(.glass).controlSize(.small)
        }
    }
}
