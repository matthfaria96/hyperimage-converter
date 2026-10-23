import Foundation
import HyperImageCore
import Observation

/// One finished file from a past batch.
struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let batch: UUID
    let date: Date
    let mode: ConvertMode
    let source: URL
    let output: URL
    let oldSize: Int64
    let newSize: Int64
    /// Set when the file failed; the message shown to the user.
    let error: String?
}

/// Past batches, newest first, kept in Application Support so they survive relaunches.
@Observable
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []
    /// Entries of the most recent batch, so the history can mark them as new.
    private(set) var latestBatch: UUID?
    @ObservationIgnored private let file: URL
    static let limit = 1000

    init(file: URL = HistoryStore.defaultFile) {
        self.file = file
        let data = try? Data(contentsOf: file)
        entries = data.flatMap { try? JSONDecoder().decode([HistoryEntry].self, from: $0) } ?? []
    }

    static var defaultFile: URL {
        #if DEBUG
        // Screenshots and test runs must not write into the user's real history.
        if let path = ProcessInfo.processInfo.environment["HYPERIMAGE_HISTORY"] { return URL(fileURLWithPath: path) }
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("HyperImage Converter", isDirectory: true).appendingPathComponent("history.json")
    }

    /// Records the done and failed files of a finished batch (skipped files are not history).
    func record(_ records: [ConversionRecord], mode: ConvertMode, date: Date = Date()) {
        let batch = UUID()
        let new = records.compactMap { r -> HistoryEntry? in
            switch r.status {
            case .done: HistoryEntry(batch: batch, date: date, mode: mode, source: r.input, output: r.output,
                                     oldSize: r.oldSize, newSize: r.newSize, error: nil)
            case let .failed(message): HistoryEntry(batch: batch, date: date, mode: mode, source: r.input, output: r.output,
                                                    oldSize: r.oldSize, newSize: 0, error: message)
            default: nil
            }
        }
        guard !new.isEmpty else { return }
        latestBatch = batch
        entries = Array((new + entries).prefix(Self.limit))
        save()
    }

    func remove(_ ids: Set<UUID>) {
        entries = entries.filter { !ids.contains($0.id) }
        save()
    }

    func clear() {
        entries = []
        latestBatch = nil
        save()
    }

    /// Entries grouped by batch, newest batch first.
    var batches: [[HistoryEntry]] {
        var order: [UUID] = []
        var groups: [UUID: [HistoryEntry]] = [:]
        for entry in entries {
            if groups[entry.batch] == nil { order.append(entry.batch) }
            groups[entry.batch, default: []].append(entry)
        }
        return order.compactMap { groups[$0] }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        } catch {
            // History is a convenience: failing to save it must never interrupt a conversion.
        }
    }
}
