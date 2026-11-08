import MacOSManagerCore
import SwiftUI

struct IdentifyView: View {
    @EnvironmentObject private var session: Session
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(
                title: "Identify this Mac",
                subtitle: "Read hw.model, or type an identifier, model name, or part number. Nothing is installed."
            )
            Text("To find the identifier yourself, hold Option and choose Apple menu, System Information. Select Hardware. The model identifier is on that page. To hear the serial number, choose File, Speak Serial Number, or press Command-4. Apple describes this in the model and serial number article.")
            AppleLinkButton(
                title: "Open Apple's model and serial number article",
                hint: "Opens Apple Support. Does not read this Mac.",
                url: "https://support.apple.com/en-us/102767"
            )
            Button("Read the model identifier from this Mac") {
                session.readThisMac()
            }
            .accessibilityHint("Uses sysctl hw.model and hw.machine. Does not run softwareupdate. Whether the App Sandbox allows sysctl has not been tested.")

            if let reading = session.reading {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Probe: \(reading.probeMethod).")
                    Text(reading.sandboxStatus)
                    if let version = reading.operatingSystemVersion {
                        Text("Installed system reported by macOS: \(version).")
                    }
                    if let error = reading.probeError {
                        Text(error)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Picker("Look up using", selection: $session.lookupKind) {
                ForEach(LookupKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityHint(session.lookupKind.hint)

            TextField(session.lookupKind.fieldLabel, text: $session.queryText)
                .focused($fieldFocused)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(session.lookupKind.fieldLabel)
                .accessibilityHint(session.lookupKind.hint)
                .onSubmit { session.lookUp() }

            Button("Look up") {
                session.lookUp()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(session.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityHint("Looks up the text in Apple's published model pages. Does not change this Mac.")

            if let report = session.report {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Result")
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(report.sentences.enumerated()), id: \.offset) { _, sentence in
                        Text(sentence)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .onAppear { fieldFocused = true }
    }
}
