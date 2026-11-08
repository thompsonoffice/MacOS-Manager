import AppKit
import MacOSManagerCore
import SwiftUI

enum AppScreen: String, CaseIterable, Identifiable, Hashable {
    case about
    case identify
    case compatibility
    case download
    case usb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .about: return "About"
        case .identify: return "Identify this Mac"
        case .compatibility: return "Compatible versions"
        case .download: return "Download from Apple"
        case .usb: return "Install"
        }
    }

    var hint: String {
        switch self {
        case .about:
            return "What this prototype does and does not do."
        case .identify:
            return "Read the model identifier, or type one."
        case .compatibility:
            return "macOS versions Apple lists for the Mac you looked up."
        case .download:
            return "Open Apple's own download pages. Nothing is downloaded inside this app."
        case .usb:
            return "Choose a listed macOS version, check an installer, then open Apple's installer or create a USB after naming the volume."
        }
    }
}

enum LookupKind: String, CaseIterable, Identifiable {
    case identifier = "Model identifier"
    case marketingName = "Model name"
    case partNumber = "Part number"

    var id: String { rawValue }

    var fieldLabel: String {
        switch self {
        case .identifier: return "Model identifier"
        case .marketingName: return "Apple model name"
        case .partNumber: return "Part number"
        }
    }

    var hint: String {
        switch self {
        case .identifier:
            return "Example, Mac18,1. In System Information, select Hardware. The model identifier is listed there."
        case .marketingName:
            return "Use Apple's full model name, such as MacBook Pro (14-inch, M6)."
        case .partNumber:
            return "Example, MHWT4LL/A, from the Mac or its box."
        }
    }
}

@MainActor
final class Session: ObservableObject, @unchecked Sendable {
    @Published var catalog: Catalog?
    @Published var loadError: String?
    @Published var screen: AppScreen = .about
    @Published var lookupKind: LookupKind = .identifier
    @Published var queryText = ""
    @Published var reading: MachineReading?
    @Published var report: CompatibilityReport?
    @Published var selectedReleaseID = "27"
    @Published var statusMessage = "macOS Manager is ready. Nothing is erased until a volume name matches."
    @Published var installerPath = "/Applications"
    @Published var checkedInstaller: CheckedInstaller?
    @Published var volumes: [VolumeRecord] = []
    @Published var includeInternalNonStartup = false
    @Published var selectedDeviceID: String?
    @Published var typedEraseName = ""
    @Published var progressLines: [String] = []
    @Published var isWorking = false
    private var activeCancel = WorkflowCancel()

    func load() {
        guard catalog == nil, loadError == nil else { return }
        do {
            catalog = try Catalog.loadBundled()
            statusMessage = "Apple facts catalog loaded. Retrieved \(catalog?.retrieved ?? "")."
        } catch {
            loadError = error.localizedDescription
            statusMessage = error.localizedDescription
            Announcer.say(statusMessage)
        }
    }

    func readThisMac() {
        let reading = SystemProbe.read()
        self.reading = reading
        if let identifier = reading.modelIdentifier, !identifier.isEmpty {
            lookupKind = .identifier
            queryText = identifier
            lookUp(announceBrief: true)
        } else {
            announce(reading.probeError ?? "This Mac did not return a model identifier. Type one to continue.")
        }
    }

    func lookUp(announceBrief: Bool = true) {
        guard let catalog else {
            announce(loadError ?? "The catalog is not loaded.")
            return
        }
        let query: ModelQuery
        switch lookupKind {
        case .identifier:
            query = .identifier(queryText)
        case .marketingName:
            query = .marketingName(queryText)
        case .partNumber:
            query = .partNumber(queryText)
        }
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let applicableReading: MachineReading?
        if lookupKind == .identifier,
           let probed = reading?.modelIdentifier,
           probed.caseInsensitiveCompare(trimmed) == .orderedSame {
            applicableReading = reading
        } else {
            applicableReading = nil
        }
        let report = CompatibilityReport.build(catalog: catalog, query: query, reading: applicableReading)
        self.report = report
        selectedReleaseID = InstallWorkflow.preferredReleaseID(selectedReleaseID, in: report)
        if announceBrief {
            announce(report.briefAnnouncement)
        }
    }

    func openAppleURL(_ string: String) {
        guard let url = URL(string: string) else {
            announce("That address could not be opened.")
            return
        }
        if NSWorkspace.shared.open(url) {
            announce("Asked macOS to open the Apple page. This app did not download an installer.")
        } else {
            announce("macOS did not open the address. It is still shown on screen.")
        }
    }

    func checkChosenInstaller() {
        let url = URL(fileURLWithPath: installerPath.trimmingCharacters(in: .whitespacesAndNewlines))
        let target = url.pathExtension == "app" ? url : url.appendingPathComponent(url.lastPathComponent)
        let results = url.pathExtension == "app"
            ? [InstallWorkflow.checkInstaller(at: url)]
            : InstallWorkflow.findInstallers(in: url)
        if let first = results.compactMap({ try? $0.get() }).first {
            checkedInstaller = first
            announce("Full installer found. \(first.displayName). createinstallmedia is inside the app.")
        } else if let failure = results.first, case .failure(let error) = failure {
            checkedInstaller = nil
            announce(error.localizedDescription)
        } else {
            checkedInstaller = nil
            announce("No installer app was found in \(target.path).")
        }
    }

    func downloadSelectedInstaller() {
        guard let catalog, let report, let assessment = report.versions.first(where: { $0.releaseID == selectedReleaseID }) else {
            announce("Look up a Mac and choose a version first.")
            return
        }
        switch InstallWorkflow.fetchFullInstaller(assessment: assessment, catalog: catalog) {
        case .failure(let error):
            announce(error.localizedDescription)
        case .success(let command):
            let build = assessment.latestBuild
            start("Asking Apple's softwareupdate for \(build). This does not erase a disk.") { cancel in
                _ = try InstallWorkflow.execute(command, runner: ProcessCommandRunner(allowAdministratorCommands: false), cancel: cancel) { line in
                    Task { @MainActor in self.note(line) }
                }
                return "softwareupdate finished for \(build). Check the installer, then choose open or USB. This did not erase a disk."
            }
        }
    }

    func refreshDisks() {
        let includeInternal = includeInternalNonStartup
        start("Reading disks with diskutil. The startup disk stays hidden.") { cancel in
            let outcome = try InstallWorkflow.execute(
                InstallWorkflow.diskutilList(),
                runner: ProcessCommandRunner(allowAdministratorCommands: false),
                cancel: cancel
            ) { _ in }
            let records = try DiskSurveyParser.parse(Data(outcome.standardOutput.utf8))
            let eligible = records.filter {
                DiskSurveyParser.eligibility($0, includeInternalNonStartup: includeInternal) == .eligible
            }.count
            await MainActor.run { self.volumes = records }
            return "\(records.count) named volumes were listed. \(eligible) can be chosen with the current setting."
        }
    }

    func openAppleInstaller() {
        guard let installer = checkedInstaller else {
            announce("Check a full installer first.")
            return
        }
        let command = InstallWorkflow.prepareOpen(installer)
        let name = installer.displayName
        start("Opening \(name). Apple's own window will ask before it installs. This app does not erase the running Mac.") { cancel in
            _ = try InstallWorkflow.execute(command, runner: ProcessCommandRunner(allowAdministratorCommands: false), cancel: cancel) { _ in }
            return "Asked macOS to open \(name). Use Apple's window. This app did not erase a disk."
        }
    }

    func createBootableUSB() {
        guard let installer = checkedInstaller, let volume = selectedVolume else {
            announce("Choose an installer and an external volume first.")
            return
        }
        let typed = typedEraseName
        let include = includeInternalNonStartup
        let current = volumes
        let name = volume.volumeName
        start("If the typed name matches \(name), macOS will ask for an administrator password. The password is not stored.") { cancel in
            _ = try InstallWorkflow.executeUSB(
                installer: installer,
                volume: volume,
                typedName: typed,
                includeInternalNonStartup: include,
                currentVolumes: current,
                runner: ProcessCommandRunner(),
                cancel: cancel
            ) { line in
                Task { @MainActor in self.note(line) }
            }
            return "createinstallmedia finished for \(name). This workspace has not verified that step on a real disk."
        }
    }

    func cancelWork() {
        activeCancel.cancel()
        announce("Cancel requested.")
    }

    var selectedVolume: VolumeRecord? {
        volumes.first { $0.deviceIdentifier == selectedDeviceID }
    }

    private func start(_ message: String, work: @escaping (WorkflowCancel) async throws -> String) {
        let cancel = WorkflowCancel()
        activeCancel = cancel
        isWorking = true
        progressLines = [message]
        announce(message)
        Task.detached {
            do {
                let result = try await work(cancel)
                await MainActor.run {
                    self.isWorking = false
                    self.announce(cancel.isCancelled() ? WorkflowError.cancelled.localizedDescription : result)
                }
            } catch {
                await MainActor.run {
                    self.isWorking = false
                    self.announce((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            }
        }
    }

    private func note(_ line: String) {
        guard !line.isEmpty else { return }
        progressLines.append(line)
    }

    func announce(_ message: String) {
        statusMessage = message
        Announcer.say(message)
    }
}
