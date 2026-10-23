import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import HyperImageCore

struct EncoderTests {
    func encode(_ format: OutputFormat, _ configure: (inout FormatSettings) -> Void = { _ in }) throws -> (Data, LoadedImage) {
        let loaded = try Fixtures.landscape()
        var settings = FormatSettings()
        configure(&settings)
        let input = ImageEncoder.Input(image: loaded.image, sourceProperties: loaded.properties,
                                       sourceJPEGQuality: loaded.metadata.jpegQuality, dpiX: 150, dpiY: 150)
        return (try ImageEncoder.encode(input, format: format, settings: settings), loaded)
    }

    func decoded(_ data: Data) throws -> (CGImage, [CFString: Any], String?) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        return (image, props, CGImageSourceGetType(source) as String?)
    }

    @Test(arguments: OutputFormat.allCases.filter { $0 != .pdf })
    func formatRoundTrips(format: OutputFormat) throws {
        let (data, _) = try encode(format)
        let (image, _, type) = try decoded(data)
        #expect(image.pixelSize == PixelSize(width: 1200, height: 800))
        #expect(type == format.utType.identifier)
    }

    @Test func webpLosslessIsExact() throws {
        let (data, loaded) = try encode(.webp) { $0.webp.lossless = true }
        let (image, _, _) = try decoded(data)
        #expect(try Fixtures.rgba(image, x: 600, y: 400) == Fixtures.rgba(loaded.image, x: 600, y: 400))
    }

    @Test func jpegQualityAffectsSize() throws {
        let (low, _) = try encode(.jpeg) { $0.jpeg.quality = 20 }
        let (high, _) = try encode(.jpeg) { $0.jpeg.quality = 95 }
        #expect(low.count < high.count)
        let lowQ = try #require(JPEGQualityEstimator.estimate(data: low))
        let highQ = try #require(JPEGQualityEstimator.estimate(data: high))
        #expect(lowQ < highQ)
        #expect(JPEGQualityEstimator.quality(for: JPEGQualityEstimator.standardLuminance) == 50)
    }

    @Test func dpiIsWritten() throws {
        let (data, _) = try encode(.png)
        let (_, props, _) = try decoded(data)
        #expect((props[kCGImagePropertyDPIWidth] as? Double).map { abs($0 - 150) < 1 } == true)
    }

    @Test func grayscaleJPEG() throws {
        let (data, _) = try encode(.jpeg) { $0.jpeg.photometric = .grayscale }
        let (_, props, _) = try decoded(data)
        #expect(props[kCGImagePropertyColorModel] as? String == "Gray")
    }

    @Test func gifRespectsColorCount() throws {
        let (data, _) = try encode(.gif) { $0.gif.colors = .c8 }
        let (image, _, _) = try decoded(data)
        let bitmap = try Bitmap(image: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let colors = Set(stride(from: 0, to: bitmap.pixels.count, by: 4).map {
            UInt32(bitmap.pixels[$0]) << 16 | UInt32(bitmap.pixels[$0 + 1]) << 8 | UInt32(bitmap.pixels[$0 + 2])
        })
        #expect(colors.count <= 8)
    }

    @Test(arguments: [PaletteSize.c256, .blackWhite])
    func indexedPNG(colors: PaletteSize) throws {
        let (data, _) = try encode(.png) { $0.png.colors = colors }
        let (image, _, _) = try decoded(data)
        #expect(image.pixelSize == PixelSize(width: 1200, height: 800))
        let (full, _) = try encode(.png)
        #expect(data.count < full.count)
    }

    @Test func pdfPageMatchesDPI() throws {
        let (data, _) = try encode(.pdf)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let page = try #require(CGPDFDocument(provider)?.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        #expect(abs(box.width - 1200 * 72 / 150) < 0.5)
        #expect(abs(box.height - 800 * 72 / 150) < 0.5)
    }

    @Test(arguments: TIFFCompression.allCases)
    func tiffCompressions(compression: TIFFCompression) throws {
        let (data, _) = try encode(.tiff) { $0.tiff.compression = compression }
        let (_, props, _) = try decoded(data)
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFCompression] as? Int == compression.tagValue)
    }

    @Test func faxCompressionStoresBlackAndWhite() throws {
        let (data, _) = try encode(.tiff) { $0.tiff.compression = .g4Fax }
        let (image, _, _) = try decoded(data)
        let bitmap = try Bitmap(image: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let levels = Set(stride(from: 0, to: bitmap.pixels.count, by: 4).map { bitmap.pixels[$0] })
        #expect(levels.isSubset(of: [0, 255]))
    }

    @Test func pngFilterChangesEncoding() throws {
        let (none, _) = try encode(.png) { $0.png.filter = .none }
        let (paeth, _) = try encode(.png) { $0.png.filter = .paeth }
        #expect(paeth.count != none.count)
        let legacy = try JSONDecoder().decode(PNGSettings.self, from: Data(#"{"colors":256,"interlaced":true}"#.utf8))
        #expect(legacy.colors == .c256 && legacy.interlaced && legacy.filter == .adaptive)
    }
}

struct BatchConverterTests {
    @Test func convertsAndKeepsDates() async throws {
        let dir = try TemporaryDirectory()
        let input = dir.url.appendingPathComponent("in", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        let files = try ["paisagem", "retrato"].map { name -> URL in
            let dest = input.appendingPathComponent("\(name).jpg")
            try FileManager.default.copyItem(at: Fixtures.url(name), to: dest)
            return dest
        }
        let old = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: files[0].path)

        var settings = ConvertSettings()
        settings.format = .webp
        settings.outputFolder = dir.url.appendingPathComponent("out").path
        settings.useAdvancedOptions = true
        settings.advanced.resize.enabled = true
        settings.advanced.resize.mode = .percentage

        let converter = BatchConverter(settings: settings)
        let records = converter.records(for: files.map { InputItem(url: $0) })
        #expect(records.map(\.output.lastPathComponent) == ["paisagem.webp", "retrato.webp"])

        let results = ResultBox()
        try await converter.run(records, askOverwrite: { _ in .yes }, update: { await results.add($0) })
        let done = await results.items.sorted { $0.id < $1.id }
        #expect(done.map(\.status) == [.done, .done])
        #expect(ImageLoader.pixelSize(records[0].output) == PixelSize(width: 600, height: 400))
        let modified = try records[0].output.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(modified == old)

        // Second run: everything exists, "No to All" skips both.
        let again = ResultBox()
        try await converter.run(records, askOverwrite: { _ in .noToAll }, update: { await again.add($0) })
        #expect(await again.items.map(\.status) == [.skipped, .skipped])
    }

    @Test func keepsFolderStructure() throws {
        var settings = ConvertSettings()
        settings.outputFolder = "/out"
        let items = [InputItem(url: URL(fileURLWithPath: "/src/Album/sub/a.png"), relativeDirectory: "Album/sub"),
                     InputItem(url: URL(fileURLWithPath: "/elsewhere/a.png"))]
        let out = OutputPlanner.destinations(for: items, settings: settings)
        #expect(out.map(\.path) == ["/out/Album/sub/a.jpg", "/out/a.jpg"])
        settings.keepFolderStructure = false
        settings.uppercaseExtension = true
        let flat = OutputPlanner.destinations(for: items, settings: settings)
        #expect(flat.map(\.path) == ["/out/a.JPG", "/out/a-2.JPG"])
    }

    @Test func failureIsReportedPerFile() async throws {
        let dir = try TemporaryDirectory()
        let bogus = dir.url.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: bogus)
        var settings = ConvertSettings()
        settings.outputFolder = dir.url.appendingPathComponent("out").path
        let converter = BatchConverter(settings: settings)
        let box = ResultBox()
        try await converter.run(converter.records(for: [InputItem(url: bogus)]), askOverwrite: { _ in .yes }, update: { await box.add($0) })
        guard case .failed = await box.items.first?.status else {
            Issue.record("expected failure")
            return
        }
    }
}

actor ResultBox {
    var items: [ConversionRecord] = []
    func add(_ record: ConversionRecord) { items.append(record) }
}

struct OutputSafetyTests {
    private func renameSettings(_ template: String, start: Int = 1) -> ConvertSettings {
        var s = ConvertSettings()
        s.outputFolder = "/out"
        s.rename = true
        s.renameTemplate = template
        s.renameStartNumber = start
        return s
    }

    private let pair = [InputItem(url: URL(fileURLWithPath: "/f/a.png")), InputItem(url: URL(fileURLWithPath: "/f/b.png"))]

    @Test func templateNamesOutputs() {
        let out = OutputPlanner.destinations(for: pair, settings: renameSettings("Foto###", start: 5))
        #expect(out.map(\.path) == ["/out/Foto005.jpg", "/out/Foto006.jpg"])
    }

    @Test func templateWinsOverSuffix() {
        var s = renameSettings("Foto###", start: 5)
        s.addSuffix = true
        let out = OutputPlanner.destinations(for: pair, settings: s)
        #expect(out.map(\.path) == ["/out/Foto005.jpg", "/out/Foto006.jpg"])
    }

    @Test func templateCollisionGetsCounter() {
        let out = OutputPlanner.destinations(for: pair, settings: renameSettings("x"))
        #expect(out.map(\.path) == ["/out/x.jpg", "/out/x-2.jpg"])
    }

    @Test func templateNeverOverwritesInput() {
        var s = renameSettings("x")
        s.useOutputFolder = false
        let items = [InputItem(url: URL(fileURLWithPath: "/f/x.jpg")), InputItem(url: URL(fileURLWithPath: "/f/y.jpg"))]
        let out = OutputPlanner.destinations(for: items, settings: s)
        #expect(out.map(\.path) == ["/f/x-2.jpg", "/f/x-3.jpg"])
    }

    @Test func inPlaceTemplateSkipsUnrelatedFilesOnDisk() {
        var s = renameSettings("Image#")
        s.useOutputFolder = false
        s.askBeforeOverwrite = false
        s.skipExisting = false
        let onDisk: Set<String> = ["/f/Image1.jpg", "/f/Image1-2.jpg"]
        let out = OutputPlanner.destinations(for: [InputItem(url: URL(fileURLWithPath: "/f/a.png"))], settings: s,
                                             exists: { onDisk.contains($0.path) })
        #expect(out.map(\.path) == ["/f/Image1-3.jpg"])
    }

    @Test func inPlaceTemplateKeepsPlainNameWhenSkipping() {
        var s = renameSettings("Image#####")
        s.useOutputFolder = false
        s.skipExisting = true
        s.askBeforeOverwrite = false
        let out = OutputPlanner.destinations(for: pair, settings: s, exists: { _ in true })
        #expect(out.map(\.path) == ["/f/Image00001.jpg", "/f/Image00002.jpg"])
    }

    @Test func inPlaceTemplateKeepsPlainNameWhenAsking() {
        var s = renameSettings("Image#####")
        s.useOutputFolder = false
        s.skipExisting = false
        s.askBeforeOverwrite = true
        let out = OutputPlanner.destinations(for: pair, settings: s, exists: { _ in true })
        #expect(out.map(\.path) == ["/f/Image00001.jpg", "/f/Image00002.jpg"])
    }

    @Test func plannerStopsWhenCancelled() {
        var checks = 0
        let out = OutputPlanner.destinations(for: pair, settings: renameSettings("Foto#"),
                                             isCancelled: { checks += 1; return checks > 1 })
        #expect(out.map(\.path) == ["/out/Foto1.jpg"])
    }

    @Test func cancellableRecordsThrowWhenCancelled() async {
        let converter = BatchConverter(settings: renameSettings("Foto#"))
        let items = pair
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try converter.cancellableRecords(for: items)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func outputFolderTemplateStillAsksAboutExistingFiles() {
        let out = OutputPlanner.destinations(for: pair, settings: renameSettings("Foto#"), exists: { _ in true })
        #expect(out.map(\.path) == ["/out/Foto1.jpg", "/out/Foto2.jpg"])
    }

    @Test func renameOffKeepsOldNames() {
        var s = renameSettings("Foto###")
        s.rename = false
        let out = OutputPlanner.destinations(for: pair, settings: s)
        #expect(out.map(\.path) == ["/out/a.jpg", "/out/b.jpg"])
    }

    @Test func outputNeverLandsOnAnotherInput() {
        var settings = ConvertSettings()
        settings.useOutputFolder = false
        let items = [InputItem(url: URL(fileURLWithPath: "/f/x.png")), InputItem(url: URL(fileURLWithPath: "/f/x.jpg"))]
        let out = OutputPlanner.destinations(for: items, settings: settings)
        #expect(out.map(\.path) == ["/f/x-2.jpg", "/f/x-3.jpg"])
    }

    @Test func virtualFoldersBecomeSubfolders() {
        var settings = ConvertSettings()
        settings.outputFolder = "/out"
        let items = [InputItem(url: URL(fileURLWithPath: "/src/Album/a.png"), relativeDirectory: "Album", virtualFolder: "Praia"),
                     InputItem(url: URL(fileURLWithPath: "/src/b.png")).inFolder("Praia"),
                     InputItem(url: URL(fileURLWithPath: "/src/c.png"))]
        let out = OutputPlanner.destinations(for: items, settings: settings)
        #expect(out.map(\.path) == ["/out/Praia/a.jpg", "/out/Praia/b.jpg", "/out/c.jpg"])
        settings.useOutputFolder = false
        let beside = OutputPlanner.destinations(for: items, settings: settings)
        #expect(beside.map(\.path) == ["/src/Album/Praia/a.jpg", "/src/Praia/b.jpg", "/src/c.jpg"])
    }

    @Test(arguments: [("  Férias 2026 ", "Férias 2026"), ("", nil), ("..", nil), ("a/b", nil), ("a:b", nil), (".", nil)])
    func folderNamesAreValidated(raw: String, expected: String?) {
        #expect(InputItem.folderName(raw) == expected)
    }
}
