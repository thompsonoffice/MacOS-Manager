import MacOSManagerCore
import SwiftUI

struct DownloadView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(
                title: "Download from Apple",
                subtitle: "These buttons open Apple's pages. To download an installer inside macOS Manager, use Install. That screen reads Apple's live catalog and only offers a version this Mac can run."
            )
            if let catalog = session.catalog {
                Picker("Version", selection: $session.selectedReleaseID) {
                    ForEach(catalog.compatibilityReleases) { release in
                        Text(release.marketingName).tag(release.id)
                    }
                }
                .accessibilityHint("Choose a macOS version. The choice does not start a download.")

                if let guidance = DownloadGuidance.make(catalog: catalog, releaseID: session.selectedReleaseID) {
                    if let report = session.report, report.found,
                       let version = report.versions.first(where: { $0.releaseID == guidance.releaseID }) {
                        Text("For the Mac you looked up, \(version.marketingName): \(version.claim.label).")
                    } else {
                        Text("Look up a Mac before reading this as support for your computer. The link below is still Apple's public path.")
                    }
                    Text(guidance.note)
                    ForEach(Array(guidance.steps.enumerated()), id: \.offset) { _, step in
                        Text(step)
                    }
                    AppleLinkButton(
                        title: guidance.primaryLinkTitle,
                        hint: "Opens an Apple page. Does not download an installer inside macOS Manager.",
                        url: guidance.primaryURL
                    )
                    if guidance.primaryURL != guidance.softwareUpdateHelpURL {
                        AppleLinkButton(
                            title: "Open Apple's Software Update instructions",
                            hint: "Opens the Mac user guide page that describes Software Update settings.",
                            url: guidance.softwareUpdateHelpURL
                        )
                    }
                    if let https = guidance.httpsURL, https != guidance.primaryURL {
                        AppleLinkButton(
                            title: "Open the https App Store page",
                            hint: "Same Apple product id as the Mac App Store link, using https.",
                            url: https
                        )
                    }
                    AppleLinkButton(
                        title: "Try Apple's Software Update settings link",
                        hint: "This is the Open Software Update settings link from Apple's Mac user guide. This prototype has not confirmed that another app can open it.",
                        url: guidance.settingsURLFromAppleHelp
                    )
                    Text("The settings link has not been verified from this app. If nothing opens, use the written steps: Apple menu, System Settings, General, Software Update.")
                    Text("Older than Catalina: this catalog has no per-model list. Apple's download article still links some older installers.")
                    AppleLinkButton(
                        title: "Open Apple's download article",
                        hint: "Opens the article that lists App Store and disk image links.",
                        url: catalog.rules.downloadArticleURL
                    )
                }
            }
        }
    }
}
