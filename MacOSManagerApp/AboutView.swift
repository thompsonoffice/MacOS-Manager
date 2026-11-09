import MacOSManagerCore
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(
                title: "macOS Manager",
                subtitle: "A private review prototype. It names a Mac and shows macOS versions Apple publishes for that model."
            )
            Text("VoiceOver can be turned on with Command-F5. If the Mac or Magic Keyboard has Touch ID, hold Command and press Touch ID three times. You can also use Apple menu, System Settings, Accessibility, VoiceOver. These steps are from Apple's VoiceOver User Guide.")
            if let url = session.catalog?.rules.voiceOverGuideURL {
                AppleLinkButton(
                    title: "Open Apple's VoiceOver on and off guide",
                    hint: "Opens Apple's VoiceOver User Guide in your browser.",
                    url: url
                )
            }
            Group {
                Text("What you can do here")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                Text("Look up a model identifier, Apple's model name, or a part number. On Install, read Apple's live catalog and download a version that catalog still serves and that this Mac can run. The download is checked with pkgutil, then installed into Applications. You can also open Apple's installer window, or create a USB after you type the volume name.")
                Text("What is still unverified")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                Text("The copy of this app is an unsigned package that installs into Applications. It is not a Mac App Store app, and it is not Developer ID signed or notarized. Gatekeeper, VoiceOver, pkgutil, the full installer download, and createinstallmedia have not been exercised on a physical Mac in this workspace. Install on this Mac opens Apple's window after the installer app is in Applications. It does not erase the running Mac in the background.")
                Text("The factory macOS, and the installers Software Update would offer this Mac today, are separate from the hardware list. If a fact is missing or two Apple records disagree, the result says unknown or shows both records.")
            }
            if let retrieved = session.catalog?.retrieved {
                Text("Apple facts in this copy were retrieved \(retrieved).")
            }
        }
    }
}
