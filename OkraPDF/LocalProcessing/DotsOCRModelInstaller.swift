import Foundation

struct DotsOCRModelInstaller: DotsOCRModelInstalling {
    private let downloader: any DotsOCRModelDownloading

    init(downloader: any DotsOCRModelDownloading = DotsOCRModelDownloader()) {
        self.downloader = downloader
    }

    func install(
        runtime: DotsOCRRuntime,
        scriptURL: URL,
        progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void
    ) async throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: runtime.readyMarkerURL.path) {
            try fileManager.removeItem(at: runtime.readyMarkerURL)
        }
        progress(
            LocalProviderSetupProgress(
                phase: .preparing,
                fraction: nil,
                message: "Preparing the private Dots OCR runtime…"
            )
        )
        try fileManager.createDirectory(at: runtime.rootURL, withIntermediateDirectories: true)

        progress(
            LocalProviderSetupProgress(
                phase: .installingRuntime,
                fraction: nil,
                message: "Installing the pinned MLX runtime…"
            )
        )
        _ = try await LocalCommandRunner.runAsync(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [scriptURL.path, runtime.rootURL.path]
        )
        try Task.checkCancellation()

        progress(
            LocalProviderSetupProgress(
                phase: .downloadingModel,
                fraction: 0,
                message: "Downloading Dots OCR 1.5…"
            )
        )
        try await downloader.downloadModel(to: runtime.modelURL, progress: progress)
        try Task.checkCancellation()

        try DotsOCRReadyMarker.current().write(to: runtime.readyMarkerURL)
        progress(
            LocalProviderSetupProgress(
                phase: .ready,
                fraction: 1,
                message: "Dots OCR 1.5 is ready offline."
            )
        )
    }
}
