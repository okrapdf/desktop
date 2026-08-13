import Foundation

extension LocalProviderDescriptor {
    var downloadSizeBytes: Int64? {
        parserDefinition?.modelDelivery.pinnedPackage?.totalBytes
    }

    var installLocation: String? {
        switch id {
        case .appleVision:
            nil
        case .dotsOCR:
            "~/.okra/providers/dots-ocr"
        case .hybridAuto:
            nil
        case .unlimitedOCR:
            "~/.okra/providers/unlimited-ocr"
        case .ollama:
            nil
        }
    }
}
