import AppKit
import HyperImageCore
import Observation

/// Drives one batch conversion and holds its live state for the progress sheet.
@Observable
final class ConversionRunner {
    struct OverwritePrompt: Identifiable {
        let id = UUID()
        let url: URL
    }

    private(set) var records: [ConversionRecord] = []
    /// Progress inside the file currently being upscaled.
    private(set) var partial: Double = 0
    private(set) var isRunning = false
    private(set) var wasCancelled = false
    private(set) var failure: String?
    /// Bumped on every finish so observers that attach late still see the completion.
    private(set) var completionID = 0
    private(set) var startDate = Date()
    private(set) var endDate: Date?
    private(set) var settings = ConvertSettings()
    var prompt: OverwritePrompt?
    var openFolderWhenDone = false

    // Aggregates are stored (refreshed once per update) so views can read them freely while a batch runs.
    private(set) var finishedCount = 0
    private(set) var doneCount = 0
    private(set) var oldTotal: Int64 = 0
    private(set) var newTotal: Int64 = 0
    private(set) var failures: [ConversionRecord] = []
    /// The first file still waiting: where an upscale (which runs in order) currently is.
    private(set) var currentURL: URL?
    @ObservationIgnored private var indexByURL: [URL: Int] = [:]
    /// Bumped per run so late updates from a cancelled run never overwrite the new one.
    @ObservationIgnored private var generation = 0

    private var task: Task<Void, Never>?
    private var continuation: CheckedContinuation<OverwriteDecision, Never>?

    func start(items: [InputItem], settings: ConvertSettings) {
        task?.cancel()
        answer(.cancel)
        partial = 0
        generation += 1
        let run = generation
        let converter = BatchConverter(settings: settings, fileProgress: { [weak self] _, fraction in
            Task { @MainActor in self?.report(fraction, run: run) }
        })
        self.settings = settings
        openFolderWhenDone = settings.openFolderWhenDone
        records = converter.records(for: items)
        indexByURL = Dictionary(records.enumerated().map { ($1.input, $0) }, uniquingKeysWith: { _, last in last })
        recount()
        isRunning = true
        wasCancelled = false
        failure = nil
        startDate = Date()
        endDate = nil
        let queued = records
        task = Task {
            do {
                try await converter.run(queued,
                                        askOverwrite: { url in await self.ask(url) },
                                        update: { record in await self.apply(record, run: run) })
            } catch is CancellationError {
                if run == generation { wasCancelled = true }
            } catch {
                if run == generation { failure = error.localizedDescription }
            }
            guard run == generation else { return }
            finish()
        }
    }

    func cancel() {
        task?.cancel()
        answer(.cancel)
    }

    func answer(_ decision: OverwriteDecision) {
        prompt = nil
        continuation?.resume(returning: decision)
        continuation = nil
    }

    private func ask(_ url: URL) async -> OverwriteDecision {
        if task?.isCancelled ?? true { return .cancel }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            prompt = OverwritePrompt(url: url)
        }
    }

    private func apply(_ record: ConversionRecord, run: Int) {
        guard run == generation, record.id < records.count else { return }
        records[record.id] = record
        partial = 0
        recount()
    }

    /// Progress inside the current file, in whole-percent steps so the UI is not redrawn for every output line.
    private func report(_ fraction: Double, run: Int) {
        guard run == generation, fraction - partial >= 0.01 || fraction >= 0.999 else { return }
        partial = fraction
    }

    private func recount() {
        var finished = 0, done = 0, old: Int64 = 0, new: Int64 = 0
        var failed: [ConversionRecord] = []
        var firstPending: URL?
        for record in records {
            switch record.status {
            case .pending: if firstPending == nil { firstPending = record.input }
            case .working: break
            case .done: finished += 1; done += 1; old += record.oldSize; new += record.newSize
            case .skipped: finished += 1
            case .failed: finished += 1; failed.append(record)
            }
        }
        finishedCount = finished
        doneCount = done
        oldTotal = old
        newTotal = new
        failures = failed
        currentURL = firstPending
    }

    private func finish() {
        isRunning = false
        endDate = Date()
        completionID += 1
        if openFolderWhenDone, let first = records.first(where: { $0.status == .done }) {
            NSWorkspace.shared.activateFileViewerSelecting([first.output])
        }
    }

    /// Latest result for an input file, for the file cards (nil before the first run).
    func record(for url: URL) -> ConversionRecord? { indexByURL[url].map { records[$0] } }

    var hasResults: Bool { !records.isEmpty }

    /// The file an upscale is working on (upscales run one at a time, in order).
    var currentUpscale: URL? { isRunning && settings.mode == .upscale ? currentURL : nil }

    func clearResults() {
        guard !isRunning else { return }
        records = []
        indexByURL = [:]
        recount()
        endDate = nil
        failure = nil
        wasCancelled = false
    }

    // MARK: Totals

    var progress: Double {
        records.isEmpty ? 1 : min(1, (Double(finishedCount) + (isRunning ? partial : 0)) / Double(records.count))
    }


    /// Time left, from the pace so far (the partial upscale counts, so the first file already gives an estimate).
    func remaining(now: Date) -> TimeInterval? {
        let progressed = Double(finishedCount) + partial
        guard isRunning, progressed > 0.05 else { return nil }
        let elapsed = now.timeIntervalSince(startDate)
        guard elapsed > 2 else { return nil }
        return elapsed / progressed * (Double(records.count) - progressed)
    }
}
