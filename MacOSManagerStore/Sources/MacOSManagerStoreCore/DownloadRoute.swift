import Foundation

/// Official Apple page or App Store product the user can open. This edition never
/// launches softwareupdate, never fetches an installer, and never opens a CDN disk image.
public struct DownloadRoute: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case appStore
        case supportArticle
    }

    public var releaseID: String
    public var marketingName: String
    public var kind: Kind
    public var url: String
    public var buttonTitle: String
    public var accessibilityHint: String
    public var explanation: String

    public static func officialRoute(catalog: Catalog, release: OperatingSystemRelease) -> DownloadRoute {
        let download = release.download
        if download.kind == "appStore", let https = download.httpsURL, !https.isEmpty {
            return DownloadRoute(
                releaseID: release.id,
                marketingName: release.marketingName,
                kind: .appStore,
                url: https,
                buttonTitle: "Open Apple's official App Store page for \(release.marketingName)",
                accessibilityHint: "Opens Apple's Mac App Store product page so you can install, upgrade, or downgrade this version on this Mac. macOS Manager does not download the installer. Apple handles the download and any progress.",
                explanation: "Apple published a Mac App Store product page for this version. The button opens that official page so you can install it on this Mac. Apple handles the download and progress."
            )
        }
        if download.kind == "appStore", let mas = download.macAppStoreURL, !mas.isEmpty {
            return DownloadRoute(
                releaseID: release.id,
                marketingName: release.marketingName,
                kind: .appStore,
                url: mas,
                buttonTitle: "Open Apple's official App Store page for \(release.marketingName)",
                accessibilityHint: "Opens Apple's Mac App Store product so you can install, upgrade, or downgrade this version on this Mac. macOS Manager does not download the installer. Apple handles the download and any progress.",
                explanation: "Apple published a Mac App Store link for this version. The button opens that official link so you can install it on this Mac. Apple handles the download and progress."
            )
        }
        if release.id == "27" {
            return DownloadRoute(
                releaseID: release.id,
                marketingName: release.marketingName,
                kind: .supportArticle,
                url: catalog.rules.upgrade27URL,
                buttonTitle: "Open Apple's official macOS 27 upgrade article",
                accessibilityHint: "Opens Apple's support article about upgrading to macOS 27. macOS Manager does not run Software Update and does not download the installer.",
                explanation: "Apple's How to download macOS article does not list a standalone installer for macOS 27. The button opens Apple's official upgrade article so you can upgrade this Mac when Apple offers it. Apple handles the download and progress."
            )
        }
        if release.id == "26" {
            return DownloadRoute(
                releaseID: release.id,
                marketingName: release.marketingName,
                kind: .supportArticle,
                url: release.compatibilityPageURL ?? catalog.rules.softwareUpdateHelpURL,
                buttonTitle: "Open Apple's official page for \(release.marketingName)",
                accessibilityHint: "Opens Apple's official support page for this version. macOS Manager does not run Software Update and does not download the installer.",
                explanation: "Apple's How to download macOS article does not list a standalone installer for macOS Tahoe 26. The button opens Apple's official compatibility page. Use Software Update on this Mac when Apple offers it. Apple handles the download and progress."
            )
        }
        let article = download.articleURL.isEmpty ? catalog.rules.downloadArticleURL : download.articleURL
        return DownloadRoute(
            releaseID: release.id,
            marketingName: release.marketingName,
            kind: .supportArticle,
            url: article,
            buttonTitle: "Open Apple's official download article for \(release.marketingName)",
            accessibilityHint: "Opens Apple's How to download macOS support article. macOS Manager does not download a disk image and does not run Software Update.",
            explanation: "Apple documents this version on the official How to download macOS support article. This edition opens that article so you can install or downgrade on this Mac. It does not open a direct installer file. Apple handles any download from there."
        )
    }

    public static func officialRoute(catalog: Catalog, releaseID: String) -> DownloadRoute? {
        guard let release = catalog.releases.first(where: { $0.id == releaseID }) else {
            return nil
        }
        return officialRoute(catalog: catalog, release: release)
    }
}
