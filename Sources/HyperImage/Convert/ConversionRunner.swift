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

    private var task: Task<Void, Never>?
    private var continuation: CheckedContinuation<OverwriteDecision, Never>?

    func start(items: [InputItem], settings: ConvertSettings) {
        task?.cancel()
        answer(.cancel)
        let converter = BatchConverter(settings: settings)
        self.settings = settings
        openFolderWhenDone = settings.openFolderWhenDone
        records = converter.records(for: items)
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
                                        update: { record in await self.apply(record) })
            } catch is CancellationError {
                wasCancelled = true
            } catch {
                failure = error.localizedDescription
            }
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

    private func apply(_ record: ConversionRecord) {
        guard record.id < records.count else { return }
        records[record.id] = record
    }

    private func finish() {
        isRunning = false
        endDate = Date()
        completionID += 1
        if openFolderWhenDone, let first = records.first(where: { $0.status == .done }) {
            NSWorkspace.shared.activateFileViewerSelecting([first.output])
        }
    }

    // MARK: Totals

    var finishedCount: Int { records.filter { $0.status != .pending && $0.status != .working }.count }
    var failures: [ConversionRecord] { records.filter { if case .failed = $0.status { true } else { false } } }
    var progress: Double { records.isEmpty ? 1 : Double(finishedCount) / Double(records.count) }

    var oldTotal: Int64 { records.filter { $0.status == .done }.map(\.oldSize).reduce(0, +) }
    var newTotal: Int64 { records.filter { $0.status == .done }.map(\.newSize).reduce(0, +) }

    func remaining(now: Date) -> TimeInterval? {
        let done = finishedCount
        guard isRunning, done > 0 else { return nil }
        let elapsed = now.timeIntervalSince(startDate)
        return elapsed / Double(done) * Double(records.count - done)
    }
}
