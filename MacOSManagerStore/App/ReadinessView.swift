import MacOSManagerStoreCore
import SwiftUI

struct ReadinessScreen: View {
    @EnvironmentObject private var session: StoreSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button("Back to compatible versions") {
                session.showHome()
            }
            .accessibilityHint("Returns to the list of macOS versions. Does not install anything.")
            .accessibilityIdentifier("back-to-versions")

            if let readiness = session.readinessReport() {
                Text(readiness.headline)
                    .font(.largeTitle)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(readiness.spokenSummary)
                    .accessibilityHint("Spoken summary of the model, free space, memory, upgrade or downgrade, and power checks.")
                    .accessibilityIdentifier("readiness-summary")
                Text(readiness.marketingName)
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(readiness.checks) { check in
                    checkBlock(check)
                }

                Button("Show the checklist before you install") {
                    session.showChecklist()
                }
                .accessibilityHint("Opens backup, power, internet, restart, and VoiceOver reminders. Does not install macOS and does not open System Settings.")
                .accessibilityIdentifier("show-checklist")
            } else {
                Text("Choose a macOS version first. The readiness check has nothing to compare yet.")
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("readiness-summary")
            }
        }
    }

    private func checkBlock(_ check: ReadinessCheck) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(check.title)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(outcomeWord(check.outcome))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(check.detail)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("readiness-check-\(check.id)")
            }

            if let url = check.sourceURL, let title = check.sourceButtonTitle {
                Button(title) {
                    session.openSupportURL(url, title: title)
                }
                .accessibilityLabel("\(title) for \(check.title)")
                .accessibilityHint("Opens the Apple support page that states this requirement. Does not download macOS.")
                .accessibilityIdentifier("open-source-\(check.id)")
            }
        }
    }

    private func outcomeWord(_ outcome: CheckOutcome) -> String {
        switch outcome {
        case .pass:
            return "Pass"
        case .fail:
            return "Needs attention"
        case .notStated:
            return "Apple did not state a number"
        }
    }
}

struct ChecklistScreen: View {
    @EnvironmentObject private var session: StoreSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button("Back to the readiness result") {
                session.showReadinessAgain()
            }
            .accessibilityHint("Returns to the Ready or Not ready summary. Does not install anything.")
            .accessibilityIdentifier("back-to-readiness")

            Text("Before you install")
                .font(.largeTitle)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("checklist-heading")
            Text("This checklist does not install macOS. It reminds you what to do before you use Apple's own installer.")
                .foregroundStyle(.primary)

            if let readiness = session.readinessReport() {
                Text(readiness.headline)
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .accessibilityLabel(readiness.spokenSummary)
                    .accessibilityIdentifier("checklist-result")
            }

            ForEach(checklistItems) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("checklist-\(item.id)")
                    Text(item.detail)
                        .foregroundStyle(.primary)
                    ForEach(item.actions) { action in
                        Button(action.title) {
                            session.openChecklistLink(action)
                        }
                        .accessibilityLabel(action.title)
                        .accessibilityHint(action.hint)
                        .accessibilityIdentifier(action.id)
                    }
                }
            }
        }
    }

    private var checklistItems: [ChecklistItem] {
        let guide = session.catalog?.rules.voiceOverGuideURL ?? ""
        return PreinstallChecklist.items(voiceOverGuideURL: guide).map { item in
            ChecklistItem(
                id: item.id,
                title: item.title,
                detail: item.detail,
                actions: item.actions.filter { !$0.url.isEmpty }
            )
        }
    }
}
