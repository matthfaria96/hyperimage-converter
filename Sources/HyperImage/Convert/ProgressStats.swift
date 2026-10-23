import SwiftUI

struct BatchNumbers: Equatable {
    let old: Int64
    let new: Int64
    var ratioPercent: Int { old > 0 ? Int((Double(new) / Double(old) * 100).rounded()) : 0 }
    var saved: Int64 { max(0, old - new) }
}

/// Progress bar plus one compact line: old → new, elapsed and remaining time of the running or finished batch.
struct ProgressStats: View {
    let runner: ConversionRunner

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let n = BatchNumbers(old: runner.oldTotal, new: runner.newTotal)
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: runner.progress)
                    .tint(runner.failures.isEmpty ? Color.accentColor : .orange)
                    .animation(.easeInOut(duration: 0.3), value: runner.progress)
                HStack(spacing: 0) {
                    stat("Original → novo", "\(formatBytes(n.old)) → \(formatBytes(n.new))")
                    Spacer(minLength: 8)
                    stat("Decorrido", SummaryBox.duration((runner.endDate ?? context.date).timeIntervalSince(runner.startDate)))
                    if runner.isRunning {
                        Spacer(minLength: 8)
                        stat("Restante", runner.remaining(now: context.date).map(SummaryBox.duration) ?? "—")
                    }
                }
                .font(.callout).monospacedDigit()
            }
        }
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).contentTransition(.numericText())
        }
    }
}
