import AppKit
import Foundation
import Testing

private let packagedAppPath = ProcessInfo.processInfo.environment[
    "OKRA_DESKTOP_PACKAGED_APP_PATH"
]
private let packagedDMGPath = ProcessInfo.processInfo.environment[
    "OKRA_DESKTOP_PACKAGED_DMG_PATH"
]

@MainActor
struct PackagedAppLaunchTests {
    @Test(
        "Packaged app remains alive without builder-only resources",
        .disabled(if: packagedAppPath == nil, "Runs after build-dmg.sh"),
        .tags(.packaging, .smoke),
        .timeLimit(.minutes(1))
    )
    func packagedAppRemainsAlive() async throws {
        let appPath = try #require(packagedAppPath)
        let appURL = URL(fileURLWithPath: appPath, isDirectory: true)
        try verifyBundleLayout(at: appURL)
        let resourceIsolation = try ResourceFallbackIsolation.fromEnvironment()
        defer { resourceIsolation?.restore() }

        let workspace = try TestWorkspace(prefix: "okra-packaged-launch")
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
        let executableURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("Okra")
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.environment = isolatedEnvironment(home: workspace.root)

        try process.run()
        try await Task.sleep(for: .seconds(3))
        let remainedRunning = process.isRunning

        if remainedRunning {
            process.terminate()
            try await waitUntil("packaged app process to terminate") {
                process.isRunning == false
            }
        } else {
            let output = String(
                decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            #if compiler(>=6.2)
            Attachment.record(output, named: "Packaged app launch output")
            #endif
        }

        #expect(
            remainedRunning,
            "The packaged app terminated during its three-second startup grace period."
        )
    }

    @Test(
        "Quarantined DMG launches through LaunchServices",
        .disabled(if: packagedDMGPath == nil, "Runs after the final DMG is packaged"),
        .tags(.packaging, .smoke),
        .timeLimit(.minutes(1))
    )
    func quarantinedDMGLaunchesThroughLaunchServices() async throws {
        let dmgPath = try #require(packagedDMGPath)
        let workspace = try TestWorkspace(prefix: "okra-dmg-launch")
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
        let copiedDMG = workspace.root.appendingPathComponent("Okra.dmg")
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: dmgPath),
            to: copiedDMG
        )
        try runCommand(
            URL(fileURLWithPath: "/usr/bin/xattr"),
            arguments: [
                "-w",
                "com.apple.quarantine",
                "0083;6696e1a0;Safari;D1A3A2E0-7D6E-4FE5-A8A4-2E9D2F2CFA01",
                copiedDMG.path,
            ]
        )

        let mountURL = workspace.root.appendingPathComponent("mount", isDirectory: true)
        try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
        try runCommand(
            URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: [
                "attach", copiedDMG.path,
                "-nobrowse", "-readonly",
                "-mountpoint", mountURL.path,
            ]
        )
        defer {
            _ = try? runCommand(
                URL(fileURLWithPath: "/usr/bin/hdiutil"),
                arguments: ["detach", "-force", mountURL.path]
            )
        }

        try verifyDMGPresentation(at: mountURL)
        let appURL = mountURL.appendingPathComponent("Okra.app", isDirectory: true)
        try verifyBundleLayout(at: appURL)
        let resourceIsolation = try ResourceFallbackIsolation.fromEnvironment()
        defer { resourceIsolation?.restore() }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true
        configuration.environment = isolatedEnvironment(home: workspace.root)
        let launchStartedAt = Date()
        let runningApplication = try await NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration
        )
        defer {
            if runningApplication.isTerminated == false {
                runningApplication.forceTerminate()
            }
        }

        try await Task.sleep(for: .seconds(3))

        if runningApplication.isTerminated {
            attachMostRecentCrashReport(since: launchStartedAt)
        }
        #expect(runningApplication.isTerminated == false)
        #expect(runningApplication.bundleIdentifier == "com.okrapdf.desktop")
        runningApplication.forceTerminate()
        try await waitUntil("DMG app process to terminate") {
            runningApplication.isTerminated
        }
    }

    private func verifyBundleLayout(at appURL: URL) throws {
        let fileManager = FileManager.default
        let executableURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("Okra")
        let providerScriptsURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("okraPDF_Okra.bundle", isDirectory: true)
            .appendingPathComponent("ProviderScripts", isDirectory: true)
        let brandMarkURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("okraPDF_Okra.bundle", isDirectory: true)
            .appendingPathComponent("AppIcon.png")
        let bundle = try #require(Bundle(url: appURL))

        try #require(fileManager.isExecutableFile(atPath: executableURL.path))
        try #require(fileManager.fileExists(atPath: providerScriptsURL.path))
        try #require(
            fileManager.fileExists(
                atPath: providerScriptsURL.appendingPathComponent("dots-ocr-worker.py").path
            )
        )
        try #require(
            fileManager.fileExists(
                atPath: providerScriptsURL.appendingPathComponent("install-dots-ocr.sh").path
            )
        )
        try #require(fileManager.fileExists(atPath: brandMarkURL.path))
        #expect(bundle.bundleIdentifier == "com.okrapdf.desktop")
        #expect(bundle.object(forInfoDictionaryKey: "LSUIElement") == nil)
    }

    private func verifyDMGPresentation(at mountURL: URL) throws {
        let fileManager = FileManager.default
        let applicationsURL = mountURL.appendingPathComponent("Applications")
        let applicationsAttributes = try fileManager.attributesOfItem(
            atPath: applicationsURL.path
        )
        let applicationsType = applicationsAttributes[.type] as? FileAttributeType
        let applicationsDestination = try fileManager.destinationOfSymbolicLink(
            atPath: applicationsURL.path
        )

        #expect(applicationsType == .typeSymbolicLink)
        #expect(applicationsDestination == "/Applications")
        let finderMetadataURL = mountURL.appendingPathComponent(".DS_Store")
        let finderMetadataAttributes = try fileManager.attributesOfItem(
            atPath: finderMetadataURL.path
        )
        let finderMetadataSize = finderMetadataAttributes[.size] as? NSNumber
        #expect(
            (finderMetadataSize?.intValue ?? 0) > 0,
            "The DMG should preserve its Finder window and icon layout."
        )
    }

    private func isolatedEnvironment(home: URL) -> [String: String] {
        ProcessInfo.processInfo.environment.merging([
            "CFFIXED_USER_HOME": home.path,
            "HOME": home.path,
        ]) { _, isolatedValue in
            isolatedValue
        }
    }

    private func attachMostRecentCrashReport(since launchDate: Date) {
        let diagnosticReportsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let reports = try? FileManager.default.contentsOfDirectory(
            at: diagnosticReportsURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let reportURL = reports
            .filter { $0.lastPathComponent.hasPrefix("Okra-") && $0.pathExtension == "ips" }
            .compactMap { url -> (URL, Date)? in
                guard let values = try? url.resourceValues(forKeys: resourceKeys),
                      values.isRegularFile == true,
                      let modifiedAt = values.contentModificationDate,
                      modifiedAt >= launchDate.addingTimeInterval(-1) else {
                    return nil
                }
                return (url, modifiedAt)
            }
            .max { $0.1 < $1.1 }?
            .0

        guard let reportURL, let report = try? String(contentsOf: reportURL, encoding: .utf8) else {
            return
        }
        #if compiler(>=6.2)
        Attachment.record(report, named: reportURL.lastPathComponent)
        #endif
    }

    @discardableResult
    private func runCommand(
        _ executableURL: URL,
        arguments: [String],
        timeout: TimeInterval = 15
    ) throws -> String {
        let outputPipe = Pipe()
        let process = Process()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            throw PackagedAppTestError.commandTimedOut(
                executableURL.lastPathComponent,
                timeout
            )
        }

        let output = String(
            decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        guard process.terminationStatus == 0 else {
            throw PackagedAppTestError.commandFailed(
                executableURL.lastPathComponent,
                process.terminationStatus,
                output
            )
        }
        return output
    }
}

private enum PackagedAppTestError: Error {
    case commandFailed(String, Int32, String)
    case commandTimedOut(String, TimeInterval)
    case missingResourceFallback(String)
}

private final class ResourceFallbackIsolation {
    private let originalURL: URL
    private let heldURL: URL
    private var isRestored = false

    static func fromEnvironment() throws -> ResourceFallbackIsolation? {
        guard let path = ProcessInfo.processInfo.environment[
            "OKRA_DESKTOP_RESOURCE_BUNDLE_FALLBACK_PATH"
        ] else {
            return nil
        }
        return try ResourceFallbackIsolation(originalURL: URL(fileURLWithPath: path))
    }

    private init(originalURL: URL) throws {
        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            throw PackagedAppTestError.missingResourceFallback(originalURL.path)
        }
        self.originalURL = originalURL
        heldURL = originalURL.deletingLastPathComponent()
            .appendingPathComponent("okraPDF_Okra.bundle.startup-smoke-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: originalURL, to: heldURL)
    }

    deinit {
        restore()
    }

    func restore() {
        guard isRestored == false else { return }
        isRestored = true
        try? FileManager.default.moveItem(at: heldURL, to: originalURL)
    }
}
