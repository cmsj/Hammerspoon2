//
//  HSTaskReaperTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
@testable import Hammerspoon_2

/// Tests for HSTaskReaper, which SIGKILLs hs.task processes that don't exit after SIGTERM.
///
/// Each test uses its own reaper instance so pending processes from other tests can't
/// affect counts or timings.
@Suite("HSTaskReaper tests")
struct HSTaskReaperTests {

    /// Launch a process, and wait until it is ready to receive signals.
    /// - Parameter ignoreSIGTERM: If true, the process ignores SIGTERM and only SIGKILL will end it
    private func launchSleeper(ignoreSIGTERM: Bool) throws -> Process {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The trap must be installed before we signal the process, so it reports when it's ready.
        // exec keeps the PID the same, and ignored signals stay ignored across exec.
        let trap = ignoreSIGTERM ? "trap '' TERM; " : ""
        process.arguments = ["-c", "\(trap)echo ready; exec /bin/sleep 30"]
        process.standardOutput = stdout
        try process.run()
        _ = stdout.fileHandleForReading.availableData
        return process
    }

    private func waitUntil(timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test("Reaping a process that isn't running is a no-op")
    func testReapNotRunning() throws {
        let reaper = HSTaskReaper()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()

        reaper.reap(process)
        #expect(reaper.pendingCount == 0)
    }

    @Test("A process that exits on SIGTERM is released without SIGKILL")
    func testCooperativeProcessIsReleased() async throws {
        let reaper = HSTaskReaper()
        let process = try launchSleeper(ignoreSIGTERM: false)

        process.terminate()
        reaper.reap(process, gracePeriod: .seconds(5))

        let released = await waitUntil(timeout: .seconds(2)) { reaper.pendingCount == 0 }
        #expect(released)
        process.waitUntilExit()
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(process.terminationStatus == SIGTERM)
    }

    @Test("A process that ignores SIGTERM is sent SIGKILL after its grace period")
    func testStubbornProcessIsKilled() async throws {
        let reaper = HSTaskReaper()
        let process = try launchSleeper(ignoreSIGTERM: true)

        process.terminate()
        reaper.reap(process, gracePeriod: .milliseconds(200))

        let exited = await waitUntil(timeout: .seconds(3)) { !process.isRunning }
        #expect(exited)
        #expect(reaper.pendingCount == 0)
        process.waitUntilExit()
        #expect(process.terminationStatus == SIGKILL)
    }

    @Test("Reaping a pending process again keeps the earlier deadline")
    func testReapTwiceKeepsEarlierDeadline() async throws {
        let reaper = HSTaskReaper()
        let process = try launchSleeper(ignoreSIGTERM: true)

        process.terminate()
        reaper.reap(process, gracePeriod: .milliseconds(200))
        reaper.reap(process, gracePeriod: .seconds(60))
        #expect(reaper.pendingCount == 1)

        let exited = await waitUntil(timeout: .seconds(3)) { !process.isRunning }
        #expect(exited)
        process.waitUntilExit()
        #expect(process.terminationStatus == SIGKILL)
    }

    @MainActor
    @Test("drain() sends SIGKILL to processes still running when its timeout expires")
    func testDrainKillsStubbornProcess() throws {
        let reaper = HSTaskReaper()
        let process = try launchSleeper(ignoreSIGTERM: true)

        process.terminate()
        reaper.reap(process, gracePeriod: .seconds(60))

        let start = ContinuousClock.now
        let killed = reaper.drain(timeout: .milliseconds(300))
        let elapsed = ContinuousClock.now - start

        #expect(killed == 1)
        #expect(reaper.pendingCount == 0)
        #expect(elapsed < .seconds(2))
        process.waitUntilExit()
        #expect(process.terminationStatus == SIGKILL)
    }

    @MainActor
    @Test("drain() returns as soon as pending processes exit on SIGTERM")
    func testDrainReturnsEarly() throws {
        let reaper = HSTaskReaper()
        let process = try launchSleeper(ignoreSIGTERM: false)

        process.terminate()
        reaper.reap(process, gracePeriod: .seconds(60))

        let start = ContinuousClock.now
        let killed = reaper.drain(timeout: .seconds(5))
        let elapsed = ContinuousClock.now - start

        #expect(killed == 0)
        #expect(reaper.pendingCount == 0)
        #expect(elapsed < .seconds(2))
        process.waitUntilExit()
        #expect(process.terminationStatus == SIGTERM)
    }

    @MainActor
    @Test("drain() with nothing pending returns immediately")
    func testDrainEmpty() {
        let reaper = HSTaskReaper()
        #expect(reaper.drain(timeout: .seconds(5)) == 0)
    }
}
