import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class LocalProcessingCoordinator: ObservableObject {
    @Published var selectedProviderID: LocalProviderID {
        didSet {
            userDefaults.set(selectedProviderID.rawValue, forKey: Self.providerDefaultsKey)
            refreshAvailability()
            guard !isRunning, !isInstalling else { return }
            setupProgress = nil
            setupErrorMessage = nil
            statusMessage = selectedAvailability.isReady
                ? "\(selectedDescriptor.name) is ready offline."
                : selectedAvailability.message
            progress = 0
            if latestRun == nil, totalPageCount > 0 {
                pageLifecycles = ParserPageLifecycle.idlePages(
                    parserID: selectedProviderID.rawValue,
                    pageCount: totalPageCount,
                    at: .now
                )
            }
            if selectedProviderUsesOllama {
                refreshOllamaModels()
            }
        }
    }
    @Published private(set) var availabilityByProvider: [LocalProviderID: LocalProviderAvailability] = [:]
    @Published private(set) var latestRun: LocalProcessingRun?
    @Published private(set) var recentRuns: [LocalProcessingRun] = []
    @Published private(set) var outputText = ""
    @Published private(set) var structuredOutputText = ""
    @Published private(set) var structuredOutput: StructuredExtractionDocument?
    @Published private(set) var selectedStructuredBlockID: String?
    @Published private(set) var hoveredStructuredBlockID: String?
    @Published private(set) var structuredBlockHoverSource: StructuredBlockHoverSource?
    @Published var showsPDFBoundingBoxes = true {
        didSet {
            if showsPDFBoundingBoxes == false {
                clearStructuredBlockHover(source: .pdf)
            }
        }
    }
    @Published private(set) var progress = 0.0
    @Published private(set) var completedPageCount = 0
    @Published private(set) var totalPageCount = 0
    @Published private(set) var pageLifecycles: [ParserPageLifecycle] = []
    @Published private(set) var statusMessage = "Choose a local parser and extract."
    @Published private(set) var isRunning = false
    @Published private(set) var isInstalling = false
    @Published private(set) var setupProgress: LocalProviderSetupProgress?
    @Published private(set) var setupErrorMessage: String?
    @Published private(set) var runHealthMessage: String?
    @Published private(set) var ollamaModels: [OllamaModel] = []
    @Published private(set) var isRefreshingOllamaModels = false
    @Published private(set) var ollamaErrorMessage: String?
    @Published var selectedOllamaModelName: String? {
        didSet {
            if let selectedOllamaModelName {
                userDefaults.set(selectedOllamaModelName, forKey: Self.ollamaModelDefaultsKey)
            } else {
                userDefaults.removeObject(forKey: Self.ollamaModelDefaultsKey)
            }
            ollamaIntegration.select(modelName: selectedOllamaModelName)
            refreshAvailability()
            if selectedProviderUsesOllama {
                statusMessage = selectedAvailability.isReady
                    ? "\(selectedDescriptor.name) is ready with \(selectedOllamaModelName ?? "Ollama")."
                    : selectedAvailability.message
            }
        }
    }

    private static let providerDefaultsKey = "localProcessing.selectedProvider"
    private static let ollamaModelDefaultsKey = "localProcessing.ollama.selectedModel"

    static func modelLicenseAcceptanceKey(for providerID: LocalProviderID) -> String {
        "localProcessing.modelLicenseAcceptance.\(providerID.rawValue)"
    }
    private let providers: [any LocalProcessingProvider]
    private let ollamaClient: OllamaClient
    private let ollamaIntegration: OllamaIntegrationState
    private let runsRoot: URL
    private let userDefaults: UserDefaults
    private let memorySampler: @Sendable () -> SystemMemoryStatus
    private let stallThreshold: TimeInterval
    private let healthPollInterval: TimeInterval
    private var currentSourcePath: String?
    private var currentFileName = "extraction.pdf"
    private var installationTask: Task<Void, Never>?
    private var ollamaRefreshTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var healthMonitorTask: Task<Void, Never>?
    private var activeRun: LocalProcessingRun?
    private var lastProgressEventAt = Date()

    init(
        providers: [any LocalProcessingProvider]? = nil,
        runsRoot: URL = LocalProviderPaths.runsRoot,
        userDefaults: UserDefaults = .standard,
        ollamaClient: OllamaClient = OllamaClient(),
        memorySampler: @escaping @Sendable () -> SystemMemoryStatus = {
            SystemMemorySampler.sample()
        },
        stallThreshold: TimeInterval = 90,
        healthPollInterval: TimeInterval = 5,
        hostProfile: LocalParserHostProfile = .current()
    ) {
        self.runsRoot = runsRoot
        self.userDefaults = userDefaults
        self.ollamaClient = ollamaClient
        let storedOllamaModel = userDefaults.string(forKey: Self.ollamaModelDefaultsKey)
        selectedOllamaModelName = storedOllamaModel
        let ollamaIntegration = OllamaIntegrationState(selectedModelName: storedOllamaModel)
        self.ollamaIntegration = ollamaIntegration
        let resolvedProviders: [any LocalProcessingProvider]
        if let providers {
            resolvedProviders = providers
        } else {
            let ollamaProvider = OllamaProcessingProvider(
                client: ollamaClient,
                integration: ollamaIntegration
            )
            resolvedProviders = [
                AppleVisionProcessingProvider(),
                HybridAutoProcessingProvider(ollama: ollamaProvider),
                DotsOCRProcessingProvider(hostProfile: hostProfile),
                UnlimitedOCRProcessingProvider(),
                ollamaProvider,
            ]
        }
        self.providers = resolvedProviders
        self.memorySampler = memorySampler
        self.stallThreshold = stallThreshold
        self.healthPollInterval = healthPollInterval

        let dotsCanBeDefault = resolvedProviders.first(where: {
            $0.descriptor.id == .dotsOCR
        }).map { provider in
            if case .unavailable = provider.availability() { return false }
            return true
        } ?? false
        let storedProvider = userDefaults.string(forKey: Self.providerDefaultsKey)
        if let stored = storedProvider,
           let providerID = LocalProviderID.persisted(rawValue: stored),
           self.providers.contains(where: { $0.descriptor.id == providerID }) {
            selectedProviderID = providerID
        } else if dotsCanBeDefault {
            selectedProviderID = .dotsOCR
        } else if self.providers.contains(where: { $0.descriptor.id == .appleVision }) {
            selectedProviderID = .appleVision
        } else if let firstProvider = self.providers.first {
            selectedProviderID = firstProvider.descriptor.id
        } else {
            preconditionFailure("LocalProcessingCoordinator requires at least one provider.")
        }

        refreshAvailability()
        refreshRecentRuns()
        recoverOrphanedRuns()
        if self.providers.contains(where: { $0.descriptor.id == .ollama }) {
            refreshOllamaModels()
        }
    }

    var descriptors: [LocalProviderDescriptor] {
        providers.map(\.descriptor)
    }

    var selectedDescriptor: LocalProviderDescriptor {
        provider(for: selectedProviderID)?.descriptor ?? providers[0].descriptor
    }

    var selectedAvailability: LocalProviderAvailability {
        availabilityByProvider[selectedProviderID] ?? .unavailable("Unavailable")
    }

    var selectedProviderUsesOllama: Bool {
        selectedProviderID == .ollama || selectedProviderID == .hybridAuto
    }

    var ollamaVisionModels: [OllamaModel] {
        ollamaModels.filter(\.supportsVision)
    }

    var outputURL: URL? {
        guard let outputPath = latestRun?.outputPath else { return nil }
        return URL(fileURLWithPath: outputPath)
    }

    var structuredOutputURL: URL? {
        guard let structuredOutputPath = latestRun?.structuredOutputPath else { return nil }
        return URL(fileURLWithPath: structuredOutputPath)
    }

    var pdfBoundingBoxOverlays: [PDFBoundingBoxOverlay] {
        guard let run = latestRun,
              run.status == "succeeded",
              let structuredOutput,
              structuredOutput.provider.id == run.providerId else {
            return []
        }
        return structuredOutput.pdfBoundingBoxOverlays
    }

    var previewHoveredStructuredBlockID: String? {
        structuredBlockHoverSource == .preview ? hoveredStructuredBlockID : nil
    }

    var canResumeLatestRun: Bool {
        guard !isRunning,
              !isInstalling,
              let run = latestRun,
              ["canceled", "failed", "interrupted"].contains(run.status),
              FileManager.default.fileExists(atPath: run.sourcePath),
              let providerID = LocalProviderID.persisted(rawValue: run.providerId),
              let provider = provider(for: providerID) else {
            return false
        }
        return provider.availability().isReady
    }

    var pageLifecycleRollup: ParserLifecycleState {
        ParserLifecycleState.rollup(pageLifecycles.map(\.state))
    }

    var pageLifecycleGroups: [ParserPageLifecycleGroup] {
        Dictionary(grouping: pageLifecycles, by: \.parserID)
            .map { parserID, lifecycles in
                let parserName: String
                if latestRun?.providerId == parserID, let latestRun {
                    parserName = latestRun.providerName
                } else if let providerID = LocalProviderID.persisted(rawValue: parserID),
                          let descriptor = provider(for: providerID)?.descriptor {
                    parserName = descriptor.name
                } else {
                    parserName = parserID
                }
                return ParserPageLifecycleGroup(
                    parserID: parserID,
                    parserName: parserName,
                    lifecycles: lifecycles.sorted { $0.pageNumber < $1.pageNumber }
                )
            }
            .sorted { $0.parserName.localizedStandardCompare($1.parserName) == .orderedAscending }
    }

    func load(document: LocalPDFDocument) {
        currentSourcePath = document.filePath
        currentFileName = document.fileName
        setupErrorMessage = nil
        refreshAvailability()
        refreshRecentRuns()

        if let run = recentRuns.first(where: { $0.sourcePath == document.filePath }) {
            display(run: run)
            return
        }

        latestRun = nil
        outputText = ""
        structuredOutputText = ""
        structuredOutput = nil
        selectedStructuredBlockID = nil
        clearStructuredBlockHover()
        progress = 0
        completedPageCount = 0
        totalPageCount = document.totalPages
        pageLifecycles = ParserPageLifecycle.idlePages(
            parserID: selectedProviderID.rawValue,
            pageCount: document.totalPages,
            at: .now
        )
        statusMessage = selectedAvailability.isReady
            ? "Ready to parse with \(selectedDescriptor.name)."
            : selectedAvailability.message
    }

    func refreshAvailability() {
        availabilityByProvider = Dictionary(
            uniqueKeysWithValues: providers.map { ($0.descriptor.id, $0.availability()) }
        )
    }

    func refreshOllamaModels() {
        guard isRefreshingOllamaModels == false else { return }
        isRefreshingOllamaModels = true
        ollamaErrorMessage = nil
        ollamaIntegration.beginRefresh()
        refreshAvailability()

        ollamaRefreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isRefreshingOllamaModels = false
                ollamaRefreshTask = nil
            }
            do {
                let models = try await ollamaClient.listModels()
                let visionModels = models.filter(\.supportsVision)
                let selected = selectedOllamaModelName.flatMap { stored in
                    visionModels.contains(where: { $0.name == stored }) ? stored : nil
                } ?? visionModels.first?.name
                ollamaIntegration.connect(models: models, selectedModelName: selected)
                ollamaModels = models
                selectedOllamaModelName = selected
                if selectedProviderUsesOllama {
                    statusMessage = selectedAvailability.isReady
                        ? "\(selectedDescriptor.name) is ready with \(selected ?? "Ollama")."
                        : selectedAvailability.message
                }
            } catch is CancellationError {
                return
            } catch {
                let message = error.localizedDescription
                ollamaIntegration.fail(message: message)
                ollamaErrorMessage = message
                refreshAvailability()
                if selectedProviderUsesOllama {
                    statusMessage = message
                }
            }
        }
    }

    func installSelectedProvider() {
        guard !isInstalling, let provider = provider(for: selectedProviderID) else { return }
        if let package = provider.descriptor.parserDefinition?.modelDelivery.pinnedPackage,
           let licenseRevision = package.licenseRevision {
            userDefaults.set(
                licenseRevision,
                forKey: Self.modelLicenseAcceptanceKey(for: provider.descriptor.id)
            )
        }
        isInstalling = true
        progress = 0
        setupErrorMessage = nil
        setupProgress = LocalProviderSetupProgress(
            phase: .preparing,
            fraction: nil,
            message: "Preparing \(provider.descriptor.name)…"
        )
        statusMessage = "Setting up \(provider.descriptor.name)…"

        installationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await provider.install { [weak self] update in
                    Task { @MainActor in
                        guard let self, self.isInstalling else { return }
                        self.setupProgress = update
                        self.statusMessage = update.message
                    }
                }
                self.refreshAvailability()
                self.setupProgress = LocalProviderSetupProgress(
                    phase: .ready,
                    fraction: 1,
                    message: "\(provider.descriptor.name) is ready offline."
                )
                self.statusMessage = "\(provider.descriptor.name) is ready offline."
            } catch is CancellationError {
                self.setupProgress = nil
                self.statusMessage = "Setup canceled. You can resume when you are ready."
            } catch {
                self.setupErrorMessage = error.localizedDescription
                self.setupProgress = nil
                self.statusMessage = error.localizedDescription
            }
            self.isInstalling = false
            self.installationTask = nil
        }
    }

    func cancelInstallation() {
        guard isInstalling else { return }
        statusMessage = "Canceling setup after the current operation…"
        installationTask?.cancel()
    }

    func run(document: LocalPDFDocument) {
        guard !isRunning else {
            statusMessage = "Another extraction is already running."
            return
        }
        guard let provider = provider(for: selectedProviderID) else {
            statusMessage = "The selected parser is unavailable."
            return
        }
        guard provider.availability().isReady else {
            statusMessage = provider.availability().message
            return
        }

        let runID = UUID().uuidString
        let runDirectory = LocalProviderPaths.runDirectory(runsRoot: runsRoot, runID: runID)
        var run = LocalProcessingRun(
            id: runID,
            sourcePath: document.filePath,
            fileName: document.fileName,
            providerId: provider.descriptor.id.rawValue,
            providerName: provider.descriptor.name,
            executionMode: provider.availability().isSimulated ? "simulation" : "local",
            status: "running",
            outputPath: nil,
            structuredOutputPath: nil,
            errorMessage: nil,
            pageCount: 0,
            completedPageCount: 0,
            totalPageCount: document.totalPages,
            startedAt: Date(),
            completedAt: nil,
            progress: 0,
            statusMessage: "Starting \(provider.descriptor.name)…",
            updatedAt: Date(),
            resumeCount: 0,
            eventSequence: 0,
            pageLifecycles: ParserPageLifecycle.idlePages(
                parserID: provider.descriptor.id.rawValue,
                pageCount: document.totalPages,
                at: .now
            )
        )

        do {
            try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
            try recordTransition(&run, type: "run.started", in: runDirectory)
        } catch {
            statusMessage = "Could not start extraction: \(error.localizedDescription)"
            return
        }

        beginProcessing(run: run, document: document, provider: provider, in: runDirectory)
    }

    func cancelRun() {
        guard isRunning, var run = activeRun, run.status == "running" else { return }
        let runDirectory = LocalProviderPaths.runDirectory(runsRoot: runsRoot, runID: run.id)
        run.status = "canceling"
        run.cancelRequestedAt = Date()
        run.statusMessage = "Canceling after the current operation…"

        do {
            try recordTransition(&run, type: "run.cancel_requested", in: runDirectory)
        } catch {
            statusMessage = "Could not save the cancellation request: \(error.localizedDescription)"
            return
        }

        activeRun = run
        upsertRecentRun(run)
        if latestRun?.id == run.id {
            latestRun = run
            statusMessage = run.statusMessage ?? "Canceling…"
        }
        processingTask?.cancel()
    }

    func resume(document: LocalPDFDocument) {
        guard canResumeLatestRun,
              var run = latestRun,
              run.sourcePath == document.filePath,
              let providerID = LocalProviderID.persisted(rawValue: run.providerId),
              let provider = provider(for: providerID) else {
            return
        }

        selectedProviderID = providerID
        let runDirectory = LocalProviderPaths.runDirectory(runsRoot: runsRoot, runID: run.id)
        let completed = run.completedPageCount ?? 0
        let total = run.totalPageCount ?? document.totalPages
        run.status = "running"
        run.errorMessage = nil
        run.completedAt = nil
        run.cancelRequestedAt = nil
        run.resumeCount = (run.resumeCount ?? 0) + 1
        run.progress = total > 0 ? Double(completed) / Double(total) : 0
        run.statusMessage = completed > 0
            ? "Resuming after \(completed) of \(total) saved pages…"
            : "Restarting \(provider.descriptor.name)…"

        do {
            try recordTransition(&run, type: "run.resumed", in: runDirectory)
        } catch {
            statusMessage = "Could not resume extraction: \(error.localizedDescription)"
            return
        }

        beginProcessing(run: run, document: document, provider: provider, in: runDirectory)
    }

    private func beginProcessing(
        run: LocalProcessingRun,
        document: LocalPDFDocument,
        provider: any LocalProcessingProvider,
        in runDirectory: URL
    ) {
        let runID = run.id

        currentSourcePath = document.filePath
        currentFileName = document.fileName
        activeRun = run
        latestRun = run
        selectedStructuredBlockID = nil
        clearStructuredBlockHover()
        upsertRecentRun(run)
        progress = run.progress ?? 0
        completedPageCount = run.completedPageCount ?? 0
        totalPageCount = run.totalPageCount ?? document.totalPages
        pageLifecycles = resolvedPageLifecycles(for: run)
        isRunning = true
        statusMessage = run.statusMessage ?? "Starting \(provider.descriptor.name)…"
        startHealthMonitor()

        let request = LocalProcessingRequest(
            parserID: provider.descriptor.id,
            fileName: document.fileName,
            sourceURL: document.fileURL,
            outputDirectory: runDirectory,
            expectedPageCount: document.totalPages,
            pageProgress: { [weak self] update in
                Task { @MainActor in
                    guard let self,
                          var trackedRun = self.activeRun,
                          trackedRun.id == runID else {
                        return
                    }
                    self.noteProgressEvent()
                    self.completedPageCount = max(
                        self.completedPageCount,
                        update.completedPageCount
                    )
                    self.totalPageCount = max(self.totalPageCount, update.totalPageCount)
                    self.progress = max(self.progress, update.fraction)
                    self.statusMessage = update.message
                        ?? self.defaultPageStatusMessage(for: update)

                    trackedRun.pageCount = max(trackedRun.pageCount, update.completedPageCount)
                    trackedRun.completedPageCount = max(
                        trackedRun.completedPageCount ?? 0,
                        update.completedPageCount
                    )
                    trackedRun.totalPageCount = max(
                        trackedRun.totalPageCount ?? 0,
                        update.totalPageCount
                    )
                    trackedRun.progress = self.progress
                    trackedRun.statusMessage = self.statusMessage
                    trackedRun.pageLifecycles = self.applying(
                        update,
                        to: trackedRun
                    )
                    self.pageLifecycles = trackedRun.pageLifecycles ?? []
                    try? self.recordTransition(
                        &trackedRun,
                        type: "run.page_lifecycle",
                        in: runDirectory
                    )
                    self.activeRun = trackedRun
                    self.upsertRecentRun(trackedRun)
                    if self.latestRun?.id == runID {
                        self.latestRun = trackedRun
                    }
                }
            }
        )

        processingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await provider.process(request: request) { [weak self] fraction, message in
                    Task { @MainActor in
                        guard let self,
                              var trackedRun = self.activeRun,
                              trackedRun.id == runID else { return }
                        self.noteProgressEvent()
                        self.progress = max(self.progress, min(max(fraction, 0), 1))
                        self.statusMessage = message
                        trackedRun.progress = self.progress
                        trackedRun.statusMessage = message
                        try? self.recordTransition(
                            &trackedRun,
                            type: "run.progress",
                            in: runDirectory
                        )
                        self.activeRun = trackedRun
                        self.upsertRecentRun(trackedRun)
                        if self.latestRun?.id == runID {
                            self.latestRun = trackedRun
                        }
                    }
                }
                try Task.checkCancellation()
                guard var completedRun = activeRun, completedRun.id == runID else { return }
                completedRun.status = "succeeded"
                completedRun.outputPath = result.outputURL.path
                completedRun.structuredOutputPath = result.structuredOutputURL?.path
                completedRun.pageCount = result.pageCount
                completedRun.completedPageCount = result.pageCount
                completedRun.totalPageCount = max(document.totalPages, result.pageCount)
                completedRun.pageLifecycles = completedPageLifecycles(
                    for: completedRun,
                    pageCount: result.pageCount,
                    message: "Saved by \(provider.descriptor.name)"
                )
                completedRun.progress = 1
                completedRun.completedAt = Date()
                completedRun.statusMessage = provider.availability().isSimulated
                    ? "Simulation complete · model weights were not loaded."
                    : "Parsed locally with \(provider.descriptor.name)."
                try recordTransition(&completedRun, type: "run.succeeded", in: runDirectory)
                activeRun = completedRun
                upsertRecentRun(completedRun)

                if currentSourcePath == document.filePath {
                    latestRun = completedRun
                    progress = 1
                    completedPageCount = result.pageCount
                    totalPageCount = max(document.totalPages, result.pageCount)
                    pageLifecycles = completedRun.pageLifecycles ?? []
                    statusMessage = completedRun.statusMessage ?? "Extraction complete."
                    loadOutputs()
                }
            } catch is CancellationError {
                if var canceledRun = activeRun, canceledRun.id == runID {
                    let completed = canceledRun.completedPageCount ?? 0
                    let total = canceledRun.totalPageCount ?? document.totalPages
                    canceledRun.status = "canceled"
                    canceledRun.errorMessage = nil
                    canceledRun.completedAt = Date()
                    canceledRun.progress = total > 0 ? Double(completed) / Double(total) : 0
                    canceledRun.statusMessage = "Canceled · \(completed) of \(total) pages saved."
                    canceledRun.pageLifecycles = transitioningActivePages(
                        in: canceledRun,
                        to: .attention,
                        detail: "Canceled. Resume to continue this page."
                    )
                    try? recordTransition(&canceledRun, type: "run.canceled", in: runDirectory)
                    activeRun = canceledRun
                    upsertRecentRun(canceledRun)
                    if currentSourcePath == document.filePath {
                        latestRun = canceledRun
                        progress = canceledRun.progress ?? 0
                        completedPageCount = completed
                        totalPageCount = total
                        pageLifecycles = canceledRun.pageLifecycles ?? []
                        statusMessage = canceledRun.statusMessage ?? "Canceled."
                    }
                }
            } catch {
                if var failedRun = activeRun, failedRun.id == runID {
                    failedRun.status = "failed"
                    failedRun.errorMessage = error.localizedDescription
                    failedRun.completedAt = Date()
                    failedRun.statusMessage = error.localizedDescription
                    failedRun.pageLifecycles = transitioningActivePages(
                        in: failedRun,
                        to: .error,
                        detail: error.localizedDescription,
                        markFirstUnfinishedWhenNoActivePage: true
                    )
                    try? recordTransition(&failedRun, type: "run.failed", in: runDirectory)
                    activeRun = failedRun
                    upsertRecentRun(failedRun)
                    if currentSourcePath == document.filePath {
                        latestRun = failedRun
                        pageLifecycles = failedRun.pageLifecycles ?? []
                        statusMessage = error.localizedDescription
                    }
                }
            }
            activeRun = nil
            isRunning = false
            processingTask = nil
            stopHealthMonitor()
        }
    }

    private func noteProgressEvent() {
        lastProgressEventAt = Date()
        runHealthMessage = nil
    }

    private func startHealthMonitor() {
        healthMonitorTask?.cancel()
        lastProgressEventAt = Date()
        runHealthMessage = nil
        healthMonitorTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(self?.healthPollInterval ?? 5))
                guard let self, Task.isCancelled == false, self.isRunning else { return }
                guard self.activeRun?.status == "running" else { continue }
                let healthMessage = LocalRunHealth.message(
                    idleFor: Date().timeIntervalSince(self.lastProgressEventAt),
                    stallThreshold: self.stallThreshold,
                    memory: self.memorySampler()
                )
                let previousMessage = self.runHealthMessage
                self.runHealthMessage = healthMessage

                guard let healthMessage,
                      healthMessage != previousMessage,
                      var run = self.activeRun else {
                    continue
                }
                run.pageLifecycles = self.transitioningActivePages(
                    in: run,
                    to: .attention,
                    detail: healthMessage,
                    markFirstUnfinishedWhenNoActivePage: true
                )
                let runDirectory = LocalProviderPaths.runDirectory(
                    runsRoot: self.runsRoot,
                    runID: run.id
                )
                try? self.recordTransition(
                    &run,
                    type: "run.page_attention",
                    in: runDirectory
                )
                self.activeRun = run
                self.upsertRecentRun(run)
                if self.latestRun?.id == run.id {
                    self.latestRun = run
                    self.pageLifecycles = run.pageLifecycles ?? []
                }
            }
        }
    }

    private func stopHealthMonitor() {
        healthMonitorTask?.cancel()
        healthMonitorTask = nil
        runHealthMessage = nil
    }

    func revealRunsFolder() {
        try? FileManager.default.createDirectory(at: runsRoot, withIntermediateDirectories: true)
        NSWorkspace.shared.open(runsRoot)
    }

    func selectRun(_ run: LocalProcessingRun) {
        currentSourcePath = run.sourcePath
        currentFileName = run.fileName
        display(run: run)
    }

    func selectStructuredBlock(_ id: String) {
        guard pdfBoundingBoxOverlays.contains(where: { $0.id == id }) else { return }
        showsPDFBoundingBoxes = true
        selectedStructuredBlockID = id
    }

    func hoverStructuredBlock(_ id: String, isHovering: Bool) {
        if isHovering {
            setHoveredStructuredBlock(id, source: .preview)
        } else {
            clearStructuredBlockHover(source: .preview, matching: id)
        }
    }

    func hoverPDFOverlay(_ id: String?) {
        if let id {
            setHoveredStructuredBlock(id, source: .pdf)
        } else {
            clearStructuredBlockHover(source: .pdf)
        }
    }

    private func display(run: LocalProcessingRun) {
        latestRun = run
        selectedStructuredBlockID = nil
        clearStructuredBlockHover()
        completedPageCount = run.completedPageCount
            ?? (run.status == "succeeded" ? run.pageCount : 0)
        totalPageCount = run.totalPageCount ?? run.pageCount
        pageLifecycles = resolvedPageLifecycles(for: run)
        progress = run.progress ?? (totalPageCount > 0
            ? Double(completedPageCount) / Double(totalPageCount)
            : (run.status == "succeeded" ? 1 : 0))
        statusMessage = displayMessage(for: run)
        loadOutputs()
    }

    func refreshRecentRuns() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let runDirectories = try? FileManager.default.contentsOfDirectory(
            at: runsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            recentRuns = []
            return
        }

        recentRuns = runDirectories.compactMap { runDirectory in
            let manifestURL = runDirectory.appendingPathComponent("run.json")
            guard let data = try? Data(contentsOf: manifestURL) else { return nil }
            return try? decoder.decode(LocalProcessingRun.self, from: data)
        }
        .sorted { $0.startedAt > $1.startedAt }
        .prefix(12)
        .map { $0 }
    }

    func revealOutput() {
        guard let outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    func revealStructuredOutput() {
        guard let structuredOutputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([structuredOutputURL])
    }

    func copyOutput() {
        guard !outputText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
        statusMessage = "Copied Markdown."
    }

    func copyStructuredOutput() {
        guard !structuredOutputText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(structuredOutputText, forType: .string)
        statusMessage = "Copied structured JSON."
    }

    func saveOutputAs() {
        guard !outputText.isEmpty else { return }

        let panel = NSSavePanel()
        panel.title = "Save Extracted Markdown"
        panel.prompt = "Save"
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(URL(fileURLWithPath: currentFileName).deletingPathExtension().lastPathComponent).md"

        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try outputText.write(to: destination, atomically: true, encoding: .utf8)
            statusMessage = "Saved Markdown."
        } catch {
            statusMessage = "Could not save Markdown: \(error.localizedDescription)"
        }
    }

    func saveStructuredOutputAs() {
        guard !structuredOutputText.isEmpty else { return }

        let panel = NSSavePanel()
        panel.title = "Save Structured Extraction"
        panel.prompt = "Save"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(URL(fileURLWithPath: currentFileName).deletingPathExtension().lastPathComponent).json"

        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try structuredOutputText.write(to: destination, atomically: true, encoding: .utf8)
            statusMessage = "Saved structured JSON."
        } catch {
            statusMessage = "Could not save structured JSON: \(error.localizedDescription)"
        }
    }

    private func provider(for id: LocalProviderID) -> (any LocalProcessingProvider)? {
        providers.first { $0.descriptor.id == id }
    }

    private func recoverOrphanedRuns() {
        for index in recentRuns.indices where ["running", "canceling"].contains(recentRuns[index].status) {
            var run = recentRuns[index]
            let completed = run.completedPageCount ?? 0
            let total = run.totalPageCount ?? run.pageCount
            run.status = "interrupted"
            run.errorMessage = nil
            run.statusMessage = "Run interrupted when okraPDF closed · \(completed) of \(total) pages saved."
            run.progress = total > 0 ? Double(completed) / Double(total) : 0
            run.pageLifecycles = transitioningActivePages(
                in: run,
                to: .attention,
                detail: "The app closed during this page. Resume to continue."
            )
            let runDirectory = LocalProviderPaths.runDirectory(runsRoot: runsRoot, runID: run.id)
            try? recordTransition(&run, type: "run.interrupted", in: runDirectory)
            recentRuns[index] = run
        }
    }

    private func displayMessage(for run: LocalProcessingRun) -> String {
        if let message = run.statusMessage, message.isEmpty == false {
            return message
        }
        switch run.status {
        case "succeeded":
            return "Parsed locally with \(run.providerName)."
        case "canceled":
            return "Canceled. Resume to keep the saved page checkpoints."
        case "interrupted":
            return "Run interrupted. Resume to keep the saved page checkpoints."
        case "failed":
            return run.errorMessage ?? "This run failed."
        case "canceling":
            return "Canceling after the current operation…"
        case "running":
            return "Extraction is running."
        default:
            return run.errorMessage ?? "This run did not finish."
        }
    }

    private func defaultPageStatusMessage(for update: LocalPageProgressUpdate) -> String {
        switch update.state {
        case .idle:
            return "Page \(update.pageNumber) is waiting."
        case .inProgress:
            return "Parsing page \(update.pageNumber) of \(update.totalPageCount)."
        case .done:
            return "Saved page \(update.pageNumber) of \(update.totalPageCount) to disk."
        case .attention:
            return "Page \(update.pageNumber) needs attention."
        case .error:
            return "Page \(update.pageNumber) failed."
        }
    }

    private func applying(
        _ update: LocalPageProgressUpdate,
        to run: LocalProcessingRun
    ) -> [ParserPageLifecycle] {
        ParserPageLifecycle.applying(
            parserID: update.parserID.rawValue,
            pageNumber: update.pageNumber,
            state: update.state,
            totalPageCount: update.totalPageCount,
            detail: update.message,
            at: .now,
            to: resolvedPageLifecycles(for: run)
        )
    }

    private func completedPageLifecycles(
        for run: LocalProcessingRun,
        pageCount: Int,
        message: String
    ) -> [ParserPageLifecycle] {
        var lifecycles = resolvedPageLifecycles(for: run)
        guard pageCount > 0 else { return lifecycles }

        for pageNumber in 1...pageCount {
            lifecycles = ParserPageLifecycle.applying(
                parserID: run.providerId,
                pageNumber: pageNumber,
                state: .done,
                totalPageCount: pageCount,
                detail: message,
                at: .now,
                to: lifecycles
            )
        }
        return lifecycles
    }

    private func transitioningActivePages(
        in run: LocalProcessingRun,
        to state: ParserLifecycleState,
        detail: String,
        markFirstUnfinishedWhenNoActivePage: Bool = false
    ) -> [ParserPageLifecycle] {
        var lifecycles = resolvedPageLifecycles(for: run)
        let timestamp = Date.now
        var changed = false

        for index in lifecycles.indices where lifecycles[index].state == .inProgress {
            changed = lifecycles[index].transition(
                to: state,
                detail: detail,
                at: timestamp
            ) || changed
        }

        if changed == false,
           markFirstUnfinishedWhenNoActivePage,
           let index = lifecycles.firstIndex(where: { $0.state != .done }) {
            _ = lifecycles[index].transition(to: state, detail: detail, at: timestamp)
        }
        return lifecycles
    }

    private func resolvedPageLifecycles(for run: LocalProcessingRun) -> [ParserPageLifecycle] {
        if let lifecycles = run.pageLifecycles, lifecycles.isEmpty == false {
            return lifecycles.sorted {
                ($0.parserID, $0.pageNumber) < ($1.parserID, $1.pageNumber)
            }
        }

        let total = max(run.totalPageCount ?? run.pageCount, 0)
        guard total > 0 else { return [] }
        let completed = min(run.completedPageCount ?? (run.status == "succeeded" ? total : 0), total)
        let timestamp = run.updatedAt ?? run.completedAt ?? run.startedAt

        return (1...total).map { pageNumber in
            let state: ParserLifecycleState
            let detail: String?
            if pageNumber <= completed {
                state = .done
                detail = "Recovered from a durable page checkpoint."
            } else if pageNumber == completed + 1 {
                switch run.status {
                case "running", "canceling":
                    state = .inProgress
                    detail = run.statusMessage
                case "canceled", "interrupted":
                    state = .attention
                    detail = run.statusMessage
                case "failed":
                    state = .error
                    detail = run.errorMessage ?? run.statusMessage
                default:
                    state = .idle
                    detail = nil
                }
            } else {
                state = .idle
                detail = nil
            }
            return ParserPageLifecycle(
                parserID: run.providerId,
                pageNumber: pageNumber,
                state: state,
                detail: detail,
                updatedAt: timestamp
            )
        }
    }

    private func upsertRecentRun(_ run: LocalProcessingRun) {
        if let index = recentRuns.firstIndex(where: { $0.id == run.id }) {
            recentRuns[index] = run
        } else {
            recentRuns.append(run)
        }
        recentRuns = Array(recentRuns.sorted { $0.startedAt > $1.startedAt }.prefix(12))
    }

    private func recordTransition(
        _ run: inout LocalProcessingRun,
        type: String,
        in runDirectory: URL
    ) throws {
        let timestamp = Date()
        run.updatedAt = timestamp
        run.progress = min(max(run.progress ?? 0, 0), 1)
        run.eventSequence = (run.eventSequence ?? 0) + 1
        try persistSnapshot(run, in: runDirectory)
        try? appendEvent(
            LocalProcessingRunEvent(
                sequence: run.eventSequence ?? 1,
                type: type,
                runId: run.id,
                status: run.status,
                progress: run.progress ?? 0,
                completedPageCount: run.completedPageCount ?? 0,
                totalPageCount: run.totalPageCount ?? run.pageCount,
                message: run.statusMessage ?? run.errorMessage ?? "",
                createdAt: timestamp
            ),
            in: runDirectory
        )
    }

    private func persistSnapshot(_ run: LocalProcessingRun, in runDirectory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(run)
        try data.write(to: runDirectory.appendingPathComponent("run.json"), options: .atomic)
    }

    private func appendEvent(_ event: LocalProcessingRunEvent, in runDirectory: URL) throws {
        let eventURL = runDirectory.appendingPathComponent("events.jsonl")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(event)
        data.append(0x0A)

        if FileManager.default.fileExists(atPath: eventURL.path) == false {
            FileManager.default.createFile(atPath: eventURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: eventURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    private func loadOutputs() {
        guard let outputURL else {
            outputText = ""
            structuredOutputText = ""
            structuredOutput = nil
            selectedStructuredBlockID = nil
            clearStructuredBlockHover()
            return
        }
        outputText = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""

        guard let structuredOutputURL else {
            structuredOutputText = ""
            structuredOutput = nil
            selectedStructuredBlockID = nil
            clearStructuredBlockHover()
            return
        }
        structuredOutputText = (try? String(contentsOf: structuredOutputURL, encoding: .utf8)) ?? ""
        structuredOutput = try? StructuredExtractionDocument.load(from: structuredOutputURL)
        if let selectedStructuredBlockID,
           pdfBoundingBoxOverlays.contains(where: { $0.id == selectedStructuredBlockID }) == false {
            self.selectedStructuredBlockID = nil
        }
        if let hoveredStructuredBlockID,
           pdfBoundingBoxOverlays.contains(where: { $0.id == hoveredStructuredBlockID }) == false {
            clearStructuredBlockHover()
        }
    }

    private func setHoveredStructuredBlock(
        _ id: String,
        source: StructuredBlockHoverSource
    ) {
        guard pdfBoundingBoxOverlays.contains(where: { $0.id == id }) else { return }
        structuredBlockHoverSource = source
        hoveredStructuredBlockID = id
    }

    private func clearStructuredBlockHover(
        source: StructuredBlockHoverSource? = nil,
        matching id: String? = nil
    ) {
        guard source == nil || structuredBlockHoverSource == source,
              id == nil || hoveredStructuredBlockID == id else {
            return
        }
        hoveredStructuredBlockID = nil
        structuredBlockHoverSource = nil
    }
}
