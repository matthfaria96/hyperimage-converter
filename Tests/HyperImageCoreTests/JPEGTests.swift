import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import HyperImageCore

/// libjpeg-backed JPEG options and the lossless crop.
struct JPEGTests {
    func encode(properties: [CFString: Any] = [:], _ configure: (inout JPEGSettings) -> Void = { _ in }) throws -> Data {
        let loaded = try Fixtures.landscape()
        var settings = FormatSettings()
        configure(&settings.jpeg)
        let input = ImageEncoder.Input(image: loaded.image, sourceProperties: ImageProperties(raw: properties),
                                       sourceJPEGQuality: nil, dpiX: 150, dpiY: 150)
        return try ImageEncoder.encode(input, format: .jpeg, settings: settings)
    }

    func properties(_ data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    func image(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Luma (first component) sampling factors from the SOF marker, e.g. 0x22 for 4:2:0.
    func lumaSampling(_ data: Data) -> UInt8? {
        let b = [UInt8](data)
        var i = 2
        while i + 4 < b.count, b[i] == 0xFF {
            let marker = b[i + 1], length = Int(b[i + 2]) << 8 | Int(b[i + 3])
            if (0xC0...0xC2).contains(marker) { return b[i + 11] }
            i += 2 + length
        }
        return nil
    }

    @Test(arguments: [(JPEGSubsampling.none, UInt8(0x11)), (.medium, 0x21), (.high, 0x22)])
    func subsamplingIsWritten(subsampling: JPEGSubsampling, factors: UInt8) throws {
        let data = try encode { $0.subsampling = subsampling }
        #expect(lumaSampling(data) == factors)
    }

    @Test func subsamplingShrinksFile() throws {
        let full = try encode { $0.subsampling = .none }
        let high = try encode { $0.subsampling = .high }
        #expect(high.count < full.count)
    }

    @Test func huffmanOptimisationShrinksFile() throws {
        let plain = try encode { $0.optimizeHuffman = false }
        let optimised = try encode { $0.optimizeHuffman = true }
        #expect(optimised.count < plain.count)
    }

    @Test func smoothingChangesOutput() throws {
        let sharp = try encode { $0.smoothing = 0 }
        let smooth = try encode { $0.smoothing = 60 }
        #expect(sharp != smooth)
        #expect(smooth.count < sharp.count)
    }

    @Test func qualityUsesIJGScale() throws {
        let data = try encode { $0.quality = 75 }
        #expect(JPEGQualityEstimator.estimate(data: data) == 75)
    }

    @Test func densityAndProfileAreWritten() throws {
        let props = try properties(try encode())
        #expect((props[kCGImagePropertyDPIWidth] as? Double).map { abs($0 - 150) < 1 } == true)
        #expect((props[kCGImagePropertyProfileName] as? String)?.contains("sRGB") == true)
    }

    @Test(arguments: [JPEGPhotometric.rgb, .grayscale, .ycbcr, .cmyk])
    func photometricVariantsDecode(photometric: JPEGPhotometric) throws {
        let data = try encode { $0.photometric = photometric }
        #expect(try image(data).pixelSize == PixelSize(width: 1200, height: 800))
    }

    @Test func rgbStorageKeepsColours() throws {
        let loaded = try Fixtures.landscape()
        let decoded = try image(try encode { $0.photometric = .rgb; $0.quality = 95 })
        let a = try Fixtures.rgba(decoded, x: 600, y: 400), b = try Fixtures.rgba(loaded.image, x: 600, y: 400)
        #expect(zip(a, b).allSatisfy { abs(Int($0) - Int($1)) <= 12 })
    }

    @Test func metadataIsCarriedOrDropped() throws {
        let exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: "2024:05:01 10:20:30"]
        let tiff: [CFString: Any] = [kCGImagePropertyTIFFMake: "TestCam"]
        let source = [kCGImagePropertyExifDictionary: exif, kCGImagePropertyTIFFDictionary: tiff] as [CFString: Any]

        let kept = try properties(try encode(properties: source) { $0.keepMetadata = true })
        let keptTIFF = kept[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let keptEXIF = kept[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(keptTIFF?[kCGImagePropertyTIFFMake] as? String == "TestCam")
        #expect(keptEXIF?[kCGImagePropertyExifDateTimeOriginal] as? String == "2024:05:01 10:20:30")

        let dropped = try properties(try encode(properties: source) { $0.keepMetadata = false })
        #expect((dropped[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] == nil)
    }

    /// APP markers (code, first bytes) before the first scan.
    func markers(_ data: Data) -> [(UInt8, [UInt8])] {
        let b = [UInt8](data)
        var i = 2, out: [(UInt8, [UInt8])] = []
        while i + 4 < b.count, b[i] == 0xFF, b[i + 1] != 0xDA {
            let length = Int(b[i + 2]) << 8 | Int(b[i + 3])
            out.append((b[i + 1], Array(b[(i + 4)..<min(b.count, i + 4 + 12)])))
            i += 2 + length
        }
        return out
    }

    func hasMarker(_ data: Data, _ code: UInt8, _ tag: String) -> Bool {
        markers(data).contains { $0.0 == code && $0.1.starts(with: Array(tag.utf8)) }
    }

    @Test func rgbStorageHasNoJFIF() throws {
        let data = try encode { $0.photometric = .rgb }
        #expect(!hasMarker(data, 0xE0, "JFIF"))
        #expect(hasMarker(data, 0xEE, "Adobe"))
        #expect(hasMarker(try encode(), 0xE0, "JFIF"))
    }

    @Test func dpiAndProfileSurviveMetadataCopy() throws {
        let tiff: [CFString: Any] = [kCGImagePropertyTIFFMake: "TestCam", kCGImagePropertyTIFFXResolution: 300,
                                     kCGImagePropertyTIFFYResolution: 300, kCGImagePropertyTIFFResolutionUnit: 2]
        let data = try encode(properties: [kCGImagePropertyTIFFDictionary: tiff])
        let props = try properties(data)
        #expect((props[kCGImagePropertyDPIWidth] as? Double).map { abs($0 - 150) < 1 } == true)
        #expect((props[kCGImagePropertyProfileName] as? String)?.contains("sRGB") == true)
        #expect(hasMarker(data, 0xE2, "ICC_PROFILE"))
    }

    @Test func iptcIsCarried() throws {
        let iptc: [CFString: Any] = [kCGImagePropertyIPTCCaptionAbstract: "Praia ao entardecer",
                                     kCGImagePropertyIPTCKeywords: ["praia", "sol"]]
        let props = try properties(try encode(properties: [kCGImagePropertyIPTCDictionary: iptc]))
        let read = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        #expect(read?[kCGImagePropertyIPTCCaptionAbstract] as? String == "Praia ao entardecer")
    }

    @Test func wideGamutKeepsItsProfile() throws {
        let loaded = try Fixtures.landscape()
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let converted = try #require(loaded.image.copy(colorSpace: p3))
        let input = ImageEncoder.Input(image: converted, sourceProperties: .empty, sourceJPEGQuality: nil, dpiX: 72, dpiY: 72)
        let data = try ImageEncoder.encode(input, format: .jpeg, settings: FormatSettings())
        #expect((try properties(data)[kCGImagePropertyProfileName] as? String)?.contains("P3") == true)
    }

    @Test func legacySettingsDecodeWithDefaults() throws {
        let json = Data(#"{"quality":80,"useOriginalQuality":false,"photometric":"noChange","progressive":true,"keepMetadata":true}"#.utf8)
        let settings = try JSONDecoder().decode(JPEGSettings.self, from: json)
        #expect(settings.quality == 80 && settings.progressive)
        #expect(settings.subsampling == .high && settings.smoothing == 0 && settings.optimizeHuffman)
    }

    // MARK: Lossless crop

    func cropPipeline(_ configure: (inout AdvancedOptions) -> Void = { _ in }) throws -> ImagePipeline {
        var options = AdvancedOptions()
        options.crop.enabled = true
        configure(&options)
        return try ImagePipeline(options: options)
    }

    @Test func centredCropIsLossless() throws {
        let loaded = try Fixtures.landscape()
        let output = try cropPipeline().encode(loaded, format: .jpeg, settings: FormatSettings())
        #expect(output.image == nil)
        #expect(output.pixelSize == PixelSize(width: 640, height: 480))
        let decoded = try image(output.data)
        #expect(decoded.pixelSize == PixelSize(width: 640, height: 480))
        // Same DCT blocks: the centre decodes to the source's pixels at the snapped offset (288, 160).
        let source = try Bitmap(image: loaded.image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let cropped = try Bitmap(image: decoded, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        var worst = 0
        for y in stride(from: 16, to: 464, by: 7) {
            for x in stride(from: 16, to: 624, by: 7) {
                let s = ((y + 160) * source.width + x + 288) * 4, c = (y * cropped.width + x) * 4
                for k in 0..<3 { worst = max(worst, abs(Int(source.pixels[s + k]) - Int(cropped.pixels[c + k]))) }
            }
        }
        #expect(worst <= 1)
        #expect(JPEGQualityEstimator.estimate(data: output.data) == loaded.metadata.jpegQuality)
    }

    @Test func losslessCropKeepsProfileAndHonoursProgressive() throws {
        let loaded = try Fixtures.landscape()
        let sourceHasICC = hasMarker(try Data(contentsOf: loaded.url), 0xE2, "ICC_PROFILE")
        var settings = FormatSettings()
        settings.jpeg.keepMetadata = false
        settings.jpeg.progressive = true
        let output = try cropPipeline().encode(loaded, format: .jpeg, settings: settings)
        #expect(output.image == nil)
        #expect(hasMarker(output.data, 0xE2, "ICC_PROFILE") == sourceHasICC)
        #expect([UInt8](output.data).indices.dropLast().contains { output.data[$0] == 0xFF && output.data[$0 + 1] == 0xC2 })
        #expect((try properties(output.data)[kCGImagePropertyDPIWidth] as? Double) == loaded.metadata.dpiX)
    }

    @Test func unalignedOriginFallsBackToReencoding() throws {
        let loaded = try Fixtures.landscape()
        let pipeline = try cropPipeline { $0.crop.useOrigin = true; $0.crop.originX = 5; $0.crop.originY = 3 }
        let output = try pipeline.encode(loaded, format: .jpeg, settings: FormatSettings())
        #expect(output.image != nil)
        #expect(try image(output.data).pixelSize == PixelSize(width: 640, height: 480))
    }

    @Test func otherStepsDisableLosslessCrop() throws {
        let loaded = try Fixtures.landscape()
        let settings = FormatSettings()
        #expect(try cropPipeline().losslessCropRect(loaded, format: .jpeg, settings: settings.jpeg) != nil)
        #expect(try cropPipeline { $0.border.enabled = true }.losslessCropRect(loaded, format: .jpeg, settings: settings.jpeg) == nil)
        #expect(try cropPipeline { $0.crop.losslessJPEG = false }.losslessCropRect(loaded, format: .jpeg, settings: settings.jpeg) == nil)
        #expect(try cropPipeline().losslessCropRect(loaded, format: .png, settings: settings.jpeg) == nil)
        var gray = settings.jpeg
        gray.photometric = .grayscale
        #expect(try cropPipeline().losslessCropRect(loaded, format: .jpeg, settings: gray) == nil)
    }

    @Test func corruptJPEGFailsCleanly() throws {
        let rect = PixelRect(x: 0, y: 0, width: 16, height: 16)
        #expect(throws: ImagingError.self) {
            _ = try LibJPEG.losslessCrop(Data([0xFF, 0xD8, 0xFF, 0x00, 0x01]), rect: rect, keepMarkers: true, progressive: false, dpiX: 0, dpiY: 0)
        }
    }
}
