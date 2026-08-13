import Darwin
import Foundation

final class LocalCommandProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var processGroupID: pid_t?
    private var isCancelled = false
    private var forceKillScheduled = false

    func register(processGroupID: pid_t) {
        lock.lock()
        self.processGroupID = processGroupID
        let shouldTerminate = isCancelled
        lock.unlock()

        if shouldTerminate {
            requestTermination(ofProcessGroup: processGroupID)
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let processGroupID = processGroupID
        lock.unlock()

        if let processGroupID {
            requestTermination(ofProcessGroup: processGroupID)
        }
    }

    func processDidExit(processGroupID: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        guard self.processGroupID == processGroupID, isCancelled == false else { return }
        self.processGroupID = nil
    }

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    private func requestTermination(ofProcessGroup processGroupID: pid_t) {
        Darwin.kill(-processGroupID, SIGTERM)

        lock.lock()
        let shouldScheduleForceKill = forceKillScheduled == false
        forceKillScheduled = true
        lock.unlock()

        guard shouldScheduleForceKill else { return }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) { [self] in
            self.lock.lock()
            let shouldForceKill = self.isCancelled
                && self.processGroupID == processGroupID
            self.lock.unlock()

            if shouldForceKill {
                Darwin.kill(-processGroupID, SIGKILL)
                self.lock.lock()
                if self.processGroupID == processGroupID {
                    self.processGroupID = nil
                }
                self.lock.unlock()
            }
        }
    }
}
