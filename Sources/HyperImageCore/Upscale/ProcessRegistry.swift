import Foundation

/// Tracks child processes (upscayl-bin) so the app can stop them all when it quits.
///
/// `@unchecked Sendable`: the only mutable state is `processes`, and every access goes through `lock`.
/// `Process` itself is thread-safe for `terminate()` / `isRunning`.
public final class ProcessRegistry: @unchecked Sendable {
    public static let shared = ProcessRegistry()

    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    public init() {}

    public func register(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        processes[ObjectIdentifier(process)] = process
    }

    public func unregister(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        processes[ObjectIdentifier(process)] = nil
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return processes.count
    }

    /// Sends SIGTERM to every registered process and waits up to `timeout` seconds for them to exit.
    public func terminateAll(timeout: TimeInterval = 1.0) {
        let snapshot: [Process] = {
            lock.lock(); defer { lock.unlock() }
            let all = Array(processes.values)
            processes = [:]
            return all
        }()
        let running = snapshot.filter(\.isRunning)
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while running.contains(where: \.isRunning), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
    }
}
