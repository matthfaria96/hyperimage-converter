import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import HyperImageCore

final class ConcurrencyBudgetTests: XCTestCase {
    private let gib: UInt64 = 1 << 30
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ConcurrencyBudget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writePNG(width: Int, height: Int, name: String) throws -> URL {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        let image = try XCTUnwrap(ctx.makeImage())
        let url = dir.appendingPathComponent(name)
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    // MARK: policy

    func testSmallImagesKeepBase() {
        XCTAssertEqual(ConcurrencyBudget.workers(pixelCounts: Array(repeating: 1_000_000, count: 20), base: 6, physicalMemory: 16 * gib), 6)
    }

    func testAboveHardLimitForcesOneWorker() {
        XCTAssertEqual(ConcurrencyBudget.workers(pixelCounts: [1_000, 40_000_001, 2_000], base: 6, physicalMemory: 64 * gib), 1)
    }

    func testMidSizeShrinksByMemory() {
        XCTAssertEqual(ConcurrencyBudget.workers(pixelCounts: Array(repeating: 24_000_000, count: 10), base: 6, physicalMemory: 8 * gib), 5)
        XCTAssertEqual(ConcurrencyBudget.workers(pixelCounts: Array(repeating: 30_000_000, count: 10), base: 6, physicalMemory: 4 * gib), 2)
    }

    func testClampedBetweenOneAndBase() {
        XCTAssertEqual(ConcurrencyBudget.workers(pixelCounts: [30_000_000], base: 6, physicalMemory: 1 << 20), 1)
        XCTAssertEqual(ConcurrencyBudget.workers(pixelCounts: [100], base: 6, physicalMemory: 1024 * gib), 6)
        XCTAssertEqual(ConcurrencyBudget.workers(pixelCounts: [100], base: 1, physicalMemory: 16 * gib), 1)
        XCTAssertEqual(ConcurrencyBudget.workers(pixelCounts: [100], base: 0, physicalMemory: 16 * gib), 1)
    }

    func testUnknownAndEmptyCountsKeepBase() {
        XCTAssertEqual(ConcurrencyBudget.workers(pixelCounts: [nil, nil], base: 4, physicalMemory: 1 << 20), 4)
        XCTAssertEqual(ConcurrencyBudget.workers(pixelCounts: [], base: 4, physicalMemory: 16 * gib), 4)
    }

    // MARK: header reading

    func testPixelCountReadsHeader() throws {
        let url = try writePNG(width: 300, height: 200, name: "a.png")
        XCTAssertEqual(ConcurrencyBudget.pixelCount(of: url), 60_000)
    }

    func testPixelCountNilForNonImage() throws {
        let url = dir.appendingPathComponent("note.txt")
        try Data("not an image".utf8).write(to: url)
        XCTAssertNil(ConcurrencyBudget.pixelCount(of: url))
        XCTAssertNil(ConcurrencyBudget.pixelCount(of: dir.appendingPathComponent("missing.png")))
    }

    // MARK: BatchConverter wiring (small image + injected tiny memory instead of a 50 MP file)

    private func records(_ urls: [URL]) -> [ConversionRecord] {
        urls.enumerated().map { ConversionRecord(id: $0.offset, input: $0.element, output: $0.element.appendingPathExtension("out"),
                                                 status: .pending, oldSize: 0, newSize: 0) }
    }

    private func settings(_ mode: ConvertMode) -> ConvertSettings {
        var s = ConvertSettings()
        s.mode = mode
        s.parallel = true
        return s
    }

    func testWorkerLimitShrinksForLargeSourceUnderSmallMemory() throws {
        let big = try writePNG(width: 2000, height: 1500, name: "big.png")
        let small = try writePNG(width: 30, height: 20, name: "small.png")
        let converter = BatchConverter(settings: settings(.convert), upscaler: nil, physicalMemory: 64 << 20)
        XCTAssertEqual(converter.workerLimit(for: records([small, big, small])), 1)
    }

    func testWorkerLimitKeepsCPUCapForSmallImages() throws {
        let small = try writePNG(width: 30, height: 20, name: "small.png")
        let converter = BatchConverter(settings: settings(.convert), upscaler: nil, physicalMemory: 16 * gib)
        XCTAssertEqual(converter.workerLimit(for: records([small, small])), converter.maxConcurrency)
    }

    func testUpscaleAlwaysOneWorker() throws {
        let small = try writePNG(width: 30, height: 20, name: "small.png")
        let converter = BatchConverter(settings: settings(.upscale), upscaler: nil, physicalMemory: 1024 * gib)
        XCTAssertEqual(converter.workerLimit(for: records([small])), 1)
    }
}
