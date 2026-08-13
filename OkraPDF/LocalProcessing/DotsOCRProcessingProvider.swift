import Foundation

final class DotsOCRProcessingProvider: LocalProcessingProvider, @unchecked Sendable {
    let descriptor = LocalProviderDescriptor(
        id: .dotsOCR,
        name: "Dots OCR 1.5",
        summary: "The dots.mocr document parser, quantized to 4-bit MLX for Apple silicon.",
        setupNote: "One-time ~3.5 GB model download. Extraction stays offline after setup.",
        parserDefinition: LocalParserCatalog.dotsOCR
    )

    private let runtime: DotsOCRRuntime
    private let installer: any DotsOCRModelInstalling
    private let hostProfile: LocalParserHostProfile
    private let fileManager: FileManager

    init(
        runtime: DotsOCRRuntime? = nil,
        installer: any DotsOCRModelInstalling = DotsOCRModelInstaller(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        hostProfile: LocalParserHostProfile = .current(),
        fileManager: FileManager = .default
    ) {
        self.installer = installer
        self.hostProfile = hostProfile
        self.fileManager = fileManager
        let workerURL = ProviderResources.scriptURL(
            named: "dots-ocr-worker",
            extension: "py"
        )
        if let runtime {
            self.runtime = runtime
        } else if environment["OKRA_DESKTOP_SIMULATE_DOTS_OCR"] == "1" {
            self.runtime = .simulated(workerURL: workerURL)
        } else {
            self.runtime = .installed(workerURL: workerURL)
        }
    }

    func availability() -> LocalProviderAvailability {
        guard let workerURL = runtime.workerURL,
              fileManager.fileExists(atPath: workerURL.path) else {
            return .unavailable("Bundled worker missing")
        }

        if runtime.isSimulation {
            return fileManager.isExecutableFile(atPath: runtime.pythonURL.path)
                ? .simulated("Simulation ready")
                : .unavailable("Python 3 is required for simulation")
        }

        let isReady = runtime.hasCurrentReadyMarker
            && fileManager.isExecutableFile(atPath: runtime.pythonURL.path)
            && runtime.hasCurrentModelArtifacts
        let compatibilityHost = isReady ? hostProfile.ignoringAvailableDisk() : hostProfile
        if case .unsupported(let incompatibilities) = LocalParserCatalog.dotsOCR
            .requirements.compatibility(with: compatibilityHost) {
            return .unavailable(compatibilityMessage(for: incompatibilities))
        }
        return isReady ? .ready : .setupRequired("Setup required · ~3.5 GB")
    }

    private func compatibilityMessage(
        for incompatibilities: [LocalParserIncompatibility]
    ) -> String {
        incompatibilities.map { incompatibility in
            switch incompatibility {
            case .architecture:
                return "Dots OCR requires Apple silicon."
            case .macOS(let minimumMajorVersion):
                return "Dots OCR requires macOS \(minimumMajorVersion) or later."
            case .unifiedMemory(let minimumGB):
                return "Dots OCR requires at least \(minimumGB) GB unified memory."
            case .freeDisk(let requiredBytes, _):
                let required = ByteCountFormatter.string(
                    fromByteCount: requiredBytes,
                    countStyle: .file
                )
                return "Dots OCR setup requires at least \(required) free disk space."
            }
        }.joined(separator: " ")
    }

    func install(progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void) async throws {
        guard !runtime.isSimulation else { return }
        guard let scriptURL = ProviderResources.scriptURL(
            named: "install-dots-ocr",
            extension: "sh"
        ) else {
            throw LocalProcessingError.missingResource("Dots OCR 1.5 installer")
        }
        try await installer.install(runtime: runtime, scriptURL: scriptURL, progress: progress)
    }

    func process(
        request: LocalProcessingRequest,
        progress: @escaping LocalProcessingProgress
    ) async throws -> LocalProcessingResult {
        guard availability().isReady else {
            throw LocalProcessingError.providerUnavailable(
                "Set up Dots OCR 1.5 before extracting."
            )
        }
        guard let workerURL = runtime.workerURL else {
            throw LocalProcessingError.missingResource("Dots OCR 1.5 worker")
        }

        let worker = Task.detached(priority: .userInitiated) { [runtime] in
            try Task.checkCancellation()
            try FileManager.default.createDirectory(
                at: request.outputDirectory,
                withIntermediateDirectories: true
            )
            let pagesDirectory = request.outputDirectory.appendingPathComponent(
                "pages",
                isDirectory: true
            )
            let pageURLs = try PDFPageRenderer.writePagePNGs(
                from: request.sourceURL,
                to: pagesDirectory,
                maxDimension: 2_048,
                progress: progress
            )
            let documentHeader: String
            if runtime.isSimulation {
                documentHeader = """
                # \(request.fileName)

                > Simulation: Dots OCR 1.5 model weights were not loaded.

                Offline flags: HF_HUB_OFFLINE=1, TRANSFORMERS_OFFLINE=1, HF_DATASETS_OFFLINE=1.
                """
            } else {
                documentHeader = "# \(request.fileName)"
            }
            let pageStore = LocalPageCheckpointStore(
                outputDirectory: request.outputDirectory,
                totalPages: pageURLs.count,
                documentHeader: documentHeader
            )
            let initialManifest = try pageStore.prepare()
            if initialManifest.completedPageCount < pageURLs.count,
               let nextPage = (1...pageURLs.count).first(where: {
                   (try? pageStore.status(pageNumber: $0)) != .succeeded
               }) {
                try pageStore.markProcessing(pageNumber: nextPage)
                request.pageProgress(
                    LocalPageProgressUpdate(
                        parserID: request.parserID,
                        pageNumber: nextPage,
                        state: .inProgress,
                        completedPageCount: initialManifest.completedPageCount,
                        totalPageCount: pageURLs.count,
                        message: "Parsing page \(nextPage) of \(pageURLs.count)"
                    )
                )
            }
            let outputURL = pageStore.resultURL
            progress(
                0.22,
                runtime.isSimulation
                    ? "Simulating the Dots OCR 1.5 worker"
                    : "Loading Dots OCR 1.5 into unified memory"
            )

            var arguments = [
                workerURL.path,
                "--model", runtime.modelURL.path,
                "--output", outputURL.path,
                "--page-output-directory", pageStore.pagesDirectory.path,
                "--page-progress", pageStore.manifestURL.path,
                "--title", request.fileName,
                "--images",
            ]
            arguments.append(contentsOf: pageURLs.map(\.path))
            if runtime.isSimulation {
                arguments.append("--simulate")
            }

            let runGate = LocalExclusiveFileLock(
                url: runtime.rootURL.appendingPathComponent("worker.lock")
            )
            try await runGate.acquire {
                progress(0.22, "Waiting for another Dots OCR 1.5 run to finish…")
            }
            defer { runGate.release() }

            let monitorTask = Task.detached(priority: .utility) {
                var observedPageCount = initialManifest.completedPageCount
                while Task.isCancelled == false {
                    if let manifest = try? pageStore.loadManifest(),
                       manifest.completedPageCount > observedPageCount {
                        let newCompletedPageCount = manifest.completedPageCount
                        for completedPageCount in (observedPageCount + 1)...newCompletedPageCount {
                            request.pageProgress(
                                LocalPageProgressUpdate(
                                    parserID: request.parserID,
                                    pageNumber: completedPageCount,
                                    state: .done,
                                    completedPageCount: completedPageCount,
                                    totalPageCount: pageURLs.count,
                                    message: "Saved page \(completedPageCount) of \(pageURLs.count)"
                                )
                            )
                            if completedPageCount < pageURLs.count {
                                request.pageProgress(
                                    LocalPageProgressUpdate(
                                        parserID: request.parserID,
                                        pageNumber: completedPageCount + 1,
                                        state: .inProgress,
                                        completedPageCount: completedPageCount,
                                        totalPageCount: pageURLs.count,
                                        message: "Parsing page \(completedPageCount + 1) of \(pageURLs.count)"
                                    )
                                )
                            }
                            progress(
                                0.2 + (0.8 * Double(completedPageCount) / Double(pageURLs.count)),
                                "Saved page \(completedPageCount) of \(pageURLs.count)"
                            )
                        }
                        observedPageCount = newCompletedPageCount
                    }
                    guard observedPageCount < pageURLs.count else { return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }

            do {
                _ = try await LocalCommandRunner.runAsync(
                    executableURL: runtime.pythonURL,
                    arguments: arguments,
                    environment: [
                        "HF_HOME": runtime.cacheURL.path,
                        "HF_HUB_OFFLINE": "1",
                        "TRANSFORMERS_OFFLINE": "1",
                        "HF_DATASETS_OFFLINE": "1",
                    ]
                )
            } catch {
                monitorTask.cancel()
                await monitorTask.value
                let completedPages = (try? pageStore.reconcileCompletedPages().completedPageCount) ?? 0
                if completedPages < pageURLs.count, !(error is CancellationError) {
                    try? pageStore.markFailed(
                        pageNumber: completedPages + 1,
                        error: error
                    )
                }
                if completedPages < pageURLs.count {
                    request.pageProgress(
                        LocalPageProgressUpdate(
                            parserID: request.parserID,
                            pageNumber: completedPages + 1,
                            state: error is CancellationError ? .attention : .error,
                            completedPageCount: completedPages,
                            totalPageCount: pageURLs.count,
                            message: error is CancellationError
                                ? "Canceled. Resume to continue page \(completedPages + 1)."
                                : error.localizedDescription
                        )
                    )
                }
                throw error
            }

            monitorTask.cancel()
            await monitorTask.value
            let manifest = try pageStore.reconcileCompletedPages()
            if manifest.completedPageCount > 0 {
                request.pageProgress(
                    LocalPageProgressUpdate(
                        parserID: request.parserID,
                        pageNumber: manifest.lastCompletedPageNumber
                            ?? manifest.completedPageCount,
                        state: .done,
                        completedPageCount: manifest.completedPageCount,
                        totalPageCount: pageURLs.count,
                        message: "Saved page \(manifest.lastCompletedPageNumber ?? manifest.completedPageCount) of \(pageURLs.count)"
                    )
                )
            }
            _ = try pageStore.assembleResult()
            let structuredOutputURL = outputURL
                .deletingPathExtension()
                .appendingPathExtension("json")
            guard FileManager.default.fileExists(atPath: structuredOutputURL.path) else {
                throw LocalProcessingError.missingOutput("Dots OCR 1.5 structured JSON")
            }
            progress(1, runtime.isSimulation ? "Simulation complete" : "Extraction complete")
            return LocalProcessingResult(
                outputURL: outputURL,
                pageCount: pageURLs.count,
                structuredOutputURL: structuredOutputURL
            )
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
