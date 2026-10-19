import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import HyperImageCore

/// Every format × option × awkward input must encode, decode at the right size and keep its colours.
struct FormatSweepTests {
    static func source(_ kind: String) throws -> CGImage {
        let (space, w, h, info): (CGColorSpace, Int, Int, UInt32) = switch kind {
        case "p3": (CGColorSpace(name: CGColorSpace.displayP3)!, 64, 48, CGImageAlphaInfo.premultipliedLast.rawValue)
        case "gray": (CGColorSpaceCreateDeviceGray(), 64, 48, CGImageAlphaInfo.none.rawValue)
        case "tiny": (CGColorSpace(name: CGColorSpace.sRGB)!, 1, 1, CGImageAlphaInfo.premultipliedLast.rawValue)
        case "odd": (CGColorSpace(name: CGColorSpace.sRGB)!, 7, 3, CGImageAlphaInfo.premultipliedLast.rawValue)
        default: (CGColorSpace(name: CGColorSpace.sRGB)!, 64, 48, CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
        for x in 0..<w { for y in 0..<h {
            let comps: [CGFloat] = space.numberOfComponents == 1 ? [CGFloat(x) / CGFloat(w), 1] : [CGFloat(x) / CGFloat(w), CGFloat(y) / CGFloat(h), 0.5, kind == "alpha" && x < w / 2 ? 0 : 1]
            ctx.setFillColor(CGColor(colorSpace: space, components: comps)!)
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        } }
        return ctx.makeImage()!
    }

    static var variants: [(String, OutputFormat, (inout FormatSettings) -> Void)] {
        var v: [(String, OutputFormat, (inout FormatSettings) -> Void)] = []
        for f in OutputFormat.allCases { v.append(("\(f)", f, { _ in })) }
        for c in PaletteSize.allCases {
            v.append(("bmp-\(c)", .bmp, { $0.bmp.colors = c }))
            v.append(("png-\(c)", .png, { $0.png.colors = c }))
            if c != .trueColor {
                v.append(("gif-\(c)", .gif, { $0.gif.colors = c }))
                v.append(("gifT-\(c)", .gif, { $0.gif.colors = c; $0.gif.transparent = true }))
            }
        }
        for comp in TIFFCompression.allCases { for ph in TIFFPhotometric.allCases {
            v.append(("tiff-\(comp)-\(ph)", .tiff, { $0.tiff.compression = comp; $0.tiff.photometric = ph }))
        } }
        for q in PDFQuality.allCases { v.append(("pdf-\(q)", .pdf, { $0.pdf.quality = q })) }
        for ph in JPEGPhotometric.allCases { v.append(("jpeg-\(ph)", .jpeg, { $0.jpeg.photometric = ph })) }
        v.append(("jp2-gray", .jpeg2000, { $0.jpeg2000.photometric = .grayscale }))
        v.append(("png-interlaced", .png, { $0.png.interlaced = true }))
        v.append(("webp-lossless", .webp, { $0.webp.lossless = true }))
        return v
    }

    @Test func everyVariantRoundTrips() throws {
        var failures: [String] = []
        for kind in ["srgb", "alpha", "p3", "gray", "tiny", "odd"] {
            let img = try Self.source(kind)
            for (name, format, configure) in Self.variants {
                var s = FormatSettings(); configure(&s)
                do {
                    let data = try ImageEncoder.encode(.init(image: img, sourceProperties: ImageProperties(raw: [:]), sourceJPEGQuality: nil, dpiX: 96, dpiY: 96), format: format, settings: s)
                    if format == .pdf { if data.prefix(4) != Data("%PDF".utf8) { failures.append("\(kind) \(name): not PDF") }; continue }
                    guard let src = CGImageSourceCreateWithData(data as CFData, nil), let out = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                        failures.append("\(kind) \(name): undecodable (\(data.count) bytes)"); continue
                    }
                    if out.width != img.width || out.height != img.height { failures.append("\(kind) \(name): size \(out.width)x\(out.height)") }
                    // colour sanity: centre pixel of colour-preserving outputs should be close to source
                    let a = try Fixtures.rgba(img, x: img.width - 1, y: img.height / 2), b = try Fixtures.rgba(out, x: img.width - 1, y: img.height / 2)
                    let lossy = name.contains("gray") || name.contains("blackWhite") || name.contains("c4") || name.contains("c8") || name.contains("Fax") || name.contains("cmyk") || kind == "gray" || (img.width < 16 && (format == .heic || format == .avif))
                    if !lossy && a[3] == 255, (0..<3).contains(where: { abs(Int(a[$0]) - Int(b[$0])) > 40 }) {
                        failures.append("\(kind) \(name): colour \(a) -> \(b)")
                    }
                } catch {
                    failures.append("\(kind) \(name): threw \(error)")
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }
}
