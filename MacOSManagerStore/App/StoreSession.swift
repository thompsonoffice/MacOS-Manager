import AppKit
import Foundation
import MacOSManagerStoreCore
import SwiftUI

enum StoreScreen: Equatable {
    case home
    case readiness
    case checklist
}

@MainActor
final class StoreSession: ObservableObject {
    @Published var catalog: Catalog?
    @Published var reading: MachineReading?
    @Published var installed: InstalledVersion?
    @Published var report: CompatibilityReport?
    @Published var statusMessage = "Starting. The catalog and this Mac have not been read yet."
    @Published var loadError: String?
    @Published var queryText = ""
    @Published var isWorking = false
    @Published var lastOpenResult: String?
    @Published var screen: StoreScreen = .home
    @Published var selectedReleaseID: String?
    @Published var freeSpace: FreeSpaceMeasurement = .unreadable
    @Published var memoryBytes: UInt64?
    @Published var powerSources: [PowerSourceSnapshot]?

    func start() {
        guard catalog == nil, !isWorking else { return }
        isWorking = true
        statusMessage = "Reading the bundled compatibility table, this Mac's model identifier, free space, memory, and power. The window stays usable while that happens."
        Task { await loadAndIdentify() }
    }

    func lookUpTypedIdentifier() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let catalog else {
            statusMessage = "The compatibility table has not loaded yet."
            return
        }
        isWorking = true
        screen = .home
        statusMessage = "Looking up \(trimmed) in the bundled table."
        Task {
            await applyLookup(catalog: catalog, query: .identifier(trimmed), reading: reading)
        }
    }

    func showReadiness(releaseID: String) {
        selectedReleaseID = releaseID
        screen = .readiness
        if let readiness = readinessReport() {
            statusMessage = readiness.spokenSummary
            Announcer.say(readiness.spokenSummary)
        } else {
            statusMessage = "That version is not in the compatibility result yet."
            Announcer.say(statusMessage)
        }
    }

    func showChecklist() {
        screen = .checklist
        let message = "Checklist before you install. Back up with Time Machine, stay plugged in, use a stable internet connection, and expect restarts. VoiceOver may be unavailable for a short time at a restart. Press Command-F5 to turn VoiceOver on or off."
        statusMessage = message
        Announcer.say(message)
    }

    func showHome() {
        screen = .home
        Announcer.say("Back to compatible macOS versions.")
    }

    func showReadinessAgain() {
        guard let selectedReleaseID else {
            showHome()
            return
        }
        showReadiness(releaseID: selectedReleaseID)
    }

    func readinessReport() -> ReadinessReport? {
        guard let selectedReleaseID, let compatibility = report else { return nil }
        guard let version = compatibility.versions.first(where: { $0.releaseID == selectedReleaseID }) else {
            return nil
        }
        return ReadinessEvaluator.evaluate(
            releaseID: version.releaseID,
            marketingName: version.marketingName,
            claim: version.claim,
            nearMissNames: version.nearMissNames,
            installed: installed,
            freeSpace: freeSpace,
            memoryBytes: memoryBytes,
            powerSources: powerSources
        )
    }

    func openSupportURL(_ raw: String, title: String) {
        openAddress(raw, title: title, success: "Opened \(title). This is Apple's official page. It is not a download started by macOS Manager.")
    }

    func openOfficialRoute(_ route: DownloadRoute) {
        openAddress(
            route.url,
            title: route.buttonTitle,
            success: "Opened \(route.buttonTitle). Use that official Apple page to install, upgrade, or downgrade on this Mac. Apple handles the download and progress."
        )
    }

    func openChecklistLink(_ action: ChecklistAction) {
        let success: String
        if action.url == ChecklistLinks.timeMachineSettings {
            success = "Opened Time Machine in System Settings. This app does not create the backup."
        } else {
            success = "Opened \(action.title). This is Apple's own guide. macOS Manager does not change this Mac's settings."
        }
        let failure = "macOS did not open \(action.title). You can choose Apple menu, System Settings, yourself. Nothing was changed."
        openAddress(action.url, title: action.title, success: success, failure: failure)
    }

    private func openAddress(_ raw: String, title: String, success: String, failure: String? = nil) {
        guard let url = URL(string: raw) else {
            lastOpenResult = "That address could not be turned into a link."
            statusMessage = lastOpenResult ?? statusMessage
            Announcer.say(statusMessage)
            return
        }
        let opened = NSWorkspace.shared.open(url)
        if opened {
            lastOpenResult = success
        } else {
            lastOpenResult = failure ?? "macOS did not open \(raw). You can copy that address into Safari."
        }
        statusMessage = lastOpenResult ?? statusMessage
        Announcer.say(statusMessage)
    }

    private func loadAndIdentify() async {
        let loaded = await Task.detached(priority: .userInitiated) { () -> Result<Catalog, Error> in
            Result { try Catalog.loadBundled() }
        }.value
        switch loaded {
        case .failure(let error):
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = "The compatibility table did not load. \(loadError ?? "")"
            isWorking = false
            Announcer.say(statusMessage)
        case .success(let catalog):
            self.catalog = catalog
            let facts = await Task.detached(priority: .userInitiated) {
                SystemProbe.read()
            }.value
            self.reading = facts.reading
            self.installed = facts.installed
            self.freeSpace = facts.freeSpace
            self.memoryBytes = facts.memoryBytes
            self.powerSources = facts.powerSources
            if let identifier = facts.reading.modelIdentifier, !identifier.isEmpty {
                queryText = identifier
                await applyLookup(catalog: catalog, query: .identifier(identifier), reading: facts.reading)
            } else {
                statusMessage = "The compatibility table loaded. This Mac's model identifier was not read. Type the identifier from System Information and choose Look up."
                isWorking = false
                Announcer.say(statusMessage)
            }
        }
    }

    private func applyLookup(catalog: Catalog, query: ModelQuery, reading: MachineReading?) async {
        let report = await Task.detached(priority: .userInitiated) {
            CompatibilityReport.build(catalog: catalog, query: query, reading: reading)
        }.value
        self.report = report
        screen = .home
        if report.found {
            let names = report.records.map(\.name).joined(separator: ", ")
            let count = report.compatibleVersions.count
            statusMessage = "This Mac matches \(names). \(count) compatible macOS \(count == 1 ? "version is" : "versions are") listed from Apple's published pages. \(installed?.spoken ?? "") Choose Can my Mac run this under a version to check free space, memory, power, and whether that choice is an upgrade, the same version, or a downgrade."
        } else {
            statusMessage = report.spokenSummary
        }
        isWorking = false
        Announcer.say(report.briefAnnouncement + " " + statusMessage)
    }
}
