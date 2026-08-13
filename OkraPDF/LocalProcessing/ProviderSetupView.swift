import SwiftUI

struct ProviderSetupView: View {
    @ObservedObject var coordinator: LocalProcessingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.standardSpacing) {
            if let setupProgress = coordinator.setupProgress {
                HStack {
                    Text(setupProgress.phase.title)
                        .font(.headline)
                    Spacer()
                    if let fraction = setupProgress.fraction {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary)
                    }
                }

                if let fraction = setupProgress.fraction {
                    ProgressView(value: fraction)
                        .accessibilityLabel(setupProgress.message)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(setupProgress.message)
                }

                Text(setupProgress.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Cancel setup", role: .cancel, action: coordinator.cancelInstallation)
                    .buttonStyle(.bordered)
            } else {
                setupSummary

                if let error = coordinator.setupErrorMessage {
                    WorkspaceNoticeView(
                        message: error,
                        systemImage: "exclamationmark.triangle.fill",
                        color: .red
                    )
                }

                Button(action: coordinator.installSelectedProvider) {
                    Text(coordinator.setupErrorMessage == nil
                         ? setupButtonTitle
                         : "Retry setup")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(setupAccessibilityHint)
            }
        }
        .padding(WorkspaceTheme.standardSpacing)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: WorkspaceTheme.cardRadius))
    }

    private var setupSummary: some View {
        VStack(alignment: .leading, spacing: WorkspaceTheme.compactSpacing) {
            Text("One-time local model setup")
                .font(.headline)
            Text("Okra downloads and verifies this pinned model on this Mac. After setup, PDF extraction runs locally.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let downloadSize = coordinator.selectedDescriptor.downloadSizeBytes {
                LabeledContent("Download") {
                    Text(downloadSize, format: .byteCount(style: .file))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let location = coordinator.selectedDescriptor.installLocation {
                LabeledContent("Location", value: location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let package = coordinator.selectedDescriptor.parserDefinition?
                .modelDelivery.pinnedPackage,
               let licenseURL = package.licenseURL {
                if let licenseNotice = package.licenseNotice {
                    Text(licenseNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Link("Read model license and use terms", destination: licenseURL)
                    .font(.caption)
            }
        }
    }

    private var setupButtonTitle: String {
        if coordinator.selectedDescriptor.parserDefinition?
            .modelDelivery.pinnedPackage?.licenseNotice != nil {
            return "Agree & set up \(coordinator.selectedDescriptor.name)"
        }
        return "Set up \(coordinator.selectedDescriptor.name)"
    }

    private var setupAccessibilityHint: String {
        if coordinator.selectedDescriptor.parserDefinition?
            .modelDelivery.pinnedPackage?.licenseNotice != nil {
            return "Accepts the linked model terms and downloads this provider for offline extraction"
        }
        return "Downloads this provider once for future offline extraction"
    }
}
