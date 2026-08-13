import Foundation

enum LocalProviderID: String, CaseIterable, Codable, Hashable, Sendable {
    case appleVision = "apple-vision"
    case dotsOCR = "dots-ocr"
    case hybridAuto = "hybrid-auto"
    case unlimitedOCR = "unlimited-ocr"
    case ollama

    static func persisted(rawValue: String) -> LocalProviderID? {
        rawValue == "chandra" ? .ollama : LocalProviderID(rawValue: rawValue)
    }
}

struct LocalProviderDescriptor: Identifiable, Equatable {
    let id: LocalProviderID
    let name: String
    let summary: String
    let setupNote: String?
    let parserDefinition: LocalParserDefinition?

    init(
        id: LocalProviderID,
        name: String,
        summary: String,
        setupNote: String?,
        parserDefinition: LocalParserDefinition? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.setupNote = setupNote
        self.parserDefinition = parserDefinition
    }
}

enum LocalProviderAvailability: Equatable {
    case ready
    case simulated(String)
    case setupRequired(String)
    case unavailable(String)

    var isReady: Bool {
        switch self {
        case .ready, .simulated:
            return true
        case .setupRequired, .unavailable:
            return false
        }
    }

    var isSimulated: Bool {
        if case .simulated = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .ready:
            return "Ready offline"
        case .simulated(let message), .setupRequired(let message), .unavailable(let message):
            return message
        }
    }
}

struct LocalPageProgressUpdate: Equatable, Sendable {
    let parserID: LocalProviderID
    let pageNumber: Int
    let state: ParserLifecycleState
    let completedPageCount: Int
    let totalPageCount: Int
    let message: String?

    var fraction: Double {
        guard totalPageCount > 0 else { return 0 }
        return Double(completedPageCount) / Double(totalPageCount)
    }
}

typealias LocalPageProgress = @Sendable (LocalPageProgressUpdate) -> Void

struct LocalProcessingRequest: Sendable {
    let parserID: LocalProviderID
    let fileName: String
    let sourceURL: URL
    let outputDirectory: URL
    let expectedPageCount: Int
    let pageProgress: LocalPageProgress

    init(
        parserID: LocalProviderID,
        fileName: String,
        sourceURL: URL,
        outputDirectory: URL,
        expectedPageCount: Int,
        pageProgress: @escaping LocalPageProgress = { _ in }
    ) {
        self.parserID = parserID
        self.fileName = fileName
        self.sourceURL = sourceURL
        self.outputDirectory = outputDirectory
        self.expectedPageCount = expectedPageCount
        self.pageProgress = pageProgress
    }
}

struct LocalProcessingResult {
    let outputURL: URL
    let pageCount: Int
    let structuredOutputURL: URL?

    init(
        outputURL: URL,
        pageCount: Int,
        structuredOutputURL: URL? = nil
    ) {
        self.outputURL = outputURL
        self.pageCount = pageCount
        self.structuredOutputURL = structuredOutputURL
    }
}

struct LocalProcessingRun: Identifiable, Codable, Equatable {
    let id: String
    let sourcePath: String
    let fileName: String
    let providerId: String
    let providerName: String
    let executionMode: String?
    var status: String
    var outputPath: String?
    var structuredOutputPath: String? = nil
    var errorMessage: String?
    var pageCount: Int
    var completedPageCount: Int? = nil
    var totalPageCount: Int? = nil
    let startedAt: Date
    var completedAt: Date?
    var progress: Double? = nil
    var statusMessage: String? = nil
    var updatedAt: Date? = nil
    var cancelRequestedAt: Date? = nil
    var resumeCount: Int? = nil
    var eventSequence: Int? = nil
    var pageLifecycles: [ParserPageLifecycle]? = nil
}

struct LocalProcessingRunEvent: Codable, Equatable, Sendable {
    let sequence: Int
    let type: String
    let runId: String
    let status: String
    let progress: Double
    let completedPageCount: Int
    let totalPageCount: Int
    let message: String
    let createdAt: Date
}

typealias LocalProcessingProgress = @Sendable (_ fraction: Double, _ message: String) -> Void

protocol LocalProcessingProvider: AnyObject {
    var descriptor: LocalProviderDescriptor { get }
    func availability() -> LocalProviderAvailability
    func install(progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void) async throws
    func process(
        request: LocalProcessingRequest,
        progress: @escaping LocalProcessingProgress
    ) async throws -> LocalProcessingResult
}

extension LocalProcessingProvider {
    func install(progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void) async throws {
        throw LocalProcessingError.installNotSupported(descriptor.name)
    }
}

enum LocalProcessingError: LocalizedError {
    case installNotSupported(String)
    case missingResource(String)
    case invalidPDF
    case noPages
    case providerUnavailable(String)
    case commandFailed(command: String, status: Int32, output: String)
    case missingOutput(String)
    case invalidModelDownloadURL(String)
    case modelIntegrityFailed(provider: String, artifact: String)

    var errorDescription: String? {
        switch self {
        case .installNotSupported(let provider):
            return "Automatic setup is not available for \(provider)."
        case .missingResource(let name):
            return "The app is missing its bundled \(name) resource."
        case .invalidPDF:
            return "The PDF could not be opened."
        case .noPages:
            return "The PDF does not contain any pages."
        case .providerUnavailable(let reason):
            return reason
        case .commandFailed(let command, let status, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let clippedDetail = detail.count > 2_000 ? String(detail.suffix(2_000)) : detail
            return clippedDetail.isEmpty
                ? "\(command) exited with status \(status)."
                : "\(command) failed: \(clippedDetail)"
        case .missingOutput(let provider):
            return "\(provider) finished without producing Markdown."
        case .invalidModelDownloadURL(let artifact):
            return "The download URL for \(artifact) is invalid."
        case .modelIntegrityFailed(let provider, let artifact):
            return "\(artifact) did not match the pinned \(provider) model. Retry setup to download it again."
        }
    }
}
