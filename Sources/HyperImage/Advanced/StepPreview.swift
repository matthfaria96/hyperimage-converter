import AppKit
import HyperImageCore
import SwiftUI

/// Live result of the whole Advanced Options chain on the selected input (or a built-in sample).
struct StepPreview: View {
    let options: AdvancedOptions
    let sourceURL: URL?
    @State private var source: LoadedImage?
    @State private var rendered: CGImage?
    @State private var info = ""
    @State private var error: String?
    @State private var showingOriginal = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                CheckerboardBackground()
                if let image = showingOriginal ? source?.image : rendered {
                    Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit().padding(8)
                } else if error == nil {
                    ProgressView()
                }
                if let error {
                    Text(error).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                }
            }
            .clipShape(.rect(cornerRadius: 10))
            HStack {
                Text(showingOriginal ? "Original" : info).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Text("Segure para ver o original")
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.quaternary, in: .capsule)
                    .onLongPressGesture(minimumDuration: 0, maximumDistance: 50) {} onPressingChanged: { showingOriginal = $0 }
            }
        }
        .task(id: sourceURL) { await loadSource() }
        .task(id: RenderKey(options: options, ready: source != nil)) { await render() }
    }

    private struct RenderKey: Equatable {
        let options: AdvancedOptions
        let ready: Bool
    }

    private func loadSource() async {
        let url = sourceURL
        source = await Task.detached(priority: .userInitiated) { () -> LoadedImage? in
            if let url, let loaded = try? ImageLoader.load(url) { return loaded }
            return SampleImage.make()
        }.value
    }

    private func render() async {
        guard let source else { return }
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        let options = options
        do {
            let output = try await Task.detached(priority: .userInitiated) {
                try ImagePipeline(options: options).process(source).image
            }.value
            guard !Task.isCancelled else { return }
            rendered = output
            info = "\(source.image.width) × \(source.image.height) → \(output.width) × \(output.height)"
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A gradient test card used when the input list is empty.
enum SampleImage {
    nonisolated static func make() -> LoadedImage? {
        let w = 1200, h = 800
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(srgbRed: 0.16, green: 0.36, blue: 0.95, alpha: 1), CGColor(srgbRed: 0.75, green: 0.32, blue: 0.95, alpha: 1)]
        if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: h), options: [])
        }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.fillEllipse(in: CGRect(x: 160, y: 470, width: 180, height: 180))
        ctx.setFillColor(CGColor(srgbRed: 0.35, green: 0.75, blue: 1, alpha: 0.9))
        ctx.move(to: CGPoint(x: 0, y: 0)); ctx.addLine(to: CGPoint(x: 420, y: 430)); ctx.addLine(to: CGPoint(x: 840, y: 0)); ctx.fillPath()
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.95, alpha: 0.9))
        ctx.move(to: CGPoint(x: 500, y: 0)); ctx.addLine(to: CGPoint(x: 900, y: 360)); ctx.addLine(to: CGPoint(x: 1200, y: 0)); ctx.fillPath()
        guard let image = ctx.makeImage() else { return nil }
        return LoadedImage(url: URL(fileURLWithPath: "/Exemplo.jpg"), image: image, properties: .empty, metadata: ImageMetadata(),
                           sourceType: nil, fileSize: 0, modificationDate: Date(), creationDate: nil)
    }
}
