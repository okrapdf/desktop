import Foundation

enum LocalProviderPaths {
    static var runsRoot: URL {
        runsRoot(
            applicationSupportDirectory: FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
        )
    }

    static func runsRoot(applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("Okra", isDirectory: true)
            .appendingPathComponent("Runs", isDirectory: true)
    }

    static var providersRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".okra", isDirectory: true)
            .appendingPathComponent("providers", isDirectory: true)
    }

    static var dotsOCRRoot: URL {
        providersRoot.appendingPathComponent("dots-ocr", isDirectory: true)
    }

    static var dotsOCRPython: URL {
        dotsOCRRoot
            .appendingPathComponent("venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
    }

    static var dotsOCRModel: URL {
        dotsOCRRoot.appendingPathComponent("model", isDirectory: true)
    }

    static var dotsOCRReadyMarker: URL {
        dotsOCRRoot.appendingPathComponent(".ready")
    }

    static var unlimitedOCRRoot: URL {
        providersRoot.appendingPathComponent("unlimited-ocr", isDirectory: true)
    }

    static var unlimitedOCRPython: URL {
        unlimitedOCRRoot
            .appendingPathComponent("venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
    }

    static var unlimitedOCRModel: URL {
        unlimitedOCRRoot.appendingPathComponent("model", isDirectory: true)
    }

    static var unlimitedOCRReadyMarker: URL {
        unlimitedOCRRoot.appendingPathComponent(".ready")
    }

    static func runDirectory(runsRoot: URL = runsRoot, runID: String) -> URL {
        runsRoot.appendingPathComponent(runID, isDirectory: true)
    }
}
