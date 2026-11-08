import MacOSManagerCore
import SwiftUI

struct CompatibilityView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(
                title: "Compatible versions",
                subtitle: "Listed means Apple's compatibility page uses this exact model name. A similar name is not treated as a match."
            )
            if let report = session.report, report.found {
                modelHeader(report)
                ForEach(report.versions) { version in
                    versionBlock(version)
                }
                Text(report.factoryOperatingSystem)
                Text(report.installersCurrentlyOffered)
            } else if session.report != nil {
                Text("No Apple model matched. Go to Identify this Mac and try the identifier from System Information.")
            } else {
                Text("No Mac has been looked up yet. Go to Identify this Mac first.")
            }
        }
    }

    @ViewBuilder
    private func modelHeader(_ report: CompatibilityReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Models Apple lists for this lookup")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            ForEach(report.records) { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.name).font(.headline)
                    if record.identifiers.isEmpty {
                        Text("No hw.model identifier is published for this name in the catalog.")
                    } else {
                        Text("Model identifier: \(record.identifiers.joined(separator: ", ")).")
                    }
                    if let year = record.yearIntroduced {
                        Text("Year introduced: \(year).")
                    }
                    if let chip = record.chipLabel {
                        Text("Chip named by Apple: \(chip).")
                    }
                    if let note = record.note {
                        Text(note)
                    }
                    AppleLinkButton(
                        title: "Open Apple's page for \(record.name)",
                        hint: "Opens the Apple Support page this name was taken from.",
                        url: record.sourceURL
                    )
                }
                .padding(.bottom, 8)
            }
            Text("Processor class: \(report.processor.label). \(report.processor.explanation)")
            Text("\(report.t2.label). \(report.t2.explanation)")
            Text(report.architecture.spoken)
            switch report.newest {
            case .stated(let text, let footnote):
                Text("Newest system on Apple's identify page: \(text).")
                if let footnote {
                    Text(footnote)
                }
            case .notStated:
                Text("Apple's identify page used here does not name a newest system.")
            case .disagrees(let texts):
                Text("Newest system disagrees: \(texts.joined(separator: ", ")).")
            }
        }
    }

    private func versionBlock(_ version: VersionAssessment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(version.marketingName)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Latest build on Apple's version table: \(version.latestBuild).")
            Text(version.claim.label + ".")
            if !version.exactModelNames.isEmpty, version.exactModelNames.count > 1 {
                Text("Exact name match: \(version.exactModelNames.joined(separator: ", ")).")
            }
            if !version.notListedModelNames.isEmpty, version.claim == .differsAcrossRecords {
                Text("Not listed for: \(version.notListedModelNames.joined(separator: ", ")).")
            }
            if !version.nearMissNames.isEmpty, version.claim != .listedOnApplePage {
                Text("Similar name on the page, not used as a match: \(version.nearMissNames.joined(separator: ", ")).")
            }
            if let statement = version.blanketStatement {
                Text(statement)
            }
            if let url = version.compatibilityPageURL {
                AppleLinkButton(
                    title: "Open Apple's compatibility page for \(version.marketingName)",
                    hint: "Opens the Apple Support list for this macOS version.",
                    url: url
                )
            }
        }
        .padding(.vertical, 4)
    }
}
