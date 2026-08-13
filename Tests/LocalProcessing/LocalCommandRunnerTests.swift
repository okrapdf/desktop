import Darwin
import Foundation
import Testing
@testable import Okra

struct LocalCommandRunnerTests {
    @Test("Canceling an async provider command terminates its process", .timeLimit(.minutes(1)))
    func cancellationTerminatesProcess() async throws {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let task = Task {
            try await LocalCommandRunner.runAsync(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"]
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Canceled provider command unexpectedly succeeded")
        } catch is CancellationError {
            // Expected: the runner reports cancellation after the child exits.
        }

        #expect(startedAt.duration(to: clock.now) < .seconds(3))
    }

    @Test("Canceling a provider shell terminates its descendant process", .timeLimit(.minutes(1)))
    func cancellationTerminatesDescendantProcess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("okra-command-group-\(UUID().uuidString)", isDirectory: true)
        let childPIDURL = root.appendingPathComponent("child.pid")
        let heartbeatURL = root.appendingPathComponent("child-heartbeat.log")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let script = """
        (
          trap '' TERM
          while true; do
            print -r -- tick >> "$2"
            sleep 0.05
          done
        ) &
        child_pid=$!
        print -r -- "$child_pid" > "$1"
        wait "$child_pid"
        """
        let task = Task {
            try await LocalCommandRunner.runAsync(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: [
                    "-c",
                    script,
                    "okra-command-group",
                    childPIDURL.path,
                    heartbeatURL.path,
                ]
            )
        }

        let childPID = try await waitForChildPID(at: childPIDURL)
        defer {
            let processGroupID = Darwin.getpgid(childPID)
            if processGroupID > 0, processGroupID != Darwin.getpgrp() {
                Darwin.kill(-processGroupID, SIGKILL)
            } else {
                Darwin.kill(childPID, SIGKILL)
            }
        }
        #expect(Darwin.kill(childPID, 0) == 0)

        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Canceled provider shell unexpectedly succeeded")
        } catch is CancellationError {
            // Expected: the runner reports cancellation after the group leader exits.
        }

        try await Task.sleep(for: .milliseconds(1_400))
        let heartbeatSizeAfterForceKill = try #require(fileSize(at: heartbeatURL))
        #expect(heartbeatSizeAfterForceKill > 0)
        try await Task.sleep(for: .milliseconds(300))
        #expect(fileSize(at: heartbeatURL) == heartbeatSizeAfterForceKill)
    }

    private func waitForChildPID(at url: URL) async throws -> pid_t {
        for _ in 0..<100 {
            if let contents = try? String(contentsOf: url, encoding: .utf8),
               let processID = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return processID
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw LocalCommandRunnerTestError.childDidNotStart
    }

    private func fileSize(at url: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }
}

private enum LocalCommandRunnerTestError: Error {
    case childDidNotStart
}
