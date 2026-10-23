import Foundation

/// Tracks child processes (upscayl-bin) so the app can stop them all when it quits.
///
/// Once `terminateAll` has run the registry is closed: it is a shutdown latch, so a backend launched
/// after quit began is refused (`isAcceptingLaunches`) or killed on registration instead of being orphaned.
///
/// `@unchecked Sendable`: the only mutable state is `processes` and `closed`, and every access goes through `lock`.
/// `Process` itself is thread-safe for `terminate()` / `isRunning`.
public final class ProcessRegistry: @unchecked Sendable {
    public static let shared = ProcessRegistry()

    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]
    private var closed = false

    public init() {}

    /// False once shutdown has begun; callers check it before launching a new child.
    public var isAcceptingLaunches: Bool {
        lock.lock(); defer { lock.unlock() }
        return !closed
    }

    /// Tracks `process`. After shutdown has begun it is killed instead, and the call returns false.
    @discardableResult
    public func register(_ process: Process) -> Bool {
        let accepted: Bool = {
            lock.lock(); defer { lock.unlock() }
            if !closed { processes[ObjectIdentifier(process)] = process }
            return !closed
        }()
        // The app is about to exit: there is no time for a graceful SIGTERM.
        if !accepted, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        return accepted
    }

    public func unregister(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        processes[ObjectIdentifier(process)] = nil
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return processes.count
    }

    /// Closes the registry, sends SIGTERM to every registered process and waits up to `timeout` seconds for them to exit.
    public func terminateAll(timeout: TimeInterval = 1.0) {
        let snapshot: [Process] = {
            lock.lock(); defer { lock.unlock() }
            closed = true
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
