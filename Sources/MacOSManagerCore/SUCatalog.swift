import Foundation

public enum SUCatalogError: Error, Equatable, LocalizedError {
    case stillCompressed
    case notAPropertyList(String)
    case missingProducts

    public var errorDescription: String? {
        switch self {
        case .stillCompressed:
            return "Apple's catalog is still compressed. Uncompress it, then read the product list."
        case .notAPropertyList(let detail):
            return "Apple's catalog could not be read. \(detail)"
        case .missingProducts:
            return "Apple's catalog has no product list."
        }
    }
}

public struct CatalogInstallerPackage: Equatable, Sendable {
    public var productKey: String
    public var packageURL: URL
    public var expectedSize: Int64
    public var distributionURL: URL?
    public var sharedSupportIdentifier: String?
    public var version: String?
    public var build: String?
    public var title: String?

    public init(
        productKey: String,
        packageURL: URL,
        expectedSize: Int64,
        distributionURL: URL?,
        sharedSupportIdentifier: String?,
        version: String?,
        build: String?,
        title: String?
    ) {
        self.productKey = productKey
        self.packageURL = packageURL
        self.expectedSize = expectedSize
        self.distributionURL = distributionURL
        self.sharedSupportIdentifier = sharedSupportIdentifier
        self.version = version
        self.build = build
        self.title = title
    }
}

public enum AppleDownloadHosts {
    public static func isCatalogURL(_ url: URL) -> Bool {
        guard isHTTPS(url), host(url) == "swscan.apple.com" else { return false }
        return url.path.contains(".sucatalog")
    }

    public static func isDistributionURL(_ url: URL) -> Bool {
        guard isHTTPS(url), host(url) == "swdist.apple.com" else { return false }
        return url.path.hasSuffix(".dist")
    }

    public static func isInstallAssistantPackageURL(_ url: URL) -> Bool {
        guard isHTTPS(url), host(url) == "swcdn.apple.com" else { return false }
        return url.lastPathComponent == "InstallAssistant.pkg"
    }

    private static func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.user == nil
            && url.password == nil
            && (url.query ?? "").isEmpty
            && (url.fragment ?? "").isEmpty
    }

    private static func host(_ url: URL) -> String {
        (url.host ?? "").lowercased()
    }
}

public enum AppleCatalogList {
    /// Newest merged catalog first. Each address is Apple's public software-update catalog.
    public static let mergedCatalogURLs: [URL] = [
        "https://swscan.apple.com/content/catalogs/others/index-27-26-15-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog",
        "https://swscan.apple.com/content/catalogs/others/index-26-15-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog",
        "https://swscan.apple.com/content/catalogs/others/index-15-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog",
    ].compactMap(URL.init(string:))
}

public struct DistributionMetadata: Equatable, Sendable {
    public var title: String?
    public var version: String
    public var build: String?

    public init(title: String?, version: String, build: String?) {
        self.title = title
        self.version = version
        self.build = build
    }
}

public enum DistributionDocumentParser {
    /// Reads the version and build from an Apple English distribution document.
    /// The version inside `auxinfo` wins. A `VERSION` mention outside that block is ignored.
    public static func parse(_ xml: String) -> DistributionMetadata? {
        let aux = auxinfoBody(xml)
        let version = aux.flatMap { keyedString("VERSION", in: $0) } ?? versStr(in: xml)
        guard let version, InstallWorkflow.isOfficialVersionToken(version) else { return nil }
        let build = aux.flatMap { keyedString("BUILD", in: $0) }.flatMap { isBuildToken($0) ? $0 : nil }
        return DistributionMetadata(title: firstTitle(in: xml), version: version, build: build)
    }

    private static func auxinfoBody(_ xml: String) -> String? {
        guard let start = xml.range(of: "<auxinfo"),
              let tagEnd = xml.range(of: ">", range: start.lowerBound..<xml.endIndex),
              let close = xml.range(of: "</auxinfo>", range: tagEnd.upperBound..<xml.endIndex) else {
            return nil
        }
        return String(xml[tagEnd.upperBound..<close.lowerBound])
    }

    private static func keyedString(_ key: String, in xml: String) -> String? {
        let needle = "<key>\(key)</key>"
        guard let keyRange = xml.range(of: needle) else { return nil }
        let rest = xml[keyRange.upperBound...]
        guard let open = rest.range(of: "<string>"),
              let close = rest.range(of: "</string>", range: open.upperBound..<rest.endIndex) else {
            return nil
        }
        let value = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func versStr(in xml: String) -> String? {
        guard let marker = xml.range(of: "versStr=\"") else { return nil }
        let rest = xml[marker.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let value = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value)
    }

    private static func firstTitle(in xml: String) -> String? {
        guard let open = xml.range(of: "<title>"),
              let close = xml.range(of: "</title>", range: open.upperBound..<xml.endIndex) else {
            return nil
        }
        let value = xml[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 80, !value.contains("<") else { return nil }
        return value
    }

    private static func isBuildToken(_ value: String) -> Bool {
        (3...16).contains(value.count) && value.allSatisfy { $0.isLetter || $0.isNumber }
    }
}

public enum SUCatalogParser {
    public static func isProductKey(_ value: String) -> Bool {
        (4...32).contains(value.count) && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    /// Reads InstallAssistant packages from an uncompressed software-update catalog.
    /// Packages whose address is not Apple's download host are left out.
    public static func parse(_ data: Data) throws -> [CatalogInstallerPackage] {
        if data.count >= 2, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b {
            throw SUCatalogError.stillCompressed
        }
        let root: Any
        do {
            root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw SUCatalogError.notAPropertyList("The catalog was not a property list.")
        }
        guard let dict = root as? [String: Any] else {
            throw SUCatalogError.notAPropertyList("The catalog was not a dictionary.")
        }
        guard let products = dict["Products"] as? [String: Any] else {
            throw SUCatalogError.missingProducts
        }
        return products.keys.sorted().compactMap { key in
            guard isProductKey(key), let product = products[key] as? [String: Any] else { return nil }
            return makePackage(productKey: key, product: product)
        }
    }

    public static func releaseID(for version: String, catalog: Catalog) -> String? {
        let parts = version.split(separator: ".").map(String.init)
        guard let major = parts.first, major.allSatisfy(\.isNumber) else { return nil }
        let candidates: [String]
        if major == "10", parts.count >= 2 {
            candidates = ["10.\(parts[1])", "10"]
        } else {
            candidates = [major]
        }
        return candidates.first { id in catalog.releases.contains { $0.id == id } }
    }

    private static func makePackage(productKey: String, product: [String: Any]) -> CatalogInstallerPackage? {
        if let identifiers = installAssistantIdentifiers(product), !identifiers.looksLikeFullInstaller {
            return nil
        }
        guard let packages = product["Packages"] as? [[String: Any]] else { return nil }
        let assistants = packages.compactMap { entry -> (URL, Int64)? in
            guard let raw = entry["URL"] as? String, let url = URL(string: raw),
                  AppleDownloadHosts.isInstallAssistantPackageURL(url),
                  let size = int64(entry["Size"]), size > 0 else {
                return nil
            }
            return (url, size)
        }
        guard let chosen = assistants.max(by: { $0.1 < $1.1 }) else { return nil }
        return CatalogInstallerPackage(
            productKey: productKey,
            packageURL: chosen.0,
            expectedSize: chosen.1,
            distributionURL: distributionURL(product),
            sharedSupportIdentifier: installAssistantIdentifiers(product)?.sharedSupport,
            version: nil,
            build: nil,
            title: nil
        )
    }

    private static func installAssistantIdentifiers(_ product: [String: Any]) -> (sharedSupport: String?, looksLikeFullInstaller: Bool)? {
        guard let extended = product["ExtendedMetaInfo"] as? [String: Any],
              let identifiers = extended["InstallAssistantPackageIdentifiers"] as? [String: Any] else {
            return nil
        }
        let shared = identifiers["SharedSupport"] as? String
        let osInstall = identifiers["OSInstall"] as? String
        let looks = (shared?.contains("InstallAssistant") ?? false) || (osInstall?.contains("OSInstall") ?? false)
        return (shared, looks)
    }

    private static func distributionURL(_ product: [String: Any]) -> URL? {
        guard let distributions = product["Distributions"] as? [String: Any] else { return nil }
        let preferred = ["English", "en", "en_US"]
        var raw: String?
        for name in preferred {
            if let value = distributions[name] as? String {
                raw = value
                break
            }
        }
        if raw == nil {
            raw = distributions.values.compactMap { $0 as? String }.first { $0.hasSuffix(".English.dist") }
        }
        guard let raw, let url = URL(string: raw), AppleDownloadHosts.isDistributionURL(url) else { return nil }
        return url
    }

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let number as Int64:
            return number
        case let number as Int:
            return Int64(number)
        case let number as NSNumber:
            return number.int64Value
        case let text as String:
            return Int64(text)
        default:
            return nil
        }
    }
}
