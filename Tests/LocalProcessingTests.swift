import AppKit
import Foundation
import PDFKit
import Testing
@testable import Okra

@MainActor
struct LocalProcessingProviderTests {
    @Test("Apple Vision is ready without setup")
    func appleVisionIsReadyWithoutSetup() {
        let provider = AppleVisionProcessingProvider()

        #expect(provider.descriptor.id == .appleVision)
        #expect(provider.availability() == .ready)
    }

    @Test("Dots OCR simulation is clearly reported as simulation")
    func dotsOCRSimulationIsClearlyReportedAsSimulation() {
        let provider = DotsOCRProcessingProvider(
            environment: ["OKRA_DESKTOP_SIMULATE_DOTS_OCR": "1"]
        )

        #expect(provider.descriptor.name == "Dots OCR 1.5")
        #expect(provider.availability() == .simulated("Simulation ready"))
    }

    @Test("Dots OCR is selected by default")
    func simulationModeDefaultsToDotsOCR() throws {
        let workspace = try TestWorkspace(prefix: "okra-simulation-selection")
        let simulatedProvider = DotsOCRProcessingProvider(
            environment: ["OKRA_DESKTOP_SIMULATE_DOTS_OCR": "1"]
        )
        let coordinator = LocalProcessingCoordinator(
            providers: [FixtureProcessingProvider(), simulatedProvider],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )

        #expect(coordinator.selectedProviderID == .dotsOCR)
        #expect(coordinator.selectedAvailability == .simulated("Simulation ready"))
    }

    @Test("A stored Baidu provider choice remains explicit")
    func storedBaiduProviderRemainsSelected() throws {
        let workspace = try TestWorkspace(prefix: "okra-stored-baidu-selection")
        workspace.defaults.set(
            LocalProviderID.unlimitedOCR.rawValue,
            forKey: "localProcessing.selectedProvider"
        )
        let simulatedProvider = DotsOCRProcessingProvider(
            environment: ["OKRA_DESKTOP_SIMULATE_DOTS_OCR": "1"]
        )
        let coordinator = LocalProcessingCoordinator(
            providers: [FixtureProcessingProvider(), simulatedProvider, SetupFixtureProvider()],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )

        #expect(coordinator.selectedProviderID == .unlimitedOCR)
        #expect(coordinator.selectedAvailability == .setupRequired("Setup required"))
        #expect(
            workspace.defaults.string(forKey: "localProcessing.selectedProvider")
                == LocalProviderID.unlimitedOCR.rawValue
        )
    }

    @Test("An incompatible Mac falls back from Dots OCR to Apple Vision")
    func incompatibleMacFallsBackToAppleVision() throws {
        let workspace = try TestWorkspace(prefix: "okra-incompatible-dots-selection")
        let incompatibleProvider = DotsOCRProcessingProvider(
            environment: [:],
            hostProfile: LocalParserHostProfile(
                architecture: .intel,
                macOSMajorVersion: 13,
                unifiedMemoryGB: 8,
                availableDiskBytes: 1_000_000_000
            )
        )
        let coordinator = LocalProcessingCoordinator(
            providers: [FixtureProcessingProvider(), incompatibleProvider],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )

        #expect(coordinator.selectedProviderID == .appleVision)
        #expect(
            coordinator.availabilityByProvider[.dotsOCR]?.message
                .contains("requires Apple silicon") == true
        )
    }

    @Test("Run directory uses only the run identifier")
    func runDirectoryUsesOnlyTheRunIdentifier() {
        let root = URL(fileURLWithPath: "/tmp/okra-runs", isDirectory: true)

        #expect(
            LocalProviderPaths.runDirectory(runsRoot: root, runID: "run-1").path
                == "/tmp/okra-runs/run-1"
        )
    }

    @Test("Default runs root uses the Okra application support namespace")
    func defaultRunsRootUsesOkraApplicationSupportNamespace() {
        let applicationSupport = URL(
            fileURLWithPath: "/tmp/Application Support",
            isDirectory: true
        )

        #expect(
            LocalProviderPaths.runsRoot(applicationSupportDirectory: applicationSupport).path
                == "/tmp/Application Support/Okra/Runs"
        )
    }

    @Test("Coordinator writes Markdown and its run manifest", .timeLimit(.minutes(1)))
    func coordinatorWritesMarkdownAndRunManifest() async throws {
        let workspace = try TestWorkspace(prefix: "okra-run")
        let sourceURL = workspace.root.appendingPathComponent("sample.pdf")
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: sourceURL)

        let coordinator = LocalProcessingCoordinator(
            providers: [FixtureProcessingProvider()],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        let document = LocalPDFDocument(
            id: sourceURL.path,
            fileName: sourceURL.lastPathComponent,
            filePath: sourceURL.path,
            totalPages: 1
        )

        coordinator.load(document: document)
        coordinator.run(document: document)
        try await waitUntil("fixture parsing to finish") { coordinator.isRunning == false }

        let run = try #require(coordinator.latestRun)
        #expect(run.status == "succeeded")
        #expect(run.sourcePath == sourceURL.path)
        #expect(coordinator.outputText == "# Parsed\n")

        let runDirectory = workspace.runsRoot.appendingPathComponent(run.id, isDirectory: true)
        let manifestData = try Data(contentsOf: runDirectory.appendingPathComponent("run.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persisted = try decoder.decode(LocalProcessingRun.self, from: manifestData)

        #expect(persisted.id == run.id)
        #expect(persisted.sourcePath == run.sourcePath)
        #expect(persisted.providerId == run.providerId)
        #expect(persisted.executionMode == "local")
        #expect(persisted.status == "succeeded")
        #expect(persisted.outputPath == run.outputPath)
        #expect(persisted.completedAt != nil)
        #expect(
            FileManager.default.fileExists(
                atPath: runDirectory.appendingPathComponent("result.md").path
            )
        )
    }

    @Test("Page progress is persisted while extraction is still running", .timeLimit(.minutes(1)))
    func pageProgressPersistsDuringExtraction() async throws {
        let workspace = try TestWorkspace(prefix: "okra-live-page-progress")
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
        let sourceURL = workspace.root.appendingPathComponent("large.pdf")
        try Data("pdf".utf8).write(to: sourceURL)
        let pageCount = 3
        let coordinator = LocalProcessingCoordinator(
            providers: [IncrementalFixtureProcessingProvider(pageCount: pageCount)],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        let document = LocalPDFDocument(
            id: sourceURL.path,
            fileName: sourceURL.lastPathComponent,
            filePath: sourceURL.path,
            totalPages: pageCount
        )

        coordinator.run(document: document)
        try await waitUntil("first page checkpoint to be persisted") {
            coordinator.completedPageCount == 1
        }

        let activeRun = try #require(coordinator.latestRun)
        let runDirectory = workspace.runsRoot.appendingPathComponent(
            activeRun.id,
            isDirectory: true
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persistedDuringRun = try decoder.decode(
            LocalProcessingRun.self,
            from: Data(contentsOf: runDirectory.appendingPathComponent("run.json"))
        )
        #expect(coordinator.isRunning)
        #expect(persistedDuringRun.status == "running")
        #expect(persistedDuringRun.completedPageCount == 1)
        #expect(persistedDuringRun.totalPageCount == pageCount)
        #expect(persistedDuringRun.pageCount == 1)
        #expect(
            FileManager.default.fileExists(
                atPath: runDirectory
                    .appendingPathComponent("page-results/page-0001.md")
                    .path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: runDirectory.appendingPathComponent("result.md").path
            ) == false
        )

        try await waitUntil("incremental extraction to finish") {
            coordinator.isRunning == false
        }
        #expect(coordinator.completedPageCount == pageCount)
        #expect(coordinator.progress == 1)
    }

    @Test(
        "Cancel intent is durable and the same run resumes from its page checkpoint",
        .timeLimit(.minutes(1))
    )
    func cancelAndResumeRunFromCheckpoint() async throws {
        let workspace = try TestWorkspace(prefix: "okra-cancel-resume")
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
        let sourceURL = workspace.root.appendingPathComponent("large.pdf")
        try Data("pdf".utf8).write(to: sourceURL)
        let document = LocalPDFDocument(
            id: sourceURL.path,
            fileName: sourceURL.lastPathComponent,
            filePath: sourceURL.path,
            totalPages: 3
        )
        let coordinator = LocalProcessingCoordinator(
            providers: [ResumableFixtureProcessingProvider(pageCount: 3)],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )

        coordinator.load(document: document)
        coordinator.run(document: document)
        try await waitUntil("first durable page") {
            coordinator.completedPageCount == 1
        }

        let activeRun = try #require(coordinator.latestRun)
        let runDirectory = workspace.runsRoot.appendingPathComponent(activeRun.id, isDirectory: true)
        let firstPageURL = runDirectory.appendingPathComponent("page-results/page-0001.md")
        let firstPageBeforeResume = try Data(contentsOf: firstPageURL)
        let firstPageModifiedAt = try #require(
            try firstPageURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        )

        coordinator.cancelRun()
        try await waitUntil("run cancellation") { coordinator.isRunning == false }

        let canceledRun = try #require(coordinator.latestRun)
        #expect(canceledRun.status == "canceled")
        #expect(canceledRun.cancelRequestedAt != nil)
        #expect(canceledRun.completedPageCount == 1)
        #expect(canceledRun.progress == 1.0 / 3.0)
        let eventLines = try String(
            contentsOf: runDirectory.appendingPathComponent("events.jsonl"),
            encoding: .utf8
        ).split(separator: "\n")
        let cancelRequestedIndex = try #require(
            eventLines.firstIndex { $0.contains("run.cancel_requested") }
        )
        let canceledIndex = try #require(
            eventLines.firstIndex { $0.contains("run.canceled") }
        )
        #expect(cancelRequestedIndex < canceledIndex)

        let reopened = LocalProcessingCoordinator(
            providers: [ResumableFixtureProcessingProvider(pageCount: 3, pauseAfterPage: .milliseconds(10))],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        reopened.load(document: document)
        #expect(reopened.latestRun?.id == canceledRun.id)
        #expect(reopened.latestRun?.status == "canceled")
        #expect(reopened.canResumeLatestRun)

        reopened.resume(document: document)
        try await waitUntil("resumed extraction") { reopened.isRunning == false }

        let resumedRun = try #require(reopened.latestRun)
        #expect(resumedRun.id == canceledRun.id)
        #expect(resumedRun.status == "succeeded")
        #expect(resumedRun.resumeCount == 1)
        #expect(resumedRun.completedPageCount == 3)
        #expect(reopened.pageLifecycles.allSatisfy { $0.state == .done })
        #expect(try Data(contentsOf: firstPageURL) == firstPageBeforeResume)
        #expect(
            try firstPageURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                == firstPageModifiedAt
        )
    }

    @Test("Opening a PDF does not start extraction")
    func openingPDFDoesNotStartExtraction() throws {
        let workspace = try TestWorkspace(prefix: "okra-open")
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
        let pdfURL = workspace.root.appendingPathComponent("read-first.pdf")
        try makePDF(pageTexts: ["Read before parsing"]).write(to: pdfURL)

        let coordinator = LocalProcessingCoordinator(
            providers: [FixtureProcessingProvider()],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        let state = AppState(localProcessing: coordinator)

        state.openPDF(pdfURL)

        #expect(state.selectedDocument?.fileName == "read-first.pdf")
        #expect(state.selectedDocument?.totalPages == 1)
        #expect(coordinator.latestRun == nil)
        #expect(coordinator.isRunning == false)
        #expect(FileManager.default.fileExists(atPath: workspace.runsRoot.path) == false)
    }

    @Test("An active local operation cannot be displaced by another PDF", .timeLimit(.minutes(1)))
    func activeRunBlocksDocumentReplacement() async throws {
        let workspace = try TestWorkspace(prefix: "okra-open-guard")
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
        let sourceURL = workspace.root.appendingPathComponent("active.pdf")
        let replacementURL = workspace.root.appendingPathComponent("replacement.pdf")
        try makePDF(pageTexts: ["Active page 1", "Active page 2"]).write(to: sourceURL)
        try makePDF(pageTexts: ["Replacement"]).write(to: replacementURL)

        let coordinator = LocalProcessingCoordinator(
            providers: [
                IncrementalFixtureProcessingProvider(
                    pageCount: 2,
                    pauseAfterFirstPage: .seconds(2)
                ),
            ],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        let state = AppState(localProcessing: coordinator)
        state.openPDF(sourceURL)
        state.parseSelectedDocument()

        #expect(coordinator.isRunning)
        #expect(state.canOpenPDF == false)

        state.openPDF(replacementURL)

        #expect(state.selectedDocument?.filePath == sourceURL.path)
        #expect(state.importError?.contains("active local operation") == true)

        state.dismissImportError()
        #expect(state.importError == nil)

        coordinator.cancelRun()
        try await waitUntil("active run cancellation") { coordinator.isRunning == false }
        #expect(state.canOpenPDF)

        state.openPDF(replacementURL)
        #expect(state.selectedDocument?.filePath == replacementURL.path)
    }

    @Test("Explicit Parse starts the selected document", .timeLimit(.minutes(1)))
    func explicitParseActionStartsSelectedDocument() async throws {
        let workspace = try TestWorkspace(prefix: "okra-explicit-parse")
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
        let pdfURL = workspace.root.appendingPathComponent("explicit.pdf")
        try makePDF(pageTexts: ["Parse after click"]).write(to: pdfURL)

        let coordinator = LocalProcessingCoordinator(
            providers: [FixtureProcessingProvider()],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        let state = AppState(localProcessing: coordinator)
        state.openPDF(pdfURL)

        state.parseSelectedDocument()
        try await waitUntil("explicit parsing to finish") { coordinator.isRunning == false }

        #expect(coordinator.latestRun?.status == "succeeded")
        #expect(coordinator.outputText == "# Parsed\n")
    }

    @Test(
        "Dots OCR 1.5 simulation completes the PDF workflow",
        .tags(.smoke),
        .timeLimit(.minutes(1))
    )
    func dotsOCREndToEndSimulationOnPDF() async throws {
        let workspace = try TestWorkspace(prefix: "okra-dots-e2e")
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)

        let pdfURL: URL
        let expectedPageCount: Int
        if let suppliedPath = ProcessInfo.processInfo.environment["OKRA_DESKTOP_E2E_PDF"] {
            pdfURL = URL(fileURLWithPath: suppliedPath).standardizedFileURL
            let suppliedPDF = try #require(PDFDocument(url: pdfURL))
            expectedPageCount = suppliedPDF.pageCount
            try #require(expectedPageCount > 0)
        } else {
            pdfURL = workspace.root.appendingPathComponent("two-page-scan.pdf")
            try makePDF(pageTexts: ["Invoice 1042", "Total due 49.00"]).write(to: pdfURL)
            expectedPageCount = 2
        }

        let provider = DotsOCRProcessingProvider(
            environment: ["OKRA_DESKTOP_SIMULATE_DOTS_OCR": "1"]
        )
        let coordinator = LocalProcessingCoordinator(
            providers: [provider],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        let document = LocalPDFDocument(
            id: pdfURL.path,
            fileName: pdfURL.lastPathComponent,
            filePath: pdfURL.path,
            totalPages: expectedPageCount
        )

        coordinator.load(document: document)
        #expect(coordinator.selectedAvailability == .simulated("Simulation ready"))
        coordinator.run(document: document)
        try await waitUntil("simulated Dots parsing to finish") { coordinator.isRunning == false }

        let run = try #require(coordinator.latestRun)
        #expect(run.status == "succeeded")
        #expect(run.providerId == "dots-ocr")
        #expect(run.providerName == "Dots OCR 1.5")
        #expect(run.executionMode == "simulation")
        #expect(run.pageCount == expectedPageCount)
        #expect(coordinator.progress == 1)
        #expect(coordinator.completedPageCount == expectedPageCount)
        #expect(coordinator.totalPageCount == expectedPageCount)
        #expect(coordinator.pageLifecycles.count == expectedPageCount)
        #expect(coordinator.pageLifecycles.allSatisfy { $0.state == .done })
        #expect(coordinator.pageLifecycles.allSatisfy { $0.parserID == "dots-ocr" })
        #expect(coordinator.statusMessage == "Simulation complete · model weights were not loaded.")
        #expect(
            coordinator.outputText.contains(
                "Simulation: Dots OCR 1.5 model weights were not loaded."
            )
        )
        #expect(coordinator.outputText.contains("HF_HUB_OFFLINE=1"))
        #expect(coordinator.outputText.contains("TRANSFORMERS_OFFLINE=1"))
        #expect(coordinator.outputText.contains("HF_DATASETS_OFFLINE=1"))
        #expect(coordinator.outputText.contains("## Page 1"))
        #expect(coordinator.outputText.contains("## Page \(expectedPageCount)"))
        #expect(coordinator.structuredOutput?.provider.id == "dots-ocr")
        #expect(coordinator.structuredOutput?.pageCount == expectedPageCount)
        #expect(coordinator.structuredOutput?.completedPageCount == expectedPageCount)
        #expect(coordinator.structuredOutput?.complete == true)
        #expect(coordinator.structuredOutput?.simulation == true)
        #expect(coordinator.pdfBoundingBoxOverlays.count == expectedPageCount * 2)
        #expect(
            coordinator.pdfBoundingBoxOverlays.map(\.pageNumber)
                == (1...expectedPageCount).flatMap { [$0, $0] }
        )

        let firstOverlay = try #require(coordinator.pdfBoundingBoxOverlays.first)
        coordinator.showsPDFBoundingBoxes = false
        coordinator.selectStructuredBlock(firstOverlay.id)
        #expect(coordinator.selectedStructuredBlockID == firstOverlay.id)
        #expect(coordinator.showsPDFBoundingBoxes)
        coordinator.hoverStructuredBlock(firstOverlay.id, isHovering: true)
        #expect(coordinator.hoveredStructuredBlockID == firstOverlay.id)
        #expect(coordinator.previewHoveredStructuredBlockID == firstOverlay.id)
        coordinator.hoverStructuredBlock(firstOverlay.id, isHovering: false)
        coordinator.hoverPDFOverlay(firstOverlay.id)
        #expect(coordinator.hoveredStructuredBlockID == firstOverlay.id)
        #expect(coordinator.previewHoveredStructuredBlockID == nil)
        coordinator.hoverPDFOverlay(nil)
        #expect(coordinator.hoveredStructuredBlockID == nil)

        let runDirectory = workspace.runsRoot.appendingPathComponent(run.id, isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("run.json").path))
        #expect(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("result.md").path))
        #expect(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("result.json").path))
        #expect(
            FileManager.default.fileExists(
                atPath: runDirectory.appendingPathComponent("pages/page-0001.png").path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: runDirectory
                    .appendingPathComponent(String(format: "pages/page-%04d.png", expectedPageCount))
                    .path
            )
        )
        let pageStore = LocalPageCheckpointStore(
            outputDirectory: runDirectory,
            totalPages: expectedPageCount,
            documentHeader: "# \(pdfURL.lastPathComponent)"
        )
        let pageManifest = try pageStore.loadManifest()
        #expect(pageManifest.completedPageCount == expectedPageCount)
        #expect(pageManifest.currentPageStatus == .succeeded)
        #expect(pageManifest.lastCompletedPageNumber == expectedPageCount)
        #expect(
            FileManager.default.fileExists(
                atPath: pageStore.pageURL(pageNumber: expectedPageCount).path
            )
        )

        let manifestData = try Data(contentsOf: runDirectory.appendingPathComponent("run.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persisted = try decoder.decode(LocalProcessingRun.self, from: manifestData)
        #expect(persisted.executionMode == "simulation")
        #expect(persisted.status == "succeeded")
        #expect(persisted.pageLifecycles?.allSatisfy { $0.state == .done } == true)
        #expect(persisted.structuredOutputPath == runDirectory.appendingPathComponent("result.json").path)

        let reopened = LocalProcessingCoordinator(
            providers: [provider],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        reopened.load(document: document)
        #expect(reopened.latestRun?.id == run.id)
        #expect(reopened.pageLifecycles.allSatisfy { $0.state == .done })
        #expect(reopened.pdfBoundingBoxOverlays.count == expectedPageCount * 2)
        #expect(reopened.selectedStructuredBlockID == nil)
    }

    @Test("Apple Vision writes structured native-text boxes and exposes hover state", .timeLimit(.minutes(1)))
    func appleVisionWritesStructuredNativeTextBoxes() async throws {
        let workspace = try TestWorkspace(prefix: "okra-vision")
        try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)

        let page = NSView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        let label = NSTextField(labelWithString: "Local extraction sample")
        label.font = .systemFont(ofSize: 32)
        label.frame = NSRect(x: 72, y: 640, width: 468, height: 60)
        page.addSubview(label)
        let pdfData = page.dataWithPDF(inside: page.bounds)
        let sourceDocument = try #require(PDFDocument(data: pdfData))
        let sourcePage = try #require(sourceDocument.page(at: 0))
        sourcePage.setBounds(
            CGRect(x: 40, y: 40, width: 532, height: 700),
            for: .cropBox
        )
        sourcePage.rotation = 90
        let pdfURL = workspace.root.appendingPathComponent("sample.pdf")
        try #require(sourceDocument.dataRepresentation()).write(to: pdfURL)

        let result = try await AppleVisionProcessingProvider().process(
            request: LocalProcessingRequest(
                parserID: .appleVision,
                fileName: "sample.pdf",
                sourceURL: pdfURL,
                outputDirectory: workspace.root.appendingPathComponent("output", isDirectory: true),
                expectedPageCount: 1
            ),
            progress: { _, _ in }
        )

        let markdown = try String(contentsOf: result.outputURL, encoding: .utf8)
        #expect(result.pageCount == 1)
        #expect(markdown.contains("# sample.pdf"))
        #expect(markdown.contains("## Page 1"))
        #expect(markdown.contains("Local extraction sample"))
        let structuredOutputURL = try #require(result.structuredOutputURL)
        let structuredDocument = try StructuredExtractionDocument.load(from: structuredOutputURL)
        let structuredPage = try #require(structuredDocument.pages.first)
        let structuredBlock = try #require(structuredPage.blocks.first)
        let bbox = try #require(structuredBlock.bbox)
        #expect(structuredDocument.provider.id == "apple-vision")
        #expect(structuredDocument.complete)
        #expect(structuredBlock.sourceType == "pdf-text-line")
        #expect(structuredPage.blocks.allSatisfy { $0.bbox?.clippedNormalizedRect != nil })

        let reopenedSource = try #require(PDFDocument(url: pdfURL))
        let reopenedPage = try #require(reopenedSource.page(at: 0))
        let characterCount = (reopenedPage.string as NSString?)?.length ?? 0
        let selection = try #require(
            reopenedPage.selection(for: NSRange(location: 0, length: characterCount))?
                .selectionsByLine()
                .first
        )
        let expectedPageBounds = selection.bounds(for: reopenedPage)
            .intersection(reopenedPage.bounds(for: .cropBox))
        let actualPageBounds = try #require(
            PDFBoundingBoxGeometry.pageBounds(for: bbox, on: reopenedPage)
        )
        #expect(abs(actualPageBounds.minX - expectedPageBounds.minX) < 0.001)
        #expect(abs(actualPageBounds.minY - expectedPageBounds.minY) < 0.001)
        #expect(abs(actualPageBounds.width - expectedPageBounds.width) < 0.001)
        #expect(abs(actualPageBounds.height - expectedPageBounds.height) < 0.001)
        let pageStore = LocalPageCheckpointStore(
            outputDirectory: workspace.root.appendingPathComponent("output", isDirectory: true),
            totalPages: 1,
            documentHeader: "# sample.pdf"
        )
        let pageManifest = try pageStore.loadManifest()
        #expect(pageManifest.completedPageCount == 1)
        #expect(pageManifest.currentPageStatus == .succeeded)
        #expect(FileManager.default.fileExists(atPath: pageStore.pageURL(pageNumber: 1).path))
        #expect(
            FileManager.default.fileExists(
                atPath: pageStore.pageURL(pageNumber: 1)
                    .deletingPathExtension()
                    .appendingPathExtension("json")
                    .path
            )
        )

        let provider = AppleVisionProcessingProvider()
        let coordinator = LocalProcessingCoordinator(
            providers: [provider],
            runsRoot: workspace.runsRoot,
            userDefaults: workspace.defaults
        )
        let localDocument = LocalPDFDocument(
            id: pdfURL.path,
            fileName: pdfURL.lastPathComponent,
            filePath: pdfURL.path,
            totalPages: 1
        )
        coordinator.load(document: localDocument)
        coordinator.run(document: localDocument)
        try await waitUntil("Apple Vision parsing to finish") { coordinator.isRunning == false }

        let overlay = try #require(coordinator.pdfBoundingBoxOverlays.first)
        #expect(coordinator.latestRun?.providerId == "apple-vision")
        #expect(coordinator.structuredOutput?.provider.id == "apple-vision")
        #expect(coordinator.pageLifecycles.count == 1)
        #expect(coordinator.pageLifecycles.first?.state == .done)

        coordinator.showsPDFBoundingBoxes = false
        coordinator.hoverStructuredBlock(overlay.id, isHovering: true)
        #expect(coordinator.hoveredStructuredBlockID == overlay.id)
        #expect(coordinator.previewHoveredStructuredBlockID == overlay.id)
        #expect(coordinator.showsPDFBoundingBoxes == false)
        coordinator.hoverStructuredBlock(overlay.id, isHovering: false)
        #expect(coordinator.hoveredStructuredBlockID == nil)

        coordinator.showsPDFBoundingBoxes = true
        coordinator.hoverPDFOverlay(overlay.id)
        #expect(coordinator.hoveredStructuredBlockID == overlay.id)
        #expect(coordinator.previewHoveredStructuredBlockID == nil)
        coordinator.showsPDFBoundingBoxes = false
        #expect(coordinator.hoveredStructuredBlockID == nil)

        coordinator.selectStructuredBlock(overlay.id)
        #expect(coordinator.selectedStructuredBlockID == overlay.id)
        #expect(coordinator.showsPDFBoundingBoxes)
    }

    private func makePDF(pageTexts: [String]) throws -> Data {
        let document = PDFDocument()

        for (index, text) in pageTexts.enumerated() {
            let pageView = NSView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 30)
            label.frame = NSRect(x: 72, y: 640, width: 468, height: 60)
            pageView.addSubview(label)
            let pageData = pageView.dataWithPDF(inside: pageView.bounds)
            let pageDocument = try #require(PDFDocument(data: pageData))
            let page = try #require(pageDocument.page(at: 0))
            document.insert(page, at: index)
        }

        return try #require(document.dataRepresentation())
    }
}
