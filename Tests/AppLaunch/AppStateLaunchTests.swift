import Foundation
import Testing
@testable import Okra

@MainActor
struct AppStateLaunchTests {
    @Test("Default startup constructs every bundled provider")
    func defaultStartupConstructsBundledProviders() throws {
        let workspace = try TestWorkspace(prefix: "okra-default-launch")

        let coordinator = LocalProcessingCoordinator(
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults,
            hostProfile: supportedDotsHost
        )
        let state = AppState(localProcessing: coordinator)

        #expect(
            coordinator.descriptors.map(\.id)
                == [.appleVision, .hybridAuto, .dotsOCR, .unlimitedOCR, .ollama]
        )
        #expect(coordinator.selectedProviderID == .dotsOCR)
        #expect(state.selectedDocument == nil)
    }

    @Test("Stored Docling selection falls back to Dots OCR")
    func storedDoclingSelectionFallsBack() throws {
        let workspace = try TestWorkspace(prefix: "okra-removed-docling-provider")
        workspace.defaults.set("docling", forKey: "localProcessing.selectedProvider")

        let coordinator = LocalProcessingCoordinator(
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults,
            hostProfile: supportedDotsHost
        )

        #expect(coordinator.selectedProviderID == .dotsOCR)
        #expect(coordinator.selectedDescriptor.id == .dotsOCR)
        #expect(coordinator.selectedAvailability == .setupRequired("Setup required · ~3.5 GB"))
    }

    private var supportedDotsHost: LocalParserHostProfile {
        LocalParserHostProfile(
            architecture: .appleSilicon,
            macOSMajorVersion: 14,
            unifiedMemoryGB: 16,
            availableDiskBytes: 5_000_000_000
        )
    }

    @Test("Corrupt run manifests are skipped during startup")
    func corruptRunManifestsAreSkipped() throws {
        let workspace = try TestWorkspace(prefix: "okra-corrupt-history")
        let corruptRunDirectory = workspace.runsRoot
            .appendingPathComponent("corrupt-run", isDirectory: true)
        try FileManager.default.createDirectory(
            at: corruptRunDirectory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(
            to: corruptRunDirectory.appendingPathComponent("run.json")
        )

        let coordinator = LocalProcessingCoordinator(
            providers: [FixtureProcessingProvider()],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )

        #expect(coordinator.recentRuns.isEmpty)
        #expect(coordinator.selectedAvailability == .ready)
    }

    @Test("Startup marks orphaned work interrupted and reopening restores progress")
    func startupRecoversOrphanedRun() throws {
        let workspace = try TestWorkspace(prefix: "okra-orphaned-run")
        let sourceURL = workspace.root.appendingPathComponent("unfinished.pdf")
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: sourceURL)
        let runDirectory = workspace.runsRoot.appendingPathComponent("run-interrupted", isDirectory: true)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let orphanedRun = LocalProcessingRun(
            id: "run-interrupted",
            sourcePath: sourceURL.path,
            fileName: sourceURL.lastPathComponent,
            providerId: "apple-vision",
            providerName: "Apple Vision",
            executionMode: "local",
            status: "running",
            outputPath: nil,
            errorMessage: nil,
            pageCount: 4,
            completedPageCount: 4,
            totalPageCount: 10,
            startedAt: startedAt,
            completedAt: nil,
            progress: 0.4,
            statusMessage: "Recognizing scanned page 5 of 10",
            updatedAt: startedAt,
            eventSequence: 7
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(orphanedRun).write(
            to: runDirectory.appendingPathComponent("run.json"),
            options: .atomic
        )

        let coordinator = LocalProcessingCoordinator(
            providers: [FixtureProcessingProvider()],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        let document = LocalPDFDocument(
            id: sourceURL.path,
            fileName: sourceURL.lastPathComponent,
            filePath: sourceURL.path,
            totalPages: 10
        )
        coordinator.load(document: document)

        let recovered = try #require(coordinator.latestRun)
        #expect(recovered.status == "interrupted")
        #expect(recovered.completedPageCount == 4)
        #expect(recovered.progress == 0.4)
        #expect(recovered.eventSequence == 8)
        #expect(coordinator.completedPageCount == 4)
        #expect(coordinator.totalPageCount == 10)
        #expect(coordinator.statusMessage.contains("interrupted"))
        #expect(coordinator.pageLifecycles.prefix(4).allSatisfy { $0.state == .done })
        #expect(coordinator.pageLifecycles[4].state == .attention)
        #expect(coordinator.canResumeLatestRun)
    }
}
