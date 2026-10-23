import SwiftUI

struct BatchNumbers: Equatable {
    let old: Int64
    let new: Int64
    var ratioPercent: Int { old > 0 ? Int((Double(new) / Double(old) * 100).rounded()) : 0 }
    var saved: Int64 { max(0, old - new) }
}

/// Old → new sizes, ratio, savings, elapsed and remaining time of the running or finished batch.
struct ProgressStats: View {
    let runner: ConversionRunner

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let n = BatchNumbers(old: runner.oldTotal, new: runner.newTotal)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                row("Antigo → novo", "\(formatBytes(n.old)) → \(formatBytes(n.new))")
                row("Proporção", "\(n.ratioPercent) %")
                row("Economia", formatBytes(n.saved))
                row("Decorrido", SummaryBox.duration((runner.endDate ?? context.date).timeIntervalSince(runner.startDate)))
                row("Restante", runner.isRunning ? (runner.remaining(now: context.date).map(SummaryBox.duration) ?? "—") : "—")
            }
            .font(.caption).monospacedDigit()
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
