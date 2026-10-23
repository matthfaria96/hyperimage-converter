import Foundation
import HyperImageCore

extension AppModel {
    /// Renames the originals on disk and keeps the input list pointing at the new names.
    @discardableResult
    func applyRename(_ entries: [RenameEntry]) -> RenameOutcome {
        let outcome = BatchRename.execute(entries)
        replace(Dictionary(outcome.moved.map { ($0.from, $0.to) }, uniquingKeysWith: { _, last in last }))
        // A rename that moved nothing keeps the undo of the previous one.
        if !outcome.moved.isEmpty { lastRename = outcome.moved }
        if !outcome.failures.isEmpty {
            alert = AppAlert(title: String(localized: "\(outcome.failures.count) arquivo(s) não renomeado(s)"),
                             message: outcome.failures.prefix(8).map { "\($0.0.lastPathComponent): \($0.1)" }.joined(separator: "\n"))
        }
        return outcome
    }

    /// Restores the names from the last rename; never overwrites a name that is now taken.
    /// Files that could not go back stay in the history, so Undo can be tried again after freeing the name.
    func undoLastRename() {
        guard !lastRename.isEmpty else { return }
        let plan = BatchRename.undoPlan(lastRename)
        let outcome = BatchRename.execute(plan)
        replace(Dictionary(outcome.moved.map { ($0.from, $0.to) }, uniquingKeysWith: { _, last in last }))
        lastRename = Self.remainingHistory(lastRename, undone: outcome.moved)
        let conflicts = plan.filter(\.conflict).count
        guard conflicts > 0 || !outcome.failures.isEmpty else { return }
        var lines: [String] = []
        if conflicts > 0 {
            lines.append(String(localized: "\(conflicts) arquivo(s) não voltaram ao nome anterior: o nome está em uso ou o arquivo não existe mais."))
        }
        lines += outcome.failures.prefix(8).map { "\($0.0.lastPathComponent): \($0.1)" }
        alert = AppAlert(title: String(localized: "Desfazer renomeação"), message: lines.joined(separator: "\n"))
    }

    /// Forward moves still worth undoing: the ones not reversed, re-pointed when a file ended somewhere else,
    /// and without files that no longer exist.
    static func remainingHistory(_ history: [RenameMove], undone: [RenameMove]) -> [RenameMove] {
        let landed = Dictionary(undone.map { ($0.from, $0.to) }, uniquingKeysWith: { _, last in last })
        return history.compactMap { move in
            guard let now = landed[move.to] else {
                return FileManager.default.fileExists(atPath: move.to.path) ? move : nil
            }
            return now == move.from ? nil : RenameMove(from: move.from, to: now)
        }
    }
}
