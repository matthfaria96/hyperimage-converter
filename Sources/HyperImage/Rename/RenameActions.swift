import Foundation
import HyperImageCore

extension AppModel {
    /// Renames the originals on disk and keeps the input list pointing at the new names.
    @discardableResult
    func applyRename(_ entries: [RenameEntry]) -> RenameOutcome {
        let outcome = BatchRename.execute(entries)
        replace(Dictionary(outcome.moved.map { ($0.from, $0.to) }, uniquingKeysWith: { _, last in last }))
        lastRename = outcome.moved
        if !outcome.failures.isEmpty {
            alert = AppAlert(title: String(localized: "\(outcome.failures.count) arquivo(s) não renomeado(s)"),
                             message: outcome.failures.prefix(8).map { "\($0.0.lastPathComponent): \($0.1)" }.joined(separator: "\n"))
        }
        return outcome
    }

    /// Restores the names from the last rename; never overwrites a name that is now taken.
    func undoLastRename() {
        guard !lastRename.isEmpty else { return }
        let total = lastRename.count
        let outcome = BatchRename.execute(BatchRename.undoPlan(lastRename))
        replace(Dictionary(outcome.moved.map { ($0.from, $0.to) }, uniquingKeysWith: { _, last in last }))
        lastRename = []
        let skipped = total - outcome.renamed
        guard skipped > 0 || !outcome.failures.isEmpty else { return }
        var message = skipped > 0
            ? String(localized: "\(skipped) arquivo(s) não voltaram ao nome anterior porque o nome já está em uso.")
            : ""
        if !outcome.failures.isEmpty {
            let details = outcome.failures.prefix(8).map { "\($0.0.lastPathComponent): \($0.1)" }.joined(separator: "\n")
            message += (message.isEmpty ? "" : "\n") + details
        }
        alert = AppAlert(title: String(localized: "Desfazer renomeação"), message: message)
    }
}
