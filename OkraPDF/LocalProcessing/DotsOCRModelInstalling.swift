import Foundation

protocol DotsOCRModelInstalling: Sendable {
    func install(
        runtime: DotsOCRRuntime,
        scriptURL: URL,
        progress: @escaping @Sendable (LocalProviderSetupProgress) -> Void
    ) async throws
}
