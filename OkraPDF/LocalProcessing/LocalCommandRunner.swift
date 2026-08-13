import Darwin
import Foundation

enum LocalCommandRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        environment additions: [String: String] = [:]
    ) throws -> String {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("okra-provider-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: logURL) }

        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? logHandle.close() }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.environment = ProcessInfo.processInfo.environment.merging(additions) { _, new in new }

        try process.run()
        process.waitUntilExit()
        try logHandle.synchronize()

        let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        guard process.terminationStatus == 0 else {
            throw LocalProcessingError.commandFailed(
                command: executableURL.lastPathComponent,
                status: process.terminationStatus,
                output: output
            )
        }
        return output
    }

    static func runAsync(
        executableURL: URL,
        arguments: [String],
        environment additions: [String: String] = [:]
    ) async throws -> String {
        let processBox = LocalCommandProcessBox()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let logURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("okra-provider-\(UUID().uuidString).log")

                do {
                    FileManager.default.createFile(atPath: logURL.path, contents: nil)
                    let logHandle = try FileHandle(forWritingTo: logURL)
                    let processGroupID: pid_t
                    do {
                        processGroupID = try spawnProcessGroup(
                            executableURL: executableURL,
                            arguments: arguments,
                            environment: ProcessInfo.processInfo.environment.merging(additions) {
                                _, new in new
                            },
                            outputFileDescriptor: logHandle.fileDescriptor
                        )
                        try logHandle.close()
                    } catch {
                        try? logHandle.close()
                        throw error
                    }
                    processBox.register(processGroupID: processGroupID)

                    DispatchQueue.global(qos: .userInitiated).async {
                        let terminationStatus = waitForProcess(processGroupID)
                        processBox.processDidExit(processGroupID: processGroupID)
                        let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                        try? FileManager.default.removeItem(at: logURL)

                        if processBox.wasCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else if terminationStatus == 0 {
                            continuation.resume(returning: output)
                        } else {
                            continuation.resume(
                                throwing: LocalProcessingError.commandFailed(
                                    command: executableURL.lastPathComponent,
                                    status: terminationStatus,
                                    output: output
                                )
                            )
                        }
                    }
                } catch {
                    try? FileManager.default.removeItem(at: logURL)
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            processBox.cancel()
        }
    }

    private static func spawnProcessGroup(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        outputFileDescriptor: Int32
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try checkPOSIX(posix_spawn_file_actions_init(&fileActions))
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        try checkPOSIX(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }

        try checkPOSIX(
            posix_spawn_file_actions_adddup2(
                &fileActions,
                outputFileDescriptor,
                STDOUT_FILENO
            )
        )
        try checkPOSIX(
            posix_spawn_file_actions_adddup2(
                &fileActions,
                outputFileDescriptor,
                STDERR_FILENO
            )
        )
        try checkPOSIX(
            posix_spawn_file_actions_addclose(&fileActions, outputFileDescriptor)
        )

        var emptySignalMask = sigset_t()
        sigemptyset(&emptySignalMask)
        try checkPOSIX(posix_spawnattr_setsigmask(&attributes, &emptySignalMask))

        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        for signal in [SIGHUP, SIGINT, SIGQUIT, SIGPIPE, SIGTERM] {
            sigaddset(&defaultSignals, signal)
        }
        try checkPOSIX(posix_spawnattr_setsigdefault(&attributes, &defaultSignals))
        try checkPOSIX(posix_spawnattr_setpgroup(&attributes, 0))
        try checkPOSIX(
            posix_spawnattr_setflags(
                &attributes,
                Int16(
                    POSIX_SPAWN_SETPGROUP
                        | POSIX_SPAWN_SETSIGMASK
                        | POSIX_SPAWN_SETSIGDEF
                )
            )
        )

        let argumentStrings = [executableURL.path] + arguments
        let environmentStrings = environment.map { key, value in "\(key)=\(value)" }
        var processID: pid_t = 0
        let result = try withMutableCStrings(argumentStrings) { argumentPointers in
            try withMutableCStrings(environmentStrings) { environmentPointers in
                posix_spawn(
                    &processID,
                    executableURL.path,
                    &fileActions,
                    &attributes,
                    argumentPointers,
                    environmentPointers
                )
            }
        }
        try checkPOSIX(result)
        return processID
    }

    private static func waitForProcess(_ processID: pid_t) -> Int32 {
        var waitStatus: Int32 = 0
        var result: pid_t
        repeat {
            result = waitpid(processID, &waitStatus, 0)
        } while result == -1 && errno == EINTR

        guard result == processID else { return Int32(errno) }
        let terminationSignal = waitStatus & 0x7f
        if terminationSignal == 0 {
            return (waitStatus >> 8) & 0xff
        }
        return 128 + terminationSignal
    }

    private static func withMutableCStrings<Result>(
        _ strings: [String],
        body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> Result
    ) throws -> Result {
        var pointers: [UnsafeMutablePointer<CChar>?] = []
        pointers.reserveCapacity(strings.count + 1)
        defer {
            for pointer in pointers where pointer != nil {
                free(pointer)
            }
        }
        for string in strings {
            guard let pointer = strdup(string) else {
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(ENOMEM),
                    userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(ENOMEM))]
                )
            }
            pointers.append(pointer)
        }
        pointers.append(nil)
        return try pointers.withUnsafeMutableBufferPointer { buffer in
            try body(buffer.baseAddress!)
        }
    }

    private static func checkPOSIX(_ result: Int32) throws {
        guard result == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(result))]
            )
        }
    }
}
