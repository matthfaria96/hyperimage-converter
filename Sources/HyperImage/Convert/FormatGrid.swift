import HyperImageCore
import SwiftUI

/// The four formats people convert to most, as large tiles; the rest sit in a menu (Permute-style).
struct FormatGrid: View {
    @Binding var format: OutputFormat
    @Namespace private var selection

    private static let main: [OutputFormat] = [.jpeg, .heic, .png, .webp]
    private static let others: [OutputFormat] = OutputFormat.allCases.filter { !main.contains($0) }

    var body: some View {
        VStack(spacing: 8) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow { tile(.jpeg); tile(.heic) }
                GridRow { tile(.png); tile(.webp) }
            }
            Menu {
                ForEach(Self.others, id: \.self) { other in
                    Button { pick(other) } label: {
                        if other == format { Label(other.menuTitle, systemImage: "checkmark") } else { Text(other.menuTitle) }
                    }
                }
            } label: {
                Label(Self.others.contains(format) ? format.menuTitle : String(localized: "Outros formatos"),
                      systemImage: Self.others.contains(format) ? "checkmark.circle.fill" : "ellipsis.circle")
                    .frame(maxWidth: .infinity)
            }
            .menuIndicator(.visible)
            .buttonStyle(.glass)
            .tint(Self.others.contains(format) ? Color.accentColor : nil)
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
