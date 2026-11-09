import MacOSManagerCore
import SwiftUI

struct USBView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(
                title: "Install",
                subtitle: "Download an installer Apple is still serving for this Mac, install it on this Mac, or create a bootable USB. The USB is an installer, not a portable copy of macOS."
            )
            .onAppear { session.prepareHost() }
            versionSection
            installerSection
            actionSection
            if !session.progressLines.isEmpty {
                Text("Progress")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(session.progressLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
                Button("Cancel") { session.cancelWork() }
                    .disabled(!session.isWorking)
                    .accessibilityHint("Stops the current program before the next step. It cannot undo an erase that already started.")
            }
        }
    }

    @ViewBuilder
    private var versionSection: some View {
        Text("Version")
            .font(.title2)
            .accessibilityAddTraits(.isHeader)
        Text(hostSummary)
        if let host = session.hostReport, let lookup = session.report,
           let difference = InstallerOffers.differentMacExplanation(host: host, lookup: lookup) {
            Text(difference)
        }
        if session.didReadLiveCatalog {
            if session.installerOffers.isEmpty {
                Text("Apple's live catalog did not include an installer this Mac can run.")
            } else {
                Picker("macOS version", selection: $session.selectedReleaseID) {
                    ForEach(session.installerOffers) { offer in
                        Text(offerLabel(offer)).tag(offer.releaseID)
                    }
                }
                .pickerStyle(.radioGroup)
                .accessibilityHint("Only versions in Apple's live catalog that this Mac can run. Choosing one does not start the download.")
            }
            ForEach(session.installerRefusals) { refusal in
                Text(refusal.plainLanguage)
            }
        } else {
            Text("Check Apple's catalog before downloading. The list is the installers Apple is serving right now, limited to versions this Mac can run.")
        }
        Button("Check Apple's catalog") { session.refreshLiveCatalog() }
            .disabled(session.isWorking)
            .accessibilityHint("Reads Apple's software catalog. Does not download the installer and does not erase a disk.")
    }

    private var hostSummary: String {
        guard let host = session.hostReport else {
            return "Installers are offered for this Mac, after its model is read."
        }
        if host.found {
            return "This Mac is \(host.records.map(\.name).joined(separator: " and "))."
        }
        return "This Mac's model is not available yet. No installer is offered until it is."
    }

    private func offerLabel(_ offer: InstallerOffer) -> String {
        if let build = offer.build, !build.isEmpty {
            return "\(offer.marketingName), version \(offer.version), build \(build)."
        }
        return "\(offer.marketingName), version \(offer.version)."
    }

    private var installerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Installer")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            TextField("Installer app or folder", text: $session.installerPath)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Installer app or folder")
                .accessibilityHint("A full installer ends in .app and contains createinstallmedia. A folder is searched for those apps. Example, /Applications.")
            Button("Check this installer") { session.checkChosenInstaller() }
                .accessibilityHint("Reads the app on disk. Does not install macOS.")
            if let installer = session.checkedInstaller {
                Text("Checked \(installer.displayName). Tool: \(installer.createInstallMediaPath).")
            }
            Button("Download and install this version") { session.downloadSelectedInstaller() }
                .disabled(session.isWorking || (session.didReadLiveCatalog && session.installerOffers.isEmpty))
                .accessibilityHint("Downloads Apple's InstallAssistant package, checks that pkgutil shows an Apple Software signature, then installs it into Applications. An administrator password is requested for that install. This does not erase a disk. If the download fails, softwareupdate is tried next.")
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Install on this Mac")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            Text("This opens Apple's installer. You finish the setup in Apple's window. macOS Manager does not erase the startup disk and does not run createinstallmedia for this choice.")
            if let startup = DiskSurveyParser.startupVolume(in: session.volumes) {
                Text("Startup disk: \(startup.volumeName), \(startup.deviceIdentifier), \(DiskSurveyParser.spokenCapacity(startup.sizeBytes)). Shown so you can hear which disk is running. It is not a USB target.")
            } else {
                Text("The startup disk name and size appear here after Look for disks. Until then, Install on this Mac still only opens Apple's window.")
            }
            Button("Install on this Mac") { session.openAppleInstaller() }
                .disabled(session.checkedInstaller == nil || session.isWorking)
                .accessibilityHint("Opens the checked Install macOS app. Does not write the startup disk by itself.")

            Text("Create a bootable USB installer")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            Text(InstallWarnings.usbDataLoss)
                .accessibilityAddTraits(.isHeader)
            Text("The USB step writes an installer with createinstallmedia. It does not install a running copy of macOS onto the USB.")
            Toggle("Show internal disks that are not the startup disk", isOn: $session.includeInternalNonStartup)
                .accessibilityHint("The startup disk stays unavailable for USB. Other internal disks stay hidden until this is on.")
            Button("Look for disks") { session.refreshDisks() }
                .disabled(session.isWorking)
                .accessibilityHint("Runs diskutil list. Does not erase anything.")
            if session.volumes.isEmpty {
                Text("No disk list yet. Look for disks reads names and sizes. The startup disk is never a USB choice.")
            } else {
                ForEach(session.volumes) { volume in
                    volumeRow(volume)
                }
            }
            if let volume = session.selectedVolume {
                Text(InstallWarnings.usbConfirmation(
                    volumeName: volume.volumeName,
                    capacity: DiskSurveyParser.spokenCapacity(volume.sizeBytes)
                ))
            }
            TextField("Type the volume name to confirm erase", text: $session.typedEraseName)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Type the USB volume name to confirm erase")
                .accessibilityHint(eraseHint)
            Button(usbButtonTitle) { session.createBootableUSB() }
                .disabled(session.checkedInstaller == nil || session.selectedVolume == nil || session.isWorking)
                .accessibilityHint(eraseHint + " macOS asks for an administrator password. The password is not stored.")
        }
    }

    private var usbButtonTitle: String {
        if let volume = session.selectedVolume {
            return "Create bootable USB installer on \(volume.volumeName), \(DiskSurveyParser.spokenCapacity(volume.sizeBytes))"
        }
        return "Create bootable USB installer"
    }

    private func volumeRow(_ volume: VolumeRecord) -> some View {
        let eligibility = DiskSurveyParser.eligibility(volume, includeInternalNonStartup: session.includeInternalNonStartup)
        return VStack(alignment: .leading, spacing: 4) {
            if eligibility == .eligible {
                Button(volumeButtonTitle(volume)) {
                    session.selectedDeviceID = volume.deviceIdentifier
                    session.announce("Chosen volume \(volume.volumeName). Type that name before creating the USB.")
                }
                .accessibilityLabel(volumeButtonTitle(volume))
                .accessibilityHint("Selects this volume. Nothing is erased until the name matches and you choose Create bootable USB.")
                if session.selectedDeviceID == volume.deviceIdentifier {
                    Text("Selected.")
                }
                if let caution = DiskSurveyParser.sizeCaution(volume) {
                    Text(caution)
                }
            } else {
                Text("\(volume.volumeName), \(volume.deviceIdentifier). \(eligibility.spoken)")
            }
        }
    }

    private func volumeButtonTitle(_ volume: VolumeRecord) -> String {
        let whereMounted = volume.mountPoint ?? "not mounted"
        return "\(volume.volumeName), \(DiskSurveyParser.spokenCapacity(volume.sizeBytes)), \(volume.deviceIdentifier), \(whereMounted)"
    }

    private var eraseHint: String {
        if let volume = session.selectedVolume {
            return InstallWarnings.usbConfirmation(
                volumeName: volume.volumeName,
                capacity: DiskSurveyParser.spokenCapacity(volume.sizeBytes)
            ) + " A different name does nothing."
        }
        return "Choose a USB first. \(InstallWarnings.usbDataLoss)"
    }
}
