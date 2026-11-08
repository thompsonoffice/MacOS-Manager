import Foundation

public enum CatalogError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case missingResource
    case invalidJSON(String)

    public var description: String {
        switch self {
        case .missingResource:
            return "The Apple facts catalog is missing from the app resources."
        case .invalidJSON(let detail):
            return "The Apple facts catalog could not be read. \(detail)"
        }
    }

    /// The app reads `localizedDescription`. Without this, Swift speaks a generic
    /// "operation could not be completed" message instead of the sentences above.
    public var errorDescription: String? { description }
}

public struct Catalog: Equatable, Sendable {
    public var retrieved: String
    public var statement: String
    public var models: [ModelRecord]
    public var releases: [OperatingSystemRelease]
    public var rules: CatalogRules

    public static func loadBundled() throws -> Catalog {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CatalogError.invalidJSON("The catalog file could not be opened.")
        }
        return try load(data)
    }

    public static func load(_ data: Data) throws -> Catalog {
        let decoder = JSONDecoder()
        do {
            let file = try decoder.decode(CatalogFile.self, from: data)
            return Catalog(
                retrieved: file.retrieved,
                statement: file.statement,
                models: file.models,
                releases: file.releases,
                rules: file.rules
            )
        } catch {
            throw CatalogError.invalidJSON(String(describing: error))
        }
    }

    public var compatibilityReleases: [OperatingSystemRelease] {
        releases
            .filter(\.hasPerModelCompatibilityPage)
            .sorted { lhs, rhs in
                (Double(lhs.id) ?? 0) > (Double(rhs.id) ?? 0)
            }
    }

    public func records(for query: ModelQuery) -> [ModelRecord] {
        let trimmed = query.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        switch query {
        case .identifier:
            return models.filter { record in
                record.identifiers.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
            }
        case .marketingName:
            return models.filter { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        case .partNumber:
            return models.filter { record in
                record.partNumbers.contains { PartNumberMatch.matches(catalogPart: $0, user: trimmed) }
            }
        }
    }
}

public struct ModelRecord: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var family: String
    public var identifiers: [String]
    public var description: String?
    public var yearIntroduced: Int?
    public var yearSource: String?
    public var partNumbers: [String]
    public var newestOperatingSystemText: String?
    public var newestOperatingSystemFootnote: String?
    public var sourceURL: String
    public var sourceKind: String
    public var note: String?
    public var chipLabel: String?

    public var id: String {
        name + "|" + identifiers.joined(separator: ",")
    }
}

public struct OperatingSystemRelease: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var marketingName: String
    public var latestBuild: String
    public var latestBuildSourceURL: String
    public var latestBuildSourcePublished: String
    public var compatibilityPageURL: String?
    public var compatibilityPagePublished: String?
    public var listedModelNames: [String]
    public var appleSiliconBlanket: AppleSiliconBlanket?
    public var hasPerModelCompatibilityPage: Bool
    public var download: PublicDownload
}

public struct AppleSiliconBlanket: Codable, Equatable, Sendable {
    public var statement: String
    public var url: String
    public var published: String
    public var alsoStatedOn: String
}

public struct PublicDownload: Codable, Equatable, Sendable {
    public var kind: String
    public var articleURL: String
    public var articlePublished: String
    public var macAppStoreURL: String?
    public var httpsURL: String?
    public var diskImageURL: String?
    public var note: String
}

public struct CatalogRules: Codable, Equatable, Sendable {
    public var appleSiliconArticleURL: String
    public var appleSiliconArticlePublished: String
    public var t2ArticleURL: String
    public var t2ArticlePublished: String
    public var bootableInstallerArticleURL: String
    public var bootableInstallerArticlePublished: String
    public var downloadArticleURL: String
    public var downloadArticlePublished: String
    public var softwareUpdateHelpURL: String
    public var softwareUpdateSettingsURL: String
    public var upgrade27URL: String
    public var voiceOverGuideURL: String
    public var appStoreGuidelinesURL: String
    public var appStoreGuidelinesUpdated: String
}

public enum ModelQuery: Equatable, Sendable {
    case identifier(String)
    case marketingName(String)
    case partNumber(String)

    public var rawText: String {
        switch self {
        case .identifier(let text), .marketingName(let text), .partNumber(let text):
            return text
        }
    }
}

enum PartNumberMatch {
    static func matches(catalogPart: String, user: String) -> Bool {
        let catalog = normalize(catalogPart)
        guard let marker = catalog.range(of: "XX/A") else { return false }
        let stem = String(catalog[..<marker.lowerBound])
        guard stem.count >= 4 else { return false }
        var entered = normalize(user)
        if entered.hasSuffix("/A") {
            entered.removeLast(2)
        }
        if entered == stem || entered == stem + "XX" {
            return true
        }
        guard entered.hasPrefix(stem) else { return false }
        let region = entered.dropFirst(stem.count)
        return region.count == 2 && region.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private static func normalize(_ value: String) -> String {
        value.uppercased().filter { !$0.isWhitespace }
    }
}

private struct CatalogFile: Codable {
    var retrieved: String
    var statement: String
    var models: [ModelRecord]
    var releases: [OperatingSystemRelease]
    var rules: CatalogRules
}
