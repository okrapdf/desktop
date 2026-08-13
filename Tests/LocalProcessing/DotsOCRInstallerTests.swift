import Foundation
import Testing
@testable import Okra

struct DotsOCRInstallerTests {
    @Test("Ready marker accepts only the current model and runtime lock")
    func readyMarkerValidation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("okra-dots-marker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let markerURL = root.appendingPathComponent(".ready")
        let runtime = makeRuntime(root: root, readyMarkerURL: markerURL)

        try DotsOCRReadyMarker.current().write(to: markerURL)
        #expect(runtime.hasCurrentReadyMarker)
        #expect(runtime.hasCurrentModelArtifacts == false)

        let staleRuntime = DotsOCRReadyMarker(
            schemaVersion: DotsOCRReadyMarker.schemaVersion,
            modelRevision: DotsOCRModelManifest.revision,
            runtimeLockVersion: "older-runtime-lock",
            installedAt: Date.now.ISO8601Format()
        )
        try staleRuntime.write(to: markerURL)
        #expect(runtime.hasCurrentReadyMarker == false)

        let staleModel = DotsOCRReadyMarker(
            schemaVersion: DotsOCRReadyMarker.schemaVersion,
            modelRevision: "older-model-revision",
            runtimeLockVersion: DotsOCRReadyMarker.runtimeLockVersion,
            installedAt: Date.now.ISO8601Format()
        )
        try staleModel.write(to: markerURL)
        #expect(runtime.hasCurrentReadyMarker == false)

        try "legacy timestamp\n".write(to: markerURL, atomically: true, encoding: .utf8)
        #expect(runtime.hasCurrentReadyMarker == false)
    }

    @Test("Installer invalidates stale readiness before runtime setup")
    func installInvalidatesStaleMarker() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("okra-dots-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let markerURL = root.appendingPathComponent(".ready")
        let scriptURL = root.appendingPathComponent("fail-install.sh")
        let runtime = makeRuntime(root: root, readyMarkerURL: markerURL)
        try DotsOCRReadyMarker.current().write(to: markerURL)
        try "#!/bin/zsh\nexit 42\n".write(to: scriptURL, atomically: true, encoding: .utf8)

        let installer = DotsOCRModelInstaller(downloader: NoopDotsOCRModelDownloader())
        do {
            try await installer.install(runtime: runtime, scriptURL: scriptURL) { _ in }
            Issue.record("A failing runtime installer unexpectedly succeeded")
        } catch {
            // Expected: readiness must remain absent after any interrupted setup.
        }

        #expect(FileManager.default.fileExists(atPath: markerURL.path) == false)
    }

    private func makeRuntime(root: URL, readyMarkerURL: URL) -> DotsOCRRuntime {
        DotsOCRRuntime(
            rootURL: root,
            pythonURL: root.appendingPathComponent("venv/bin/python"),
            modelURL: root.appendingPathComponent("model", isDirectory: true),
            readyMarkerURL: readyMarkerURL,
            cacheURL: root.appendingPathComponent("huggingface", isDirectory: true),
            workerURL: root.appendingPathComponent("worker.py"),
            isSimulation: false
        )
    }
}

private struct NoopDotsOCRModelDownloader: DotsOCRModelDownloading {
    func downloadModel(
        to modelURL: URL,
        progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void
    ) async throws {}
}
