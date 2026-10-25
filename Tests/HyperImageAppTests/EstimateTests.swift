import Foundation
import ImageIO
@testable import HyperImageCore
import Testing
@testable import HyperImage
import UniformTypeIdentifiers

/// The summary's size estimate must follow the whole list, not just the files that happen to come first.
@Suite(.serialized)
struct EstimateTests {
    /// Writes the fixture again as an uncompressed TIFF: a large file that Comprimir shrinks a lot.
    private func uncompressedTIFF(from jpeg: URL, to target: URL) throws {
        let source = try #require(CGImageSourceCreateWithURL(jpeg as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let destination = try #require(CGImageDestinationCreateWithURL(target as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        let properties = [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 1]] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// Encodes every file the way the batch would and adds the sizes up.
    private func actualTotal(_ urls: [URL], settings: ConvertSettings) throws -> Int64 {
        let pipeline = try ImagePipeline(options: settings.effectiveAdvancedOptions)
        return try urls.reduce(Int64(0)) { sum, url in
            let output = try OutputEncoder.encode(try ImageLoader.load(url), pipeline: pipeline, settings: settings)
            return sum + Int64(output.data.count)
        }
    }

    @Test func compressEstimateCoversFormatsAfterTheFirstThreeFiles() throws {
        let ws = try Workspace()
        let folder = ws.images[0].deletingLastPathComponent()
        // Three small JPEGs first, then one large TIFF that dominates the total.
        var urls: [URL] = []
        for index in 1...3 {
            let copy = folder.appendingPathComponent("foto-\(index).jpg")
            try FileManager.default.copyItem(at: ws.images[index % 2], to: copy)
            urls.append(copy)
        }
        let tiff = folder.appendingPathComponent("digitalizada.tif")
        try uncompressedTIFF(from: ws.images[0], to: tiff)
        urls.append(tiff)

        var settings = ConvertSettings()
        settings.mode = .compress
        let estimate = Estimate.make(urls: urls, settings: settings)
        let bytes = try #require(estimate.bytes)
        let actual = try actualTotal(urls, settings: settings)
        let error = abs(Double(bytes - actual)) / Double(actual)
        #expect(error < 0.15, "estimated \(bytes) bytes, the batch writes \(actual) (\(Int(error * 100)) % off)")
    }

    @Test func estimateOfASingleFormatMatchesTheBatch() throws {
        let ws = try Workspace()
        var settings = ConvertSettings()
        settings.mode = .compress
        let estimate = Estimate.make(urls: ws.images, settings: settings)
        let bytes = try #require(estimate.bytes)
        let actual = try actualTotal(ws.images, settings: settings)
        #expect(abs(Double(bytes - actual)) / Double(actual) < 0.25)
        #expect(estimate.originalBytes == ws.images.reduce(Int64(0)) { $0 + BatchConverter.fileSize($1) })
    }
}
