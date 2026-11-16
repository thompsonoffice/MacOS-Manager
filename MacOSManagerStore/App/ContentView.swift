import MacOSManagerStoreCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: StoreSession

    var body: some View {
        Group {
            if let message = session.loadError, session.catalog == nil {
                loadFailure(message)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        statusBlock
                        thisMacBlock
                        compatibleList
                        aboutBlock
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("macOS Manager")
            }
        }
        .onAppear { session.start() }
        .accessibilityIdentifier("store-root")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("macOS Manager")
                .font(.largeTitle)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("app-title")
            Text("This App Store edition helps you install, upgrade, or downgrade macOS on this Mac. It reads the model identifier, lists every compatible version from Apple's published pages, and opens Apple's official installer or Software Update page for the version you choose. Apple handles the download and progress. This edition does not create a bootable USB installer.")
                .foregroundStyle(.secondary)
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            if session.isWorking {
                ProgressView("Working, the window is not frozen.")
                    .accessibilityIdentifier("working-indicator")
            }
            Text(session.statusMessage)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(session.statusMessage)
                .accessibilityValue(session.statusMessage)
                .accessibilityIdentifier("status-message")
        }
    }

    private var thisMacBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This Mac")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            if let identifier = session.reading?.modelIdentifier, !identifier.isEmpty {
                Text("Model identifier: \(identifier).")
                    .accessibilityIdentifier("model-identifier")
            } else {
                Text("Model identifier: not read yet.")
                    .accessibilityIdentifier("model-identifier")
            }
            if let report = session.report, report.found {
                Text("Apple's name: \(report.records.map(\.name).joined(separator: ", ")).")
                    .font(.headline)
                    .accessibilityIdentifier("model-name")
                if let chip = report.records.compactMap(\.chipLabel).first, report.records.count == 1 {
                    Text("Chip named by Apple: \(chip).")
                }
                Text("Processor class: \(report.processor.label).")
            } else if session.report != nil {
                Text("No Apple model name matched this identifier.")
                    .accessibilityIdentifier("model-name")
            } else {
                Text("Friendly model name: not looked up yet.")
                    .accessibilityIdentifier("model-name")
            }
            if let installed = session.installed {
                Text("Currently installed: \(installed.rawString).")
                    .accessibilityIdentifier("installed-version")
            } else {
                Text("Currently installed: not read yet.")
                    .accessibilityIdentifier("installed-version")
            }
            if let error = session.reading?.probeError {
                Text(error)
            }

            TextField("Model identifier", text: $session.queryText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Model identifier")
                .accessibilityHint("Type a hw.model identifier if the automatic reading is wrong or missing, then choose Look up.")
                .accessibilityIdentifier("identifier-field")
                .onSubmit { session.lookUpTypedIdentifier() }

            Button("Look up") {
                session.lookUpTypedIdentifier()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(session.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isWorking)
            .accessibilityHint("Looks up the typed identifier in the bundled Apple compatibility table. Does not change this Mac.")
            .accessibilityIdentifier("lookup-button")
        }
    }

    @ViewBuilder
    private var compatibleList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compatible macOS versions")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("compatible-version-list")
            Text("A version appears here only when Apple's compatibility page uses this exact model name, or when Apple's published Apple silicon statement covers it. Similar names are not treated as a match. Choose a version to install, upgrade, or downgrade on this Mac. Versions older than macOS Catalina have no per-model list in this table.")
                .foregroundStyle(.secondary)
            if let report = session.report, report.found {
                let rows = report.compatibleVersions
                if rows.isEmpty {
                    Text("The bundled table does not list a compatible version for this exact model name.")
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(rows) { version in
                            versionRow(version, catalog: session.catalog)
                        }
                    }
                }
            } else {
                Text("Compatible versions will appear here after this Mac is identified.")
            }
            if let catalog = session.catalog {
                Button("Open Apple's Software Update instructions") {
                    session.openSupportURL(
                        catalog.rules.softwareUpdateHelpURL,
                        title: "Apple's Software Update instructions"
                    )
                }
                .accessibilityHint("Opens Apple's Mac User Guide page that describes Software Update. Use it to install or upgrade on this Mac. Apple handles the download and progress. macOS Manager does not run the softwareupdate command.")
                .accessibilityIdentifier("open-software-update-instructions")
            }
        }
    }

    @ViewBuilder
    private func versionRow(_ version: VersionAssessment, catalog: Catalog?) -> some View {
        let installedHere = session.installed?.marks(releaseID: version.releaseID) == true
        let route = catalog.flatMap { DownloadRoute.officialRoute(catalog: $0, releaseID: version.releaseID) }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(version.marketingName)
                    .font(.title3)
                    .accessibilityAddTraits(.isHeader)
                if installedHere {
                    Text("Currently installed")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .accessibilityLabel("Currently installed")
                        .accessibilityIdentifier("installed-badge-\(version.releaseID)")
                }
            }
            Text("Latest build on Apple's version table: \(version.latestBuild).")
            Text(version.claim.label + ".")
            if let statement = version.blanketStatement {
                Text(statement)
            }
            Text(purposeText(for: version))
            if let route {
                Text(route.explanation)
                Button(route.buttonTitle) {
                    session.openOfficialRoute(route)
                }
                .accessibilityLabel(route.buttonTitle)
                .accessibilityHint(route.accessibilityHint)
                .accessibilityIdentifier("open-apple-download-\(version.releaseID)")
            }
            if let url = version.compatibilityPageURL {
                Button("Open Apple's compatibility page for \(version.marketingName)") {
                    session.openSupportURL(url, title: "Apple's compatibility page for \(version.marketingName)")
                }
                .accessibilityHint("Opens the Apple Support list used to decide compatibility. Does not download macOS.")
                .accessibilityIdentifier("open-compatibility-\(version.releaseID)")
            }
        }
        .padding(.vertical, 4)
    }

    private var aboutBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About this edition")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            Text("Facts in the compatibility table were read from public Apple Support pages on 2026-11-06. Sources are listed in the repository file MacOSManagerStore/SOURCES.md.")
            Text("Privacy: data is not collected. The app does not send the model identifier, the installed version, or anything else to a server. Opening an Apple page uses Apple's own site in your default browser or the App Store.")
            Text("Creating a bootable macOS USB installer is available in the full edition of macOS Manager, which is a separate product. This App Store edition does not include that feature.")
        }
    }


    private func purposeText(for version: VersionAssessment) -> String {
        switch session.installed?.action(forReleaseID: version.releaseID) {
        case .currentlyInstalled:
            return "This is the version currently running on this Mac."
        case .upgrade:
            return "Choosing this version would upgrade this Mac. The button opens Apple's official installer or Software Update page. Apple handles the download and progress."
        case .downgrade:
            return "Choosing this version would install or downgrade this Mac to an older compatible system. The button opens Apple's official installer or Support page. Apple handles the download and progress. Software Update may not offer every older version."
        default:
            return "The button opens Apple's official installer or Software Update page so you can install this version on this Mac. Apple handles the download and progress."
        }
    }

    private func loadFailure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The compatibility table did not load")
                .font(.title)
                .accessibilityAddTraits(.isHeader)
            Text(message)
            Text("macOS Manager cannot list compatible versions until the bundled Apple facts file loads.")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("store-root")
    }
}
