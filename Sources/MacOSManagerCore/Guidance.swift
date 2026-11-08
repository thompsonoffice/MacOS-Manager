import Foundation

public struct DownloadGuidance: Equatable, Sendable {
    public var releaseID: String
    public var marketingName: String
    public var primaryURL: String
    public var primaryLinkTitle: String
    public var macAppStoreURL: String?
    public var httpsURL: String?
    public var diskImageURL: String?
    public var softwareUpdateHelpURL: String
    public var settingsURLFromAppleHelp: String
    public var settingsLinkVerifiedFromThisApp: Bool
    public var runsSoftwareUpdateCommand: Bool
    public var bundlesInstaller: Bool
    public var steps: [String]
    public var note: String

    public static func make(catalog: Catalog, releaseID: String) -> DownloadGuidance? {
        guard let release = catalog.releases.first(where: { $0.id == releaseID }) else {
            return nil
        }
        let download = release.download
        let primaryURL: String
        let primaryTitle: String
        switch download.kind {
        case "appStore":
            primaryURL = download.macAppStoreURL ?? download.httpsURL ?? download.articleURL
            primaryTitle = "Open Apple's App Store link for \(release.marketingName)"
        case "diskImage":
            primaryURL = download.diskImageURL ?? download.articleURL
            primaryTitle = "Open Apple's disk image link for \(release.marketingName)"
        default:
            if release.id == "27" {
                primaryURL = catalog.rules.upgrade27URL
                primaryTitle = "Open Apple's macOS 27 upgrade article"
            } else {
                primaryURL = catalog.rules.softwareUpdateHelpURL
                primaryTitle = "Open Apple's Software Update instructions"
            }
        }
        return DownloadGuidance(
            releaseID: release.id,
            marketingName: release.marketingName,
            primaryURL: primaryURL,
            primaryLinkTitle: primaryTitle,
            macAppStoreURL: download.macAppStoreURL,
            httpsURL: download.httpsURL,
            diskImageURL: download.diskImageURL,
            softwareUpdateHelpURL: catalog.rules.softwareUpdateHelpURL,
            settingsURLFromAppleHelp: catalog.rules.softwareUpdateSettingsURL,
            settingsLinkVerifiedFromThisApp: false,
            runsSoftwareUpdateCommand: false,
            bundlesInstaller: false,
            steps: [
                "Use Spotlight to search for Software Update, or choose Apple menu, System Settings, General, then Software Update. Apple's macOS 27 article and Mac user guide both describe those steps.",
                "Software Update shows only updates that are compatible with that Mac. A version listed as hardware-compatible in this catalog can still be absent from Software Update.",
                "If Apple published an App Store or disk image link for this version, it is shown separately. This app does not download the installer.",
            ],
            note: download.note
        )
    }
}

public struct BootableInstallerStatus: Equatable, Sendable {
    public var implemented: Bool
    public var erasesDrives: Bool
    public var requestsRoot: Bool
    public var runsCreateInstallMedia: Bool
    public var articleURL: String
    public var articlePublished: String
    public var guidelineURL: String
    public var guidelineUpdated: String
    public var explanation: [String]
    public var startupSteps: [String]

    public static func notInThisBuild(catalog: Catalog, processor: ProcessorClass) -> BootableInstallerStatus {
        BootableInstallerStatus(
            implemented: false,
            erasesDrives: false,
            requestsRoot: false,
            runsCreateInstallMedia: false,
            articleURL: catalog.rules.bootableInstallerArticleURL,
            articlePublished: catalog.rules.bootableInstallerArticlePublished,
            guidelineURL: catalog.rules.appStoreGuidelinesURL,
            guidelineUpdated: catalog.rules.appStoreGuidelinesUpdated,
            explanation: [
                "The Install screen can ask Apple's softwareupdate for a catalog build, open a checked Install macOS app, or run createinstallmedia after the typed volume name matches. Startup disks stay blocked.",
                "That command path has not been run against Apple's real createinstallmedia or a physical disk. macOS shows the administrator password prompt itself. This app does not store the password.",
                "The intended download is a direct .app, not a Mac App Store build. Guideline 2.4.5(v), updated \(catalog.rules.appStoreGuidelinesUpdated), still forbids root in a store app, which is why the USB step is only in the direct build.",
                "Apple's article, published \(catalog.rules.bootableInstallerArticlePublished), says the volume is erased when you type Y. This app types that only after the volume name matches.",
            ],
            startupSteps: startupSteps(processor: processor, rules: catalog.rules)
        )
    }

    private static func startupSteps(processor: ProcessorClass, rules: CatalogRules) -> [String] {
        let source = "From Apple's article \(rules.bootableInstallerArticleURL), published \(rules.bootableInstallerArticlePublished)."
        let silicon = "On a Mac with Apple silicon, press and hold the power button. Keep holding while startup options load. Bootable volumes are shown there. \(source)"
        let intel = "On an Intel Mac, turn the Mac on and immediately press and hold the Option key. Release Option when the bootable volumes appear. \(source)"
        let t2 = "If the Mac has an Apple T2 Security Chip and will not start from external media, Apple says to allow that in Startup Security Utility. \(source)"
        switch processor.kind {
        case .appleSilicon:
            return [silicon]
        case .intel:
            return [intel, t2]
        case .unknown:
            return [
                "The processor class is unknown, so both of Apple's startup paths are shown. Use the one that matches this Mac.",
                silicon,
                intel,
                t2,
            ]
        }
    }
}
