import AppKit
import HyperImageCore
import SwiftUI

/// Before/after comparison using the current settings. "After" is the actually encoded file, decoded again.
struct ConversionPreviewSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let initial: URL
    @State private var current: URL?
    @State private var result: PreviewResult?
    @State private var error: String?
    /// nil fits the image to the pane; otherwise image pixels per screen point (1 = 1:1).
    @State private var zoom: Double?
    @State private var stacked = false

    var body: some View {
        let url = current ?? initial
        VStack(spacing: 0) {
            HStack {
                Text(url.lastPathComponent).font(.headline).lineLimit(1)
                Spacer()
                Picker("Layout", selection: $stacked) {
                    Image(systemName: "rectangle.split.2x1").tag(false)
                    Image(systemName: "rectangle.split.1x2").tag(true)
                }
                .pickerStyle(.segmented).fixedSize()
                ControlGroup {
                    Button("Ajustar à janela", systemImage: "arrow.down.right.and.arrow.up.left") { zoom = nil }
                        .disabled(zoom == nil)
                    Button("1:1") { zoom = 1 }
                    Button("Reduzir", systemImage: "minus.magnifyingglass") { zoom = ZoomLevels.step(zoom ?? 1, by: -1) }
                    Button("Ampliar", systemImage: "plus.magnifyingglass") { zoom = ZoomLevels.step(zoom ?? 1, by: 1) }
                }
                .fixedSize()
                Text(zoom.map { "\(Int(($0 * 100).rounded())) %" } ?? String(localized: "Ajustado"))
                    .monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 64)
                ControlGroup {
                    Button("Anterior", systemImage: "chevron.left") { step(-1) }
                    Button("Próxima", systemImage: "chevron.right") { step(1) }
                }
                .fixedSize()
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.glass)
            }
            .padding(12)
            Divider()
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 1)) : AnyLayout(HStackLayout(spacing: 1))
            layout {
                pane(title: "Antes", tint: .secondary, image: result?.before, info: result?.beforeInfo)
                pane(title: "Depois", tint: .accentColor, image: result?.after, info: result?.afterInfo)
            }
            .overlay {
                if result == nil && error == nil { ProgressView("Processando…") }
                if let error { ContentUnavailableView("Não foi possível pré-visualizar", systemImage: "exclamationmark.triangle", description: Text(error)) }
            }
        }
        .frame(minWidth: 940, minHeight: 560)
        .task(id: url) { await render(url) }
    }

    private func pane(title: LocalizedStringKey, tint: Color, image: CGImage?, info: String?) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(tint == .secondary ? Color.primary : .white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .glassEffect(tint == .secondary ? .regular : .regular.tint(tint), in: .capsule)
                Spacer()
                Text(info ?? "").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.bar)
            ZoomableImage(image: image, zoom: zoom)
                .opacity(image == nil ? 0 : 1)
                .blur(radius: image == nil ? 12 : 0)
                .animation(.smooth(duration: 0.35), value: image == nil)
        }
    }

    private func step(_ delta: Int) {
        let urls = app.inputs.map(\.url)
        guard let index = urls.firstIndex(of: current ?? initial), !urls.isEmpty else { return }
        result = nil
        error = nil
        current = urls[(index + delta + urls.count) % urls.count]
    }

    private func render(_ url: URL) async {
        let settings = app.state.convert
        do {
            let made = try await Task.detached(priority: .userInitiated) { try PreviewResult.make(url: url, settings: settings) }.value
            guard !Task.isCancelled else { return }
            result = made
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}

nonisolated struct PreviewResult: @unchecked Sendable {
    let before: CGImage
    let after: CGImage
    let beforeInfo: String
    let afterInfo: String

    nonisolated static func make(url: URL, settings: ConvertSettings) throws -> PreviewResult {
        let loaded = try ImageLoader.load(url)
        let pipeline = try ImagePipeline(options: settings.effectiveAdvancedOptions)
        let format = settings.outputFormat(for: url)
        let output = try OutputEncoder.encode(loaded, pipeline: pipeline, settings: settings)
        let data = output.data
        guard let after = decode(data, format: format, pixelSize: output.pixelSize) ?? output.image else {
            throw ImagingError.encodeFailed(format.displayName)
        }
        let sizeText = { (bytes: Int64) in ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        return PreviewResult(
            before: loaded.image, after: after,
            beforeInfo: "\(loaded.image.width) × \(loaded.image.height) · \(sizeText(loaded.fileSize))",
            afterInfo: "\(output.pixelSize.width) × \(output.pixelSize.height) · \(sizeText(Int64(data.count))) · \(format.displayName)")
    }

    nonisolated private static func decode(_ data: Data, format: OutputFormat, pixelSize: PixelSize) -> CGImage? {
        if format == .pdf { return renderPDF(data, pixelSize: pixelSize) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

extension PreviewResult {
    /// Rasterises page 1 at the image's pixel size.
    nonisolated static func renderPDF(_ data: Data, pixelSize: PixelSize) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData), let page = CGPDFDocument(provider)?.page(at: 1),
              let ctx = CGContext(data: nil, width: pixelSize.width, height: pixelSize.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelSize.width, height: pixelSize.height))
        ctx.scaleBy(x: CGFloat(pixelSize.width) / box.width, y: CGFloat(pixelSize.height) / box.height)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }
}

/// Fit-to-window or 1:1 pixels with scrolling.
/// Zoom steps offered by the preview's − / + buttons.
enum ZoomLevels {
    static let all: [Double] = [0.1, 0.25, 0.33, 0.5, 0.67, 1, 1.5, 2, 3, 4, 6, 8]

    static func step(_ current: Double, by direction: Int) -> Double {
        if direction > 0 { return all.first { $0 > current + 0.001 } ?? all.last! }
        return all.last { $0 < current - 0.001 } ?? all.first!
    }
}

struct ZoomableImage: View {
    let image: CGImage?
    let zoom: Double?
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { proxy in
            if let image {
                if let zoom {
                    ScrollView([.horizontal, .vertical]) {
                        Image(decorative: image, scale: scale).resizable()
                            .interpolation(zoom >= 1 ? .none : .high)
                            .frame(width: Double(image.width) * zoom / scale, height: Double(image.height) * zoom / scale)
                    }
                } else {
                    Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .background(CheckerboardBackground())
    }
}

/// Subtle transparency grid, like Preview's: low contrast in both appearances so the image stays the focus.
struct CheckerboardBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 8
            let shade = Color.primary.opacity(scheme == .dark ? 0.045 : 0.05)
            for row in 0...Int(size.height / tile) {
                for col in 0...Int(size.width / tile) where (row + col).isMultiple(of: 2) {
                    ctx.fill(Path(CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)), with: .color(shade))
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
