import XCTest
@testable import HyperImageCore

final class ProcessRegistryTests: XCTestCase {
    private var launched: [Process] = []

    override func tearDown() {
        for process in launched where process.isRunning { process.terminate() }
        launched = []
    }

    private func sleeper(_ seconds: String = "30") throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        try process.run()
        launched.append(process)
        return process
    }

    func testTerminateAllStopsRunningProcessesWithinTimeout() throws {
        let registry = ProcessRegistry()
        let process = try sleeper()
        registry.register(process)
        XCTAssertEqual(registry.count, 1)

        let start = Date()
        registry.terminateAll(timeout: 1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(registry.count, 0)
    }

    func testUnregisterRemovesProcess() throws {
        let registry = ProcessRegistry()
        let process = try sleeper()
        registry.register(process)
        registry.unregister(process)
        XCTAssertEqual(registry.count, 0)
        registry.terminateAll(timeout: 1)
        // Not registered, so terminateAll leaves it alone.
        XCTAssertTrue(process.isRunning)
    }

    func testTerminateAllOnEmptyRegistryReturnsImmediately() {
        let registry = ProcessRegistry()
        let start = Date()
        registry.terminateAll(timeout: 1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.1)
        XCTAssertEqual(registry.count, 0)
    }

    func testTerminateAllToleratesAlreadyExitedProcess() throws {
        let registry = ProcessRegistry()
        let process = try sleeper("0")
        process.waitUntilExit()
        registry.register(process)
        registry.terminateAll(timeout: 1)
        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(registry.count, 0)
    }

    func testRegisteringSameProcessTwiceCountsOnce() throws {
        let registry = ProcessRegistry()
        let process = try sleeper()
        registry.register(process)
        registry.register(process)
        XCTAssertEqual(registry.count, 1)
        registry.terminateAll(timeout: 1)
    }
}
