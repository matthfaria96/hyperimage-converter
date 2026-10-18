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
    @State private var actualSize = false
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
                Toggle(isOn: $actualSize) { Text("1:1") }.toggleStyle(.button)
                ControlGroup {
                    Button("Anterior", systemImage: "chevron.left") { step(-1) }
                    Button("Próxima", systemImage: "chevron.right") { step(1) }
                }
                .fixedSize()
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 1)) : AnyLayout(HStackLayout(spacing: 1))
            layout {
                pane(title: "Antes", image: result?.before, info: result?.beforeInfo)
                pane(title: "Depois", image: result?.after, info: result?.afterInfo)
            }
            .overlay {
                if result == nil && error == nil { ProgressView("Processando…") }
                if let error { ContentUnavailableView("Não foi possível pré-visualizar", systemImage: "exclamationmark.triangle", description: Text(error)) }
            }
        }
        .frame(minWidth: 1000, minHeight: 680)
        .task(id: url) { await render(url) }
    }

    private func pane(title: String, image: CGImage?, info: String?) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(info ?? "").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.bar)
            ZoomableImage(image: image, actualSize: actualSize)
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
            result = try await Task.detached(priority: .userInitiated) { try PreviewResult.make(url: url, settings: settings) }.value
            error = nil
        } catch {
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
        let pipeline = try ImagePipeline(options: settings.useAdvancedOptions ? settings.advanced : AdvancedOptions())
        let processed = try pipeline.process(loaded)
        let data = try ImageEncoder.encode(
            .init(image: processed.image, sourceProperties: loaded.properties, sourceJPEGQuality: loaded.metadata.jpegQuality,
                  dpiX: processed.dpiX, dpiY: processed.dpiY),
            format: settings.format, settings: settings.formatSettings)
        let after = decode(data, format: settings.format, pixelSize: PixelSize(width: processed.image.width, height: processed.image.height)) ?? processed.image
        let sizeText = { (bytes: Int64) in ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        return PreviewResult(
            before: loaded.image, after: after,
            beforeInfo: "\(loaded.image.width) × \(loaded.image.height) · \(sizeText(loaded.fileSize))",
            afterInfo: "\(processed.image.width) × \(processed.image.height) · \(sizeText(Int64(data.count))) · \(settings.format.displayName)")
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
struct ZoomableImage: View {
    let image: CGImage?
    let actualSize: Bool
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { proxy in
            if let image {
                if actualSize {
                    ScrollView([.horizontal, .vertical]) {
                        Image(decorative: image, scale: scale).interpolation(.none)
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

struct CheckerboardBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 10
            for row in 0...Int(size.height / tile) {
                for col in 0...Int(size.width / tile) where (row + col).isMultiple(of: 2) {
                    ctx.fill(Path(CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)), with: .color(.gray.opacity(0.12)))
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
