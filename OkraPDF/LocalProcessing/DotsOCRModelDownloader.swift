import Foundation

struct DotsOCRModelDownloader: DotsOCRModelDownloading {
    func downloadModel(
        to modelURL: URL,
        progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void
    ) async throws {
        let fileManager = FileManager.default
        let providerRoot = modelURL.deletingLastPathComponent()
        let stagingURL = providerRoot.appendingPathComponent("model.partial", isDirectory: true)
        let resumeRoot = stagingURL.appendingPathComponent(".resume", isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resumeRoot, withIntermediateDirectories: true)

        var completedBytes = Int64(0)
        for artifact in DotsOCRModelManifest.artifacts {
            try Task.checkCancellation()
            let destinationURL = stagingURL.appendingPathComponent(artifact.path)
            if fileSize(at: destinationURL) == artifact.size {
                completedBytes += artifact.size
                reportDownloadProgress(completedBytes, artifact: artifact, progress: progress)
                continue
            }

            let resumeFileName = artifact.path.replacing("/", with: "_") + ".resume"
            let resumeDataURL = resumeRoot.appendingPathComponent(resumeFileName)
            try await download(
                artifact,
                to: destinationURL,
                resumeDataURL: resumeDataURL,
                completedBytes: completedBytes,
                progress: progress
            )
            completedBytes += artifact.size
        }

        var verifiedBytes = Int64(0)
        for artifact in DotsOCRModelManifest.artifacts {
            try Task.checkCancellation()
            let artifactURL = stagingURL.appendingPathComponent(artifact.path)
            guard fileSize(at: artifactURL) == artifact.size else {
                throw LocalProcessingError.modelIntegrityFailed(
                    provider: "Dots OCR 1.5",
                    artifact: artifact.path
                )
            }
            let verifiedBeforeArtifact = verifiedBytes
            let digest = try FileSHA256.digest(
                of: artifactURL,
                expectedBytes: artifact.size
            ) { bytesRead in
                let fraction = Double(verifiedBeforeArtifact + bytesRead)
                    / Double(DotsOCRModelManifest.totalBytes)
                progress(
                    LocalProviderSetupProgress(
                        phase: .verifying,
                        fraction: fraction,
                        message: "Verifying Dots OCR 1.5…"
                    )
                )
            }
            guard digest == artifact.sha256 else {
                try? fileManager.removeItem(at: artifactURL)
                throw LocalProcessingError.modelIntegrityFailed(
                    provider: "Dots OCR 1.5",
                    artifact: artifact.path
                )
            }
            verifiedBytes += artifact.size
        }

        try? fileManager.removeItem(at: resumeRoot)
        if fileManager.fileExists(atPath: modelURL.path) {
            try fileManager.removeItem(at: modelURL)
        }
        try fileManager.moveItem(at: stagingURL, to: modelURL)
    }

    private func download(
        _ artifact: LocalModelArtifact,
        to destinationURL: URL,
        resumeDataURL: URL,
        completedBytes: Int64,
        progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void
    ) async throws {
        guard let downloadURL = DotsOCRModelManifest.downloadURL(for: artifact) else {
            throw LocalProcessingError.invalidModelDownloadURL(artifact.path)
        }

        let taskBox = ModelDownloadTaskBox(resumeDataURL: resumeDataURL)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let delegate = ModelDownloadDelegate(
                    destinationURL: destinationURL,
                    resumeDataURL: resumeDataURL,
                    expectedBytes: artifact.size,
                    progress: { bytesWritten in
                        let fraction = Double(completedBytes + bytesWritten)
                            / Double(DotsOCRModelManifest.totalBytes)
                        progress(
                            LocalProviderSetupProgress(
                                phase: .downloadingModel,
                                fraction: fraction,
                                message: "Downloading Dots OCR 1.5…"
                            )
                        )
                    },
                    continuation: continuation
                )
                let configuration = URLSessionConfiguration.ephemeral
                configuration.waitsForConnectivity = true
                let session = URLSession(
                    configuration: configuration,
                    delegate: delegate,
                    delegateQueue: nil
                )
                delegate.retain(session: session)

                let task: URLSessionDownloadTask
                if let resumeData = try? Data(contentsOf: resumeDataURL), !resumeData.isEmpty {
                    task = session.downloadTask(withResumeData: resumeData)
                } else {
                    task = session.downloadTask(with: downloadURL)
                }
                taskBox.register(task)
                task.resume()
            }
        } onCancel: {
            taskBox.cancel()
        }
    }

    private func fileSize(at fileURL: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }

    private func reportDownloadProgress(
        _ completedBytes: Int64,
        artifact: LocalModelArtifact,
        progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void
    ) {
        progress(
            LocalProviderSetupProgress(
                phase: .downloadingModel,
                fraction: Double(completedBytes) / Double(DotsOCRModelManifest.totalBytes),
                message: "Resuming after \(artifact.path)…"
            )
        )
    }
}
