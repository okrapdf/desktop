import Foundation

enum UnlimitedOCRModelManifest {
    static let repository = "sahilchachra/unlimited-ocr-4bit-mlx"
    static let revision = "5df80100fca719eca44a4f5ec2e5a63d31881eb6"

    static let artifacts = [
        LocalModelArtifact(
            path: "chat_template.jinja",
            size: 191,
            sha256: "b4e4771e69892ebc712ed6986bcce490c65041d1545e85599cd4a531cfab98a5"
        ),
        LocalModelArtifact(
            path: "config.json",
            size: 3_101,
            sha256: "4ff0ff8b06596c000f0b9720718e23c3b812d7baf1259c9091bdf42dd36e79f5"
        ),
        LocalModelArtifact(
            path: "model.safetensors",
            size: 2_451_214_926,
            sha256: "41bfc9be24bbdca62cb844ac126c64c4be4539219f770707c48ff37eef02cd96"
        ),
        LocalModelArtifact(
            path: "model.safetensors.index.json",
            size: 72_573,
            sha256: "e408a502fa4df68cd92c201ca83e62522bf6545c5ba080de3c54357ea6e1680a"
        ),
        LocalModelArtifact(
            path: "processor_config.json",
            size: 459,
            sha256: "83f9dcda05e4363c9258e9ffdf6d2878fc12ec312da5de36d09ba738aff80d43"
        ),
        LocalModelArtifact(
            path: "special_tokens_map.json",
            size: 801,
            sha256: "ab4bd57ce17d62e39e0a39e739de1e407484f090f0b2c7e391312bca7a5b061a"
        ),
        LocalModelArtifact(
            path: "tokenizer.json",
            size: 9_979_028,
            sha256: "f2f866b0c0bb2d768bd2da88fe098b072cea54fc58b2027da1be7e29977230cf"
        ),
        LocalModelArtifact(
            path: "tokenizer_config.json",
            size: 545,
            sha256: "35310abe97bb678ed2bfff786e40a6b6884987bb87e1559f5045ae57504d924b"
        ),
    ]

    static let package = LocalModelPackageManifest(
        displayName: "Baidu Unlimited-OCR",
        upstreamRepository: "baidu/Unlimited-OCR",
        repository: repository,
        revision: revision,
        format: .mlxSafetensors,
        quantization: LocalModelQuantization(bits: 4, scheme: "affine-int4-group-64"),
        parameterCount: nil,
        licenseSPDXIdentifier: "MIT",
        licenseURL: URL(string: "https://github.com/baidu/baidu-idl/blob/master/LICENSE"),
        licenseRevision: nil,
        licenseNotice: nil,
        artifacts: artifacts
    )

    static let totalBytes = package.totalBytes

    static func downloadURL(for artifact: UnlimitedOCRModelArtifact) -> URL? {
        package.downloadURL(for: artifact)
    }
}
