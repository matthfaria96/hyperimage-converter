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
            VStack(alignment: .leading, spacing: 5) {
                ProgressView(value: runner.progress)
                    .tint(runner.failures.isEmpty ? Color.accentColor : .orange)
                    .animation(.easeInOut(duration: 0.3), value: runner.progress)
                HStack {
                    Text("\(formatBytes(n.old)) → \(formatBytes(n.new))")
                    Spacer(minLength: 8)
                    Text(timeText(now: context.date))
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
            }
        }
    }

    private func timeText(now: Date) -> String {
        let elapsed = SummaryBox.duration((runner.endDate ?? now).timeIntervalSince(runner.startDate))
        guard runner.isRunning else { return String(localized: "Levou \(elapsed)") }
        guard let left = runner.remaining(now: now) else { return elapsed }
        return String(localized: "\(elapsed) · faltam \(SummaryBox.duration(left))")
    }
}
