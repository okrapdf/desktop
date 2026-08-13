import Foundation

enum DotsOCRModelManifest {
    static let repository = "mlx-community/dots.mocr-4bit"
    static let revision = "708b576de556b0cdba615ecd211db3b951ec09ef"

    static let artifacts = [
        LocalModelArtifact(
            path: "chat_template.jinja",
            size: 1_119,
            sha256: "7bcde5a3e537309d3316239825b950a337dd34562cd5171cdb811134fd9a23ce"
        ),
        LocalModelArtifact(
            path: "chat_template.json",
            size: 1_147,
            sha256: "c8d629ba2b3133376f1e64b980f82438945741fba5334db768afb281af93c4a9"
        ),
        LocalModelArtifact(
            path: "config.json",
            size: 1_720,
            sha256: "a5d6e4640051ae7085e2dd33d41379d366dcce56237ba24fa4622d79e8b70830"
        ),
        LocalModelArtifact(
            path: "configuration_dots.py",
            size: 3_150,
            sha256: "aa85add6cdaedfd947d25b850410de4506fc299dc55140d0cc5352c9737151fe"
        ),
        LocalModelArtifact(
            path: "generation_config.json",
            size: 86,
            sha256: "d9ca5bd51bbf3b3b2b418f2b2d296cb4286ef2f02dc76dd7361d82ffd9d4e7ca"
        ),
        LocalModelArtifact(
            path: "model.safetensors",
            size: 3_524_130_967,
            sha256: "9310766f72e340f995e43662ccf55f5999e034ef85d9e8624a744574e624d0c5"
        ),
        LocalModelArtifact(
            path: "model.safetensors.index.json",
            size: 83_910,
            sha256: "43fa0d8c1d2536687d2fce8a5e2d7078a189bd11cb07cd06c8b2e0c15aafef5c"
        ),
        LocalModelArtifact(
            path: "modeling_dots_ocr.py",
            size: 4_981,
            sha256: "274b5bfa35f624f15001da70414e733b89f5cb44b5453d80023bff26a68d0135"
        ),
        LocalModelArtifact(
            path: "modeling_dots_vision.py",
            size: 14_890,
            sha256: "f22d6251a05a03c7510d329ba1be9e959438cd54b32204eb51ccb1b56392a96f"
        ),
        LocalModelArtifact(
            path: "preprocessor_config.json",
            size: 432,
            sha256: "fec8b3187ab0ae340f6d0b1f6f892a53c63b73b328836c83dd7bff1d5bc4c79a"
        ),
        LocalModelArtifact(
            path: "processor_config.json",
            size: 735,
            sha256: "69edbef36d2dd554e4d1f8fb6ad742843e8c16728922dc9aa22f9b68fdb8a72b"
        ),
        LocalModelArtifact(
            path: "special_tokens_map.json",
            size: 494,
            sha256: "92b060f39417514eed2f7652f454a3d5afb0e4a57b9f4b51dd4d1dfd8fdb9736"
        ),
        LocalModelArtifact(
            path: "tokenizer.json",
            size: 11_426_251,
            sha256: "904d81ff0cfa066dbc0b6a21e10ded6ebb7c2d8df14100d851f90bb7878bd5de"
        ),
        LocalModelArtifact(
            path: "tokenizer_config.json",
            size: 702,
            sha256: "f18a7062fdb3b2213bce50801d6297f51c8e8d37f909c8153f80b9be17c0bf39"
        ),
        LocalModelArtifact(
            path: "vocab.json",
            size: 2_776_833,
            sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"
        ),
    ]

    static let package = LocalModelPackageManifest(
        displayName: "Dots OCR 1.5 (dots.mocr)",
        upstreamRepository: "dots-studio/dots.mocr",
        repository: repository,
        revision: revision,
        format: .mlxSafetensors,
        quantization: LocalModelQuantization(bits: 4, scheme: "affine-int4-group-64"),
        parameterCount: 3_000_000_000,
        licenseSPDXIdentifier: "LicenseRef-dots-mocr",
        licenseURL: URL(
            string: "https://huggingface.co/dots-studio/dots.mocr/blob/e539fbb52280393adc081b289ec597430a0f9031/dots.mocr%20LICENSE%20AGREEMENT"
        ),
        licenseRevision: "e539fbb52280393adc081b289ec597430a0f9031",
        licenseNotice: "Use is subject to the pinned dots.mocr agreement, including acceptable-use, privacy and security, copyright, and dispute-resolution terms.",
        artifacts: artifacts
    )

    static let totalBytes = package.totalBytes

    static func downloadURL(for artifact: LocalModelArtifact) -> URL? {
        package.downloadURL(for: artifact)
    }
}
