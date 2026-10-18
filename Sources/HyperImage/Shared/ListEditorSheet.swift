import SwiftUI

/// Editable list with add / remove / move / restore defaults (used for size presets and rename templates).
struct ListEditorSheet<Item: Hashable, Row: View>: View {
    let title: String
    @Binding var items: [Item]
    let defaults: [Item]
    let newItem: Item
    @ViewBuilder let row: (Binding<Item>) -> Row
    @Environment(\.dismiss) private var dismiss
    @State private var draft: [Entry] = []
    @State private var selection: UUID?

    struct Entry: Identifiable {
        let id = UUID()
        var value: Item
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.headline).padding(.top, 14)
            List(selection: $selection) {
                ForEach($draft) { $entry in row($entry.value).tag(entry.id) }
                    .onMove { draft.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 260)
            HStack {
                ControlGroup {
                    Button("Adicionar", systemImage: "plus") {
                        let entry = Entry(value: newItem)
                        draft.append(entry)
                        selection = entry.id
                    }
                    Button("Remover", systemImage: "minus") { draft.removeAll { $0.id == selection } }
                        .disabled(selection == nil)
                    Button("Subir", systemImage: "arrow.up") { move(-1) }
                    Button("Descer", systemImage: "arrow.down") { move(1) }
                }
                .fixedSize()
                Button("Padrões") { draft = defaults.map { Entry(value: $0) } }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") {
                    items = draft.map(\.value)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .frame(width: 440)
        .onAppear { draft = items.map { Entry(value: $0) } }
    }

    private func move(_ delta: Int) {
        guard let index = draft.firstIndex(where: { $0.id == selection }) else { return }
        let target = index + delta
        guard draft.indices.contains(target) else { return }
        draft.swapAt(index, target)
    }
}
