import ImageIO
import Foundation

public enum OverwriteDecision: Sendable {
    case yes, no, yesToAll, noToAll, cancel
}

public enum ConversionStatus: Equatable, Sendable {
    case pending, working, done, skipped, failed(String)
}

public struct ConversionRecord: Identifiable, Equatable, Sendable {
    public let id: Int
    public let input: URL
    public let output: URL
    public var status: ConversionStatus
    public var oldSize: Int64
    public var newSize: Int64

    public var ratio: Double? { oldSize > 0 && newSize > 0 ? Double(newSize) / Double(oldSize) : nil }
}

/// Converts a list of files concurrently. Overwrite questions are asked one at a time, in list order.
public struct BatchConverter: Sendable {
    public let settings: ConvertSettings
    public let maxConcurrency: Int

    public init(settings: ConvertSettings) {
        self.settings = settings
        self.maxConcurrency = settings.parallel ? max(1, min(ProcessInfo.processInfo.activeProcessorCount, 6)) : 1
    }

    public func records(for items: [InputItem]) -> [ConversionRecord] {
        let outputs = OutputPlanner.destinations(for: items, settings: settings, dates: Self.fileDate)
        return zip(items, outputs).enumerated().map { index, pair in
            ConversionRecord(id: index, input: pair.0.url, output: pair.1, status: .pending, oldSize: Self.fileSize(pair.0.url), newSize: 0)
        }
    }

    public func run(
        _ records: [ConversionRecord],
        askOverwrite: @escaping @Sendable (URL) async -> OverwriteDecision,
        update: @escaping @Sendable (ConversionRecord) async -> Void
    ) async throws {
        let pipeline = try ImagePipeline(options: settings.useAdvancedOptions ? settings.advanced : AdvancedOptions())
        var standing: OverwriteDecision?
        try await withThrowingTaskGroup(of: Void.self) { group in
            var running = 0
            for record in records {
                try Task.checkCancellation()
                if settings.askBeforeOverwrite, FileManager.default.fileExists(atPath: record.output.path) {
                    let decision: OverwriteDecision
                    if let standing { decision = standing } else { decision = await askOverwrite(record.output) }
                    switch decision {
                    case .cancel: throw CancellationError()
                    case .yesToAll, .noToAll: standing = decision
                    case .yes, .no: break
                    }
                    if decision == .no || decision == .noToAll {
                        await update(record.with(status: .skipped))
                        continue
                    }
                }
                if running >= maxConcurrency {
                    try await group.next()
                    running -= 1
                }
                group.addTask { await update(convert(record, pipeline: pipeline)) }
                running += 1
            }
            try await group.waitForAll()
        }
    }

    func convert(_ record: ConversionRecord, pipeline: ImagePipeline) -> ConversionRecord {
        do {
            let loaded = try ImageLoader.load(record.input)
            let processed = try pipeline.process(loaded)
            let data = try ImageEncoder.encode(
                .init(image: processed.image, sourceProperties: loaded.properties, sourceJPEGQuality: loaded.metadata.jpegQuality,
                      dpiX: processed.dpiX, dpiY: processed.dpiY),
                format: settings.format, settings: settings.formatSettings)
            let fm = FileManager.default
            try fm.createDirectory(at: record.output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: record.output, options: .atomic)
            if settings.keepDates {
                var attributes: [FileAttributeKey: Any] = [.modificationDate: loaded.modificationDate]
                if let created = loaded.creationDate { attributes[.creationDate] = created }
                try? fm.setAttributes(attributes, ofItemAtPath: record.output.path)
            }
            var done = record.with(status: .done)
            done.newSize = Int64(data.count)
            return done
        } catch {
            return record.with(status: .failed(error.localizedDescription))
        }
    }

    public static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    /// Date used by rename templates: EXIF capture date when present, otherwise modification date.
    public static func fileDate(_ url: URL) -> Date {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let taken = ImageMetadata(properties: p).dateTaken {
            return taken
        }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
    }
}

extension ConversionRecord {
    func with(status: ConversionStatus) -> ConversionRecord {
        var copy = self
        copy.status = status
        return copy
    }
}

