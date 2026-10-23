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

    /// AI Upscale backend; nil outside the app bundle unless, in debug builds, HYPERIMAGE_UPSCAYL points at one.
    public let upscaler: Upscaler?
    /// Fraction (0…1) of the file being upscaled, by record id. Upscales are long, one file can take minutes.
    public let fileProgress: @Sendable (Int, Double) -> Void
    /// Memory the worker budget is sized against; injectable for tests.
    public let physicalMemory: UInt64

    public init(settings: ConvertSettings, upscaler: Upscaler? = Upscaler.bundled(),
                fileProgress: @escaping @Sendable (Int, Double) -> Void = { _, _ in },
                physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) {
        self.settings = settings
        self.physicalMemory = physicalMemory
        self.upscaler = upscaler
        self.fileProgress = fileProgress
        // The GPU already parallelises one upscale; running several at once only fights over VRAM.
        self.maxConcurrency = settings.mode == .upscale ? 1
            : settings.parallel ? max(1, min(ProcessInfo.processInfo.activeProcessorCount, 6)) : 1
    }

    /// CPU cap (maxConcurrency) narrowed by the memory the sources will need once decoded.
    func workerLimit(for records: [ConversionRecord]) -> Int {
        guard maxConcurrency > 1 else { return 1 }
        return ConcurrencyBudget.workers(pixelCounts: records.map { ConcurrencyBudget.pixelCount(of: $0.input) },
                                         base: maxConcurrency, physicalMemory: physicalMemory)
    }

    public func records(for items: [InputItem]) -> [ConversionRecord] {
        let outputs = OutputPlanner.destinations(for: items, settings: settings)
        return zip(items, outputs).enumerated().map { index, pair in
            ConversionRecord(id: index, input: pair.0.url, output: pair.1, status: .pending, oldSize: Self.fileSize(pair.0.url), newSize: 0)
        }
    }

    public func run(
        _ records: [ConversionRecord],
        askOverwrite: @escaping @Sendable (URL) async -> OverwriteDecision,
        update: @escaping @Sendable (ConversionRecord) async -> Void
    ) async throws {
        let pipeline = try ImagePipeline(options: settings.effectiveAdvancedOptions)
        var standing: OverwriteDecision? = settings.skipExisting ? .noToAll : nil
        let limit = workerLimit(for: records)
        try await withThrowingTaskGroup(of: Void.self) { group in
            var running = 0
            for record in records {
                try Task.checkCancellation()
                if settings.askBeforeOverwrite || settings.skipExisting, FileManager.default.fileExists(atPath: record.output.path) {
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
                if running >= limit {
                    try await group.next()
                    running -= 1
                }
                group.addTask {
                    await update(settings.mode == .upscale ? await upscale(record) : convert(record, pipeline: pipeline))
                }
                running += 1
            }
            try await group.waitForAll()
        }
    }

    func convert(_ record: ConversionRecord, pipeline: ImagePipeline) -> ConversionRecord {
        do {
            let loaded = try ImageLoader.load(record.input)
            let data = try OutputEncoder.encode(loaded, pipeline: pipeline, settings: settings).data
            let fm = FileManager.default
            try fm.createDirectory(at: record.output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: record.output, options: .atomic)
            copyDates(from: record.input, to: record.output)
            var done = record.with(status: .done)
            done.newSize = Int64(data.count)
            return done
        } catch {
            return record.with(status: .failed(error.localizedDescription))
        }
    }

    func upscale(_ record: ConversionRecord) async -> ConversionRecord {
        do {
            guard let upscaler else { throw UpscaleError.backendMissing }
            let id = record.id, report = fileProgress
            try await upscaler.upscale(record.input, to: record.output, settings: settings.upscale) { report(id, $0) }
            copyDates(from: record.input, to: record.output)
            var done = record.with(status: .done)
            done.newSize = Self.fileSize(record.output)
            return done
        } catch is CancellationError {
            return record
        } catch {
            return record.with(status: .failed(error.localizedDescription))
        }
    }

    private func copyDates(from input: URL, to output: URL) {
        guard settings.keepDates else { return }
        let values = try? input.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        var attributes: [FileAttributeKey: Any] = [:]
        if let modified = values?.contentModificationDate { attributes[.modificationDate] = modified }
        if let created = values?.creationDate { attributes[.creationDate] = created }
        if !attributes.isEmpty { try? FileManager.default.setAttributes(attributes, ofItemAtPath: output.path) }
    }

    public static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    /// Date used for sorting by date taken: EXIF capture date when present, otherwise modification date.
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

