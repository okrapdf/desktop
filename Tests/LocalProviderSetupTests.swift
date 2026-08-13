import Foundation
import Testing
@testable import Okra

@MainActor
struct LocalProviderSetupTests {
    @Test("Setup publishes progress and finishes offline-ready")
    func setupLifecycle() async throws {
        let workspace = try TestWorkspace(prefix: "okra-setup")

        let coordinator = LocalProcessingCoordinator(
            providers: [SetupFixtureProvider()],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        coordinator.installSelectedProvider()
        try await waitUntil("provider setup to finish") { coordinator.isInstalling == false }

        #expect(coordinator.selectedAvailability == .ready)
        #expect(coordinator.setupProgress?.phase == .ready)
        #expect(coordinator.setupProgress?.fraction == 1)
        #expect(coordinator.setupErrorMessage == nil)
        #expect(coordinator.statusMessage == "Baidu Unlimited-OCR is ready offline.")
    }

    @Test("Canceled setup remains resumable")
    func canceledSetup() async throws {
        let workspace = try TestWorkspace(prefix: "okra-cancel")

        let coordinator = LocalProcessingCoordinator(
            providers: [SetupFixtureProvider(suspendsDuringDownload: true)],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        coordinator.installSelectedProvider()
        try await waitUntil("model download phase to begin") {
            coordinator.setupProgress?.phase == .downloadingModel
        }
        coordinator.cancelInstallation()
        try await waitUntil("provider setup cancellation to finish") {
            coordinator.isInstalling == false
        }

        #expect(coordinator.selectedAvailability.isReady == false)
        #expect(coordinator.setupProgress == nil)
        #expect(coordinator.setupErrorMessage == nil)
        #expect(coordinator.statusMessage == "Setup canceled. You can resume when you are ready.")
    }

    @Test("Recent runs are loaded newest first")
    func recentRuns() throws {
        let workspace = try TestWorkspace(prefix: "okra-history")
        try FileManager.default.createDirectory(at: workspace.runsRoot, withIntermediateDirectories: true)

        let older = makeRun(id: "older", startedAt: Date(timeIntervalSince1970: 100))
        let newer = makeRun(id: "newer", startedAt: Date(timeIntervalSince1970: 200))
        try write(older, to: workspace.runsRoot)
        try write(newer, to: workspace.runsRoot)

        let coordinator = LocalProcessingCoordinator(
            providers: [SetupFixtureProvider()],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )

        #expect(coordinator.recentRuns.map(\.id) == ["newer", "older"])
    }

    @Test("Pinned model manifest has a checksum for every byte")
    func modelManifest() {
        #expect(UnlimitedOCRModelManifest.artifacts.count == 8)
        #expect(UnlimitedOCRModelManifest.totalBytes == 2_461_271_624)
        #expect(UnlimitedOCRModelManifest.artifacts.allSatisfy { $0.sha256.count == 64 })
        #expect(Set(UnlimitedOCRModelManifest.artifacts.map(\.path)).count == 8)
    }

    @Test("Dots OCR manifest pins every required runtime artifact")
    func dotsOCRModelManifest() {
        #expect(DotsOCRModelManifest.artifacts.count == 15)
        #expect(DotsOCRModelManifest.totalBytes == 3_538_447_417)
        #expect(DotsOCRModelManifest.artifacts.allSatisfy { $0.sha256.count == 64 })
        #expect(Set(DotsOCRModelManifest.artifacts.map(\.path)).count == 15)
        #expect(
            DotsOCRModelManifest.artifacts.contains {
                $0.path == "model.safetensors"
                    && $0.size == 3_524_130_967
                    && $0.sha256
                        == "9310766f72e340f995e43662ccf55f5999e034ef85d9e8624a744574e624d0c5"
            }
        )
    }

    @Test("Dots OCR setup records the accepted model-license revision")
    func dotsOCRSetupRecordsLicenseAcceptance() async throws {
        let workspace = try TestWorkspace(prefix: "okra-dots-license")
        let provider = DotsOCRProcessingProvider(
            environment: ["OKRA_DESKTOP_SIMULATE_DOTS_OCR": "1"]
        )
        let coordinator = LocalProcessingCoordinator(
            providers: [provider],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )

        coordinator.installSelectedProvider()
        try await waitUntil("Dots OCR simulated setup to finish") {
            coordinator.isInstalling == false
        }

        #expect(
            workspace.defaults.string(
                forKey: LocalProcessingCoordinator.modelLicenseAcceptanceKey(
                    for: .dotsOCR
                )
            ) == DotsOCRModelManifest.package.licenseRevision
        )
    }

    @Test("Setup progress clamps determinate values", arguments: [-1.0, 0.42, 2.0])
    func progressClamping(input: Double) {
        let progress = LocalProviderSetupProgress(
            phase: .downloadingModel,
            fraction: input,
            message: "Downloading"
        )
        #expect(progress.fraction == min(max(input, 0), 1))
    }

    private func makeRun(id: String, startedAt: Date) -> LocalProcessingRun {
        LocalProcessingRun(
            id: id,
            sourcePath: "/tmp/\(id).pdf",
            fileName: "\(id).pdf",
            providerId: "unlimited-ocr",
            providerName: "Baidu Unlimited-OCR",
            executionMode: "local",
            status: "succeeded",
            outputPath: nil,
            errorMessage: nil,
            pageCount: 1,
            startedAt: startedAt,
            completedAt: startedAt
        )
    }

    private func write(_ run: LocalProcessingRun, to root: URL) throws {
        let runDirectory = root.appendingPathComponent(run.id, isDirectory: true)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(run).write(to: runDirectory.appendingPathComponent("run.json"))
    }
}
