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
            return "Open Apple's own download pages. The installer download is on the Install screen."
        case .usb:
            return "Choose a macOS version Apple's live catalog offers for this Mac, download it, then open Apple's installer or create a USB after naming the volume."
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
    @Published var statusDetail: String?
    @Published var hostReport: CompatibilityReport?
    @Published var installerOffers: [InstallerOffer] = []
    @Published var installerRefusals: [InstallerRefusal] = []
    @Published var didReadLiveCatalog = false
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

    func prepareHost() {
        guard let catalog else { return }
        let reading = SystemProbe.read()
        hostReport = InstallerOffers.hostReport(catalog: catalog, reading: reading)
    }

    func refreshLiveCatalog() {
        guard let catalog else {
            announce(loadError ?? "The catalog is not loaded.")
            return
        }
        let requested = selectedReleaseID
        start("Reading Apple's catalog for installers this Mac can run. This does not erase a disk.") { cancel in
            let packages = try await AppleCatalogClient.loadInstallerPackages(isCancelled: cancel.isCancelled) { line in
                Task { @MainActor in self.note(line) }
            }
            let offerSet = await self.publishOffers(catalog: catalog, packages: packages, requestedReleaseID: requested)
            if offerSet.offers.isEmpty {
                return offerSet.refusals.first?.plainLanguage ?? "Apple's catalog did not include an installer this Mac can run."
            }
            let names = offerSet.offers.map { "\($0.marketingName) \($0.version)" }.joined(separator: ", ")
            let hidden = offerSet.refusals.isEmpty ? "" : " \(offerSet.refusals.count) other versions are explained on screen."
            return "Apple's catalog offers \(names) for this Mac.\(hidden)"
        }
    }

    func downloadSelectedInstaller() {
        guard let catalog else {
            announce(loadError ?? "The catalog is not loaded.")
            return
        }
        let requested = selectedReleaseID
        start("Checking Apple's catalog for an installer this Mac can run. This does not erase a disk.") { cancel in
            try await self.downloadRelease(catalog: catalog, requestedReleaseID: requested, cancel: cancel)
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
                    let spoken = InstallErrorMapping.present(error)
                    let detail = spoken.rawDetail.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.announce(spoken.plainLanguage, detail: detail.isEmpty ? nil : detail)
                }
            }
        }
    }

    private func note(_ line: String) {
        guard !line.isEmpty else { return }
        progressLines.append(line)
    }

    func announce(_ message: String, detail: String? = nil) {
        statusMessage = message
        let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        statusDetail = (trimmed?.isEmpty == false) ? trimmed : nil
        Announcer.say(message)
    }

    private func publishOffers(
        catalog: Catalog,
        packages: [CatalogInstallerPackage],
        requestedReleaseID: String
    ) async -> InstallerOfferSet {
        let reading = SystemProbe.read()
        let host = InstallerOffers.hostReport(catalog: catalog, reading: reading)
        let offerSet = InstallerOffers.make(catalog: catalog, hostReport: host, packages: packages)
        await MainActor.run {
            self.hostReport = host
            self.installerOffers = offerSet.offers
            self.installerRefusals = offerSet.refusals
            self.didReadLiveCatalog = true
            if !offerSet.offers.contains(where: { $0.releaseID == requestedReleaseID }),
               let first = offerSet.offers.first {
                self.selectedReleaseID = first.releaseID
            }
        }
        return offerSet
    }

    private func downloadRelease(
        catalog: Catalog,
        requestedReleaseID: String,
        cancel: WorkflowCancel
    ) async throws -> String {
        let packages: [CatalogInstallerPackage]
        do {
            packages = try await AppleCatalogClient.loadInstallerPackages(isCancelled: cancel.isCancelled) { line in
                Task { @MainActor in self.note(line) }
            }
        } catch {
            let spoken = InstallErrorMapping.present(error)
            let reading = SystemProbe.read()
            let host = InstallerOffers.hostReport(catalog: catalog, reading: reading)
            await MainActor.run { self.hostReport = host }
            if spoken.allowsSoftwareUpdateFallback,
               let version = InstallerOffers.bundledVersionIfInstallable(catalog: catalog, hostReport: host, releaseID: requestedReleaseID) {
                await MainActor.run {
                    self.announce(
                        "Apple's live catalog could not be read. Asking softwareupdate for \(version), the build recorded for this Mac.",
                        detail: spoken.rawDetail
                    )
                }
                return try runSoftwareUpdate(version: version, cancel: cancel)
            }
            throw spoken
        }
        let offerSet = await publishOffers(catalog: catalog, packages: packages, requestedReleaseID: requestedReleaseID)
        guard let offer = offerSet.offers.first(where: { $0.releaseID == requestedReleaseID }) else {
            let refusal = offerSet.refusals.first { $0.id == requestedReleaseID } ?? offerSet.refusals.first
            throw SpokenInstallError(
                plainLanguage: refusal?.plainLanguage ?? "That version is not offered for this Mac. Nothing was downloaded.",
                rawDetail: "",
                allowsSoftwareUpdateFallback: false,
                allowsDirectPackageFallback: false
            )
        }
        return try await install(offer, cancel: cancel)
    }

    private func install(_ offer: InstallerOffer, cancel: WorkflowCancel) async throws -> String {
        let attempts = InstallerAttemptOrder.preferred(package: offer.package)
        var directFailure: SpokenInstallError?
        for (index, attempt) in attempts.enumerated() {
            if cancel.isCancelled() { throw WorkflowError.cancelled }
            do {
                switch attempt {
                case .direct(let package):
                    await MainActor.run {
                        self.note("Downloading \(offer.marketingName) \(offer.version), product \(offer.productKey), from Apple.")
                    }
                    return try await runDirect(package, offer: offer, cancel: cancel)
                case .softwareUpdate(let version):
                    await MainActor.run {
                        self.note("Asking softwareupdate for \(version).")
                    }
                    return try runSoftwareUpdate(version: version, cancel: cancel)
                }
            } catch {
                let remaining = Array(attempts.suffix(from: index + 1))
                let spoken = failure(error, attempt: attempt, remaining: remaining)
                if case .direct = attempt { directFailure = spoken }
                if index + 1 < attempts.count, InstallerAttemptOrder.mayContinue(after: spoken, to: attempts[index + 1]) {
                    await MainActor.run {
                        self.announce(spoken.plainLanguage, detail: spoken.rawDetail.isEmpty ? nil : spoken.rawDetail)
                    }
                    continue
                }
                if let directFailure, case .softwareUpdate = attempt {
                    throw SpokenInstallError(
                        plainLanguage: "The installer was not installed. The catalog download did not finish, and softwareupdate did not finish either. \(spoken.plainLanguage)",
                        rawDetail: "Catalog download:\n\(directFailure.rawDetail)\n\nsoftwareupdate:\n\(spoken.rawDetail)",
                        allowsSoftwareUpdateFallback: false,
                        allowsDirectPackageFallback: false
                    )
                }
                throw spoken
            }
        }
        throw SpokenInstallError(
            plainLanguage: "The installer was not installed.",
            rawDetail: "",
            allowsSoftwareUpdateFallback: false,
            allowsDirectPackageFallback: false
        )
    }

    private func failure(_ error: Error, attempt: InstallerAttempt, remaining: [InstallerAttempt]) -> SpokenInstallError {
        if let spoken = error as? SpokenInstallError { return spoken }
        if case .softwareUpdate = attempt,
           let workflow = error as? WorkflowError,
           case .commandFailed(let code, let message) = workflow {
            let willDirect = remaining.contains {
                if case .direct = $0 { return true }
                return false
            }
            return InstallErrorMapping.softwareUpdate(exitCode: code, message: message, willTryDirectDownload: willDirect)
        }
        return InstallErrorMapping.present(error)
    }

    private func runSoftwareUpdate(version: String, cancel: WorkflowCancel) throws -> String {
        let command = try InstallWorkflow.softwareUpdateCommand(version: version).get()
        _ = try InstallWorkflow.execute(
            command,
            runner: ProcessCommandRunner(allowAdministratorCommands: false),
            cancel: cancel
        ) { line in
            Task { @MainActor in self.note(line) }
        }
        return "softwareupdate finished for \(version). Check Applications for the installer app. This did not erase a disk."
    }

    private func runDirect(
        _ package: CatalogInstallerPackage,
        offer: InstallerOffer,
        cancel: WorkflowCancel
    ) async throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacOSManager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("InstallAssistant.pkg")
        var keepPackage = false
        defer {
            if !keepPackage {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        try await AppleHTTPS.download(
            package.packageURL,
            to: destination,
            expectedSize: package.expectedSize,
            isCancelled: cancel.isCancelled
        ) { line in
            Task { @MainActor in self.note(line) }
        }
        let actual = (try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? -1
        if let sizeError = PackageSizeCheck.evaluate(expected: package.expectedSize, actual: actual) {
            throw sizeError
        }
        let verdict = try signatureVerdict(at: destination, cancel: cancel)
        await MainActor.run { self.note(verdict.spoken.plainLanguage) }
        guard verdict.accepted else { throw verdict.spoken }
        await MainActor.run {
            self.note("macOS will ask for an administrator password to install the package into Applications. The password is not stored. This does not erase a disk.")
        }
        let command = try InstallerCommands.install(packagePath: destination.path).get()
        do {
            _ = try InstallWorkflow.execute(
                command,
                runner: ProcessCommandRunner(allowAdministratorCommands: true),
                cancel: cancel
            ) { line in
                Task { @MainActor in self.note(line) }
            }
        } catch {
            keepPackage = true
            let spoken = InstallErrorMapping.present(error)
            throw SpokenInstallError(
                plainLanguage: "The package was checked, but it was not installed into Applications. \(spoken.plainLanguage)",
                rawDetail: "Package kept at \(destination.path).\n\(spoken.rawDetail)",
                allowsSoftwareUpdateFallback: false,
                allowsDirectPackageFallback: false
            )
        }
        let names = InstallWorkflow.findInstallers(in: URL(fileURLWithPath: "/Applications")).compactMap { try? $0.get() }.map(\.displayName)
        if names.isEmpty {
            return "The package installer finished for \(offer.marketingName) \(offer.version). No Install macOS app was found in Applications yet. This did not erase a disk."
        }
        return "Installed \(names.joined(separator: ", ")) into Applications. Check the installer, then choose open or USB. This did not erase a disk."
    }

    private func signatureVerdict(at destination: URL, cancel: WorkflowCancel) throws -> SignatureVerdict {
        let command = try InstallerCommands.checkSignature(packagePath: destination.path).get()
        let runner = ProcessCommandRunner(allowAdministratorCommands: false)
        do {
            let outcome = try InstallWorkflow.execute(command, runner: runner, cancel: cancel) { line in
                Task { @MainActor in self.note(line) }
            }
            return PackageSignatureCheck.evaluate(
                exitCode: outcome.exitCode,
                output: outcome.standardOutput + "\n" + outcome.standardError
            )
        } catch let error as WorkflowError {
            if case .commandFailed(let code, let message) = error {
                return PackageSignatureCheck.evaluate(exitCode: code, output: message)
            }
            throw error
        }
    }
}
