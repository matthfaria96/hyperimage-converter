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

    /// A fake backend that just hangs, like a long upscayl-bin run.
    private func hangingBackend(in dir: URL) throws -> URL {
        let script = dir.appendingPathComponent("upscayl-bin")
        try Data("#!/bin/sh\nexec /bin/sleep 30\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    func testUpscalerRegistersBackendAndTerminateAllStopsIt() async throws {
        let scratch = try TemporaryDirectory()
        let registry = ProcessRegistry()
        let upscaler = Upscaler(executable: try hangingBackend(in: scratch.url), modelsFolder: scratch.url,
                                tempRoot: scratch.url, registry: registry)
        let input = Fixtures.url("paisagem")
        let task = Task {
            try await upscaler.upscale(input, to: scratch.url.appendingPathComponent("out.png"), settings: UpscaleSettings())
        }
        let deadline = Date().addingTimeInterval(5)
        while registry.count == 0, Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(registry.count, 1, "backend should be registered while running")

        let start = Date()
        registry.terminateAll(timeout: 1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
        let result = await task.result
        XCTAssertThrowsError(try result.get(), "a killed backend must surface as a failure")
        XCTAssertEqual(registry.count, 0)
    }

    func testUpscalerUnregistersAfterNormalExit() async throws {
        let scratch = try TemporaryDirectory()
        let registry = ProcessRegistry()
        let script = scratch.url.appendingPathComponent("upscayl-bin")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let upscaler = Upscaler(executable: script, modelsFolder: scratch.url, tempRoot: scratch.url, registry: registry)
        let input = Fixtures.url("paisagem")
        do {
            try await upscaler.upscale(input, to: scratch.url.appendingPathComponent("out.png"), settings: UpscaleSettings())
            XCTFail("exit 1 should fail")
        } catch {}
        XCTAssertEqual(registry.count, 0)
    }
}
