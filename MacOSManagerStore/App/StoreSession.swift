import AppKit
import Foundation
import MacOSManagerStoreCore
import SwiftUI

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

    func start() {
        guard catalog == nil, !isWorking else { return }
        isWorking = true
        statusMessage = "Reading the bundled compatibility table and this Mac's model identifier. The window stays usable while that happens."
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
        statusMessage = "Looking up \(trimmed) in the bundled table."
        Task {
            await applyLookup(catalog: catalog, query: .identifier(trimmed), reading: reading)
        }
    }

    func openSupportURL(_ raw: String, title: String) {
        guard let url = URL(string: raw) else {
            lastOpenResult = "That official Apple address could not be turned into a link."
            statusMessage = lastOpenResult ?? statusMessage
            Announcer.say(statusMessage)
            return
        }
        let opened = NSWorkspace.shared.open(url)
        if opened {
            lastOpenResult = "Opened \(title). This is Apple's official page. It is not a download started by macOS Manager."
        } else {
            lastOpenResult = "macOS did not open \(raw). You can copy that address into Safari."
        }
        statusMessage = lastOpenResult ?? statusMessage
        Announcer.say(statusMessage)
    }

    func openOfficialRoute(_ route: DownloadRoute) {
        guard let url = URL(string: route.url) else {
            lastOpenResult = "That official Apple address could not be turned into a link."
            statusMessage = lastOpenResult ?? statusMessage
            Announcer.say(statusMessage)
            return
        }
        let opened = NSWorkspace.shared.open(url)
        if opened {
            lastOpenResult = "Opened \(route.buttonTitle). Use that official Apple page to install, upgrade, or downgrade on this Mac. Apple handles the download and progress."
        } else {
            lastOpenResult = "macOS did not open \(route.url). You can copy that address into Safari."
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
            let probe = await Task.detached(priority: .userInitiated) {
                SystemProbe.read()
            }.value
            self.reading = probe.reading
            self.installed = probe.installed
            if let identifier = probe.reading.modelIdentifier, !identifier.isEmpty {
                queryText = identifier
                await applyLookup(catalog: catalog, query: .identifier(identifier), reading: probe.reading)
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
        if report.found {
            let names = report.records.map(\.name).joined(separator: ", ")
            let count = report.compatibleVersions.count
            statusMessage = "This Mac matches \(names). \(count) compatible macOS \(count == 1 ? "version is" : "versions are") listed from Apple's published pages. \(installed?.spoken ?? "")"
        } else {
            statusMessage = report.spokenSummary
        }
        isWorking = false
        Announcer.say(report.briefAnnouncement + " " + statusMessage)
    }
}
