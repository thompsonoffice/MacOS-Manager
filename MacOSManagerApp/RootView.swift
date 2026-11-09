import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: Session
    @AccessibilityFocusState private var statusFocused: Bool

    var body: some View {
        Group {
            if let message = session.loadError, session.catalog == nil {
                LoadFailureView(message: message)
            } else {
                NavigationSplitView {
                    List(AppScreen.allCases, selection: screenSelection) { screen in
                        Text(screen.title)
                            .tag(screen)
                            .accessibilityHint(screen.hint)
                    }
                    .navigationTitle("macOS Manager")
                    .listStyle(.sidebar)
                } detail: {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            screenContent
                            StatusBlock(message: session.statusMessage, rawDetail: session.statusDetail)
                                .accessibilityFocused($statusFocused)
                        }
                        .frame(maxWidth: 760, alignment: .leading)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .onAppear { session.load() }
        .onChange(of: session.screen) { _, screen in
            session.announce(screen.title + ". " + screen.hint)
        }
        .onChange(of: session.statusDetail) { _, detail in
            if let detail, !detail.isEmpty {
                statusFocused = true
            }
        }
    }

    /// macOS `List` selection is optional. A non-optional binding does not match that initializer.
    private var screenSelection: Binding<AppScreen?> {
        Binding(
            get: { session.screen },
            set: { newValue in
                if let newValue {
                    session.screen = newValue
                }
            }
        )
    }

    @ViewBuilder
    private var screenContent: some View {
        switch session.screen {
        case .about:
            AboutView()
        case .identify:
            IdentifyView()
        case .compatibility:
            CompatibilityView()
        case .download:
            DownloadView()
        case .usb:
            USBView()
        }
    }
}

struct LoadFailureView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The catalog did not load")
                .font(.title)
                .accessibilityAddTraits(.isHeader)
            Text(message)
            Text("macOS Manager cannot look up a Mac until the bundled Apple facts file loads.")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }
}

struct StatusBlock: View {
    let message: String
    var rawDetail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .textSelection(.enabled)
                .accessibilityLabel("Status. \(message)")
                .accessibilityAddTraits(.updatesFrequently)
                .focusable(true)
            if let rawDetail, !rawDetail.isEmpty {
                DisclosureGroup("Technical detail") {
                    Text(rawDetail)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .accessibilityLabel("Technical detail")
                        .accessibilityValue(rawDetail)
                }
                .accessibilityHint("The original message from the command. The status above is the plain-language result.")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct SectionHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

struct AppleLinkButton: View {
    @EnvironmentObject private var session: Session
    let title: String
    let hint: String
    let url: String

    var body: some View {
        Button(title) {
            session.openAppleURL(url)
        }
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}
