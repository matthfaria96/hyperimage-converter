import HyperImageCore
import SwiftUI

struct IntField: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...100_000
    var suffix = ""

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("", value: $value, format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                Stepper("", value: $value, in: range).labelsHidden()
                if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
            }
        }
        .onChange(of: value) { _, v in value = min(range.upperBound, max(range.lowerBound, v)) }
    }
}

struct DecimalField: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    var step = 0.1
    var range: ClosedRange<Double> = 0...100_000
    var suffix = ""

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("", value: $value, format: .number.precision(.fractionLength(0...2)))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                Stepper("", value: $value, in: range, step: step).labelsHidden()
                if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Slider + numeric field + reset button, as in the original's "Design and Preview".
struct AdjustmentSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var neutral = 0.0
    var decimals = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                TextField("", value: $value, format: .number.precision(.fractionLength(decimals)))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Button("Zerar", systemImage: "xmark.circle.fill") { value = neutral }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .opacity(value == neutral ? 0.3 : 1)
            }
            Slider(value: $value, in: range)
                .onChange(of: value) { _, v in
                    let factor = pow(10, Double(decimals))
                    let rounded = (min(range.upperBound, max(range.lowerBound, v)) * factor).rounded() / factor
                    if rounded != v { value = rounded }
                }
        }
    }
}

struct ColorRow: View {
    let title: LocalizedStringKey
    @Binding var color: RGBAColor
    var supportsOpacity = false

    var body: some View {
        ColorPicker(title, selection: Binding(get: { color.cgColor }, set: { color = RGBAColor(cgColor: $0) }), supportsOpacity: supportsOpacity)
    }
}

/// 3×3 grid; the four middle-edge cells the original lacks are disabled.
struct PositionPicker: View {
    @Binding var position: OverlayPosition

    private let grid: [[OverlayPosition?]] = [
        [.topLeft, .topCenter, .topRight],
        [nil, .center, nil],
        [.bottomLeft, .bottomCenter, .bottomRight],
    ]

    var body: some View {
        LabeledContent("Posição") {
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { col in
                            let cell = grid[row][col]
                            Button {
                                if let cell { position = cell }
                            } label: {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(cell == position ? Color.accentColor : Color.secondary.opacity(cell == nil ? 0.08 : 0.25))
                                    .frame(width: 22, height: 16)
                            }
                            .buttonStyle(.plain)
                            .disabled(cell == nil)
                        }
                    }
                }
            }
        }
    }
}

struct StandardSizeMenu: View {
    let sizes: [PixelSize]
    var editList: (() -> Void)?
    let pick: (PixelSize) -> Void

    var body: some View {
        Menu("Tamanhos padrão") {
            ForEach(sizes, id: \.self) { size in Button(size.description) { pick(size) } }
            if let screen = NSScreen.main {
                Divider()
                let frame = screen.frame
                let px = PixelSize(width: Int(frame.width * screen.backingScaleFactor), height: Int(frame.height * screen.backingScaleFactor))
                Button("Tamanho da tela (\(px.description))") { pick(px) }
            }
            if let editList {
                Divider()
                Button("Editar Lista…", action: editList)
            }
        }
        .fixedSize()
    }
}
