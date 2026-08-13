import Foundation

struct DotsOCRReadyMarker: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let runtimeLockVersion = "python>=3.10|mlx-vlm==0.6.6|huggingface-hub==1.24.0|v1"

    let schemaVersion: Int
    let modelRevision: String
    let runtimeLockVersion: String
    let installedAt: String

    static func current(installedAt: Date = .now) -> DotsOCRReadyMarker {
        DotsOCRReadyMarker(
            schemaVersion: schemaVersion,
            modelRevision: DotsOCRModelManifest.revision,
            runtimeLockVersion: runtimeLockVersion,
            installedAt: installedAt.ISO8601Format()
        )
    }

    var matchesCurrentRuntime: Bool {
        schemaVersion == Self.schemaVersion
            && modelRevision == DotsOCRModelManifest.revision
            && runtimeLockVersion == Self.runtimeLockVersion
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func read(from url: URL) -> DotsOCRReadyMarker? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DotsOCRReadyMarker.self, from: data)
    }
}

struct DotsOCRRuntime: Sendable {
    let rootURL: URL
    let pythonURL: URL
    let modelURL: URL
    let readyMarkerURL: URL
    let cacheURL: URL
    let workerURL: URL?
    let isSimulation: Bool

    var hasCurrentReadyMarker: Bool {
        guard let marker = DotsOCRReadyMarker.read(from: readyMarkerURL) else {
            return false
        }
        return marker.matchesCurrentRuntime
    }

    var hasCurrentModelArtifacts: Bool {
        DotsOCRModelManifest.artifacts.allSatisfy { artifact in
            let artifactURL = modelURL.appendingPathComponent(artifact.path)
            guard let attributes = try? FileManager.default.attributesOfItem(
                atPath: artifactURL.path
            ), let size = attributes[.size] as? NSNumber else {
                return false
            }
            return size.int64Value == artifact.size
        }
    }

    static func installed(workerURL: URL?) -> DotsOCRRuntime {
        DotsOCRRuntime(
            rootURL: LocalProviderPaths.dotsOCRRoot,
            pythonURL: LocalProviderPaths.dotsOCRPython,
            modelURL: LocalProviderPaths.dotsOCRModel,
            readyMarkerURL: LocalProviderPaths.dotsOCRReadyMarker,
            cacheURL: LocalProviderPaths.dotsOCRRoot
                .appendingPathComponent("huggingface", isDirectory: true),
            workerURL: workerURL,
            isSimulation: false
        )
    }

    static func simulated(workerURL: URL?) -> DotsOCRRuntime {
        let pythonCandidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/python3"),
            URL(fileURLWithPath: "/usr/local/bin/python3"),
            URL(fileURLWithPath: "/usr/bin/python3"),
        ]
        let pythonURL = pythonCandidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        } ?? URL(fileURLWithPath: "/usr/bin/python3")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("okra-dots-ocr-simulation", isDirectory: true)
        return DotsOCRRuntime(
            rootURL: root,
            pythonURL: pythonURL,
            modelURL: root.appendingPathComponent("model", isDirectory: true),
            readyMarkerURL: root.appendingPathComponent(".ready"),
            cacheURL: root.appendingPathComponent("huggingface", isDirectory: true),
            workerURL: workerURL,
            isSimulation: true
        )
    }
}
