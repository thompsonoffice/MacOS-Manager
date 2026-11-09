import Foundation

public struct SpokenInstallError: Error, Equatable, LocalizedError, Sendable {
    public var plainLanguage: String
    public var rawDetail: String
    /// The catalog download failed in a way that makes Apple's softwareupdate worth trying.
    public var allowsSoftwareUpdateFallback: Bool
    /// softwareupdate failed, and a catalog package may still be tried.
    public var allowsDirectPackageFallback: Bool

    public init(
        plainLanguage: String,
        rawDetail: String,
        allowsSoftwareUpdateFallback: Bool,
        allowsDirectPackageFallback: Bool
    ) {
        self.plainLanguage = plainLanguage
        self.rawDetail = rawDetail
        self.allowsSoftwareUpdateFallback = allowsSoftwareUpdateFallback
        self.allowsDirectPackageFallback = allowsDirectPackageFallback
    }

    public var errorDescription: String? { plainLanguage }
}

public enum InstallErrorMapping {
    public static func productKey(in message: String) -> String? {
        capture("SUErrorUpdateProductKey=([0-9]{3}-[A-Za-z0-9-]+)", in: message)
    }

    public static func serverName(in message: String) -> String? {
        capture("SUErrorUpdateServerName=([A-Za-z0-9._-]+)", in: message)
    }

    public static func isSoftwareUpdateSignatureFailure(_ message: String) -> Bool {
        let compact = message.lowercased().filter { !$0.isWhitespace }
        let domain = compact.contains("suerrordomain") && (compact.contains("code=203") || compact.contains("code:203"))
        let words = message.lowercased().contains("digital signature")
            && (message.lowercased().contains("missing") || message.lowercased().contains("invalid"))
        return domain || words
    }

    /// Plain language for a softwareupdate failure. The original text stays in `rawDetail`.
    public static func softwareUpdate(exitCode: Int32, message: String, willTryDirectDownload: Bool) -> SpokenInstallError {
        let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = namedProductSentence(detail)
        let plain: String
        if isSoftwareUpdateSignatureFailure(detail) {
            if willTryDirectDownload {
                plain = "Apple's softwareupdate could not verify the digital signature on this update. \(named)The installer was not taken from Software Update. macOS Manager will download Apple's installer package and check its signature before installing it."
            } else {
                plain = "The installer was not installed. Apple's softwareupdate said the digital signature on the update is missing or invalid. \(named)No installer package from Apple's catalog was installed."
            }
        } else if willTryDirectDownload {
            plain = "Apple's softwareupdate stopped with code \(exitCode). \(named)macOS Manager will try the installer package from Apple's catalog instead."
        } else {
            plain = "The installer was not installed. Apple's softwareupdate stopped with code \(exitCode). \(named)"
        }
        return SpokenInstallError(
            plainLanguage: plain.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines),
            rawDetail: detail.isEmpty ? "softwareupdate exited with code \(exitCode)." : detail,
            allowsSoftwareUpdateFallback: false,
            allowsDirectPackageFallback: true
        )
    }

    public static func present(_ error: Error) -> SpokenInstallError {
        if let spoken = error as? SpokenInstallError {
            return spoken
        }
        if let workflow = error as? WorkflowError {
            switch workflow {
            case .commandFailed(let code, let message):
                let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
                let plain = detail.isEmpty
                    ? "The command stopped with code \(code)."
                    : "The command stopped with code \(code). The technical detail is shown below."
                return SpokenInstallError(
                    plainLanguage: plain,
                    rawDetail: detail,
                    allowsSoftwareUpdateFallback: false,
                    allowsDirectPackageFallback: false
                )
            default:
                return SpokenInstallError(
                    plainLanguage: workflow.localizedDescription,
                    rawDetail: "",
                    allowsSoftwareUpdateFallback: false,
                    allowsDirectPackageFallback: false
                )
            }
        }
        return SpokenInstallError(
            plainLanguage: "The installer was not installed. \(error.localizedDescription)",
            rawDetail: String(describing: error),
            allowsSoftwareUpdateFallback: true,
            allowsDirectPackageFallback: false
        )
    }

    private static func namedProductSentence(_ message: String) -> String {
        switch (productKey(in: message), serverName(in: message)) {
        case let (key?, server?):
            return "Software Update named product \(key) on \(server). "
        case let (key?, nil):
            return "Software Update named product \(key). "
        default:
            return ""
        }
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let found = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[found])
    }
}

public struct SignatureVerdict: Equatable, Sendable {
    public var accepted: Bool
    public var spoken: SpokenInstallError

    public init(accepted: Bool, spoken: SpokenInstallError) {
        self.accepted = accepted
        self.spoken = spoken
    }
}

public enum PackageSignatureCheck {
    /// Accepts a pkgutil report only when the chain includes Apple Software and an Apple root or Apple Inc. certificate.
    public static func evaluate(exitCode: Int32, output: String) -> SignatureVerdict {
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = certificateNames(in: detail)
        let status = statusLine(in: detail)
        let unsigned = status?.lowercased().contains("no signature") ?? false
        let appleSoftware = names.contains { $0.range(of: "Apple Software", options: .caseInsensitive) != nil }
        let appleAuthority = names.contains { name in
            name.range(of: "Apple Root CA", options: .caseInsensitive) != nil
                || name.range(of: "Apple Inc", options: .caseInsensitive) != nil
        }
        let accepted = exitCode == 0 && status != nil && !unsigned && appleSoftware && appleAuthority
        let plain: String
        if accepted {
            plain = "pkgutil reports this package is signed by Apple Software, and the chain includes an Apple root certificate. The package can be installed."
        } else if unsigned || status == nil && exitCode != 0 && names.isEmpty {
            plain = "The package was not installed. pkgutil did not report an Apple signature."
        } else if !appleSoftware {
            plain = "The package was not installed. Its certificate chain does not include an Apple Software certificate."
        } else if !appleAuthority {
            plain = "The package was not installed. Its certificate chain does not include an Apple root or Apple Inc. certificate."
        } else {
            plain = "The package was not installed. pkgutil stopped with code \(exitCode) and did not accept the signature."
        }
        return SignatureVerdict(
            accepted: accepted,
            spoken: SpokenInstallError(
                plainLanguage: plain,
                rawDetail: detail,
                allowsSoftwareUpdateFallback: false,
                allowsDirectPackageFallback: false
            )
        )
    }

    public static func certificateNames(in output: String) -> [String] {
        var names: [String] = []
        var inChain = false
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.localizedCaseInsensitiveContains("Certificate Chain") {
                inChain = true
                continue
            }
            guard inChain else { continue }
            guard let name = certificateName(on: line) else { continue }
            names.append(name)
        }
        return names
    }

    private static func certificateName(on line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index].isNumber {
            index = trimmed.index(after: index)
        }
        guard index != trimmed.startIndex, index < trimmed.endIndex, trimmed[index] == "." else { return nil }
        let afterDot = trimmed.index(after: index)
        let name = trimmed[afterDot...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return name
    }

    private static func statusLine(in output: String) -> String? {
        output.split(whereSeparator: \.isNewline).map(String.init).first {
            $0.localizedCaseInsensitiveContains("Status:")
        }
    }
}

public enum PackageSizeCheck {
    /// Full macOS installer packages are multiple gigabytes. A smaller catalog size is not offered.
    public static let minimumFullInstallerBytes: Int64 = 500_000_000

    public static func evaluate(expected: Int64, actual: Int64) -> SpokenInstallError? {
        if expected < minimumFullInstallerBytes {
            return SpokenInstallError(
                plainLanguage: "Apple's catalog listed a package that is too small to be a full macOS installer. Nothing was installed.",
                rawDetail: "Catalog size \(expected) bytes. Downloaded size \(actual) bytes.",
                allowsSoftwareUpdateFallback: false,
                allowsDirectPackageFallback: false
            )
        }
        if actual != expected {
            return SpokenInstallError(
                plainLanguage: "The downloaded file size does not match Apple's catalog. Nothing was installed.",
                rawDetail: "Catalog size \(expected) bytes. Downloaded size \(actual) bytes.",
                allowsSoftwareUpdateFallback: true,
                allowsDirectPackageFallback: false
            )
        }
        return nil
    }
}

public enum DownloadProgressText {
    public static func line(bytes: Int64, expected: Int64) -> String {
        let amount = spoken(bytes)
        guard expected > 0 else { return "Downloaded \(amount)." }
        let percent = min(100, (bytes * 100) / expected)
        return "Downloaded \(amount) of \(spoken(expected)). \(percent) percent."
    }

    public static func spoken(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MB" }
        if bytes < 1_000_000_000 {
            let megabytes = (bytes + 500_000) / 1_000_000
            return "\(megabytes) MB"
        }
        return DiskSurveyParser.spokenCapacity(bytes)
    }
}

public enum InstallerCommands {
    public static func checkSignature(
        packagePath: String,
        pkgutil: String = "/usr/sbin/pkgutil"
    ) -> Result<ArgumentVector, WorkflowError> {
        switch checkedPackagePath(packagePath) {
        case .failure(let error):
            return .failure(error)
        case .success(let path):
            return .success(ArgumentVector(
                executable: pkgutil,
                arguments: ["--check-signature", path],
                needsAdministratorPrompt: false
            ))
        }
    }

    public static func install(
        packagePath: String,
        installer: String = "/usr/sbin/installer"
    ) -> Result<ArgumentVector, WorkflowError> {
        switch checkedPackagePath(packagePath) {
        case .failure(let error):
            return .failure(error)
        case .success(let path):
            return .success(ArgumentVector(
                executable: installer,
                arguments: ["-pkg", path, "-target", "/"],
                needsAdministratorPrompt: true
            ))
        }
    }

    private static func checkedPackagePath(_ packagePath: String) -> Result<String, WorkflowError> {
        if packagePath.contains("\0") || packagePath.contains("\n") || !packagePath.hasPrefix("/") {
            return .failure(.commandRejected("The package path must be an absolute path without control characters."))
        }
        let url = URL(fileURLWithPath: packagePath).standardizedFileURL
        guard url.isFileURL, url.path.hasPrefix("/"), url.lastPathComponent == "InstallAssistant.pkg" else {
            return .failure(.commandRejected("The package must be an absolute path named InstallAssistant.pkg."))
        }
        return .success(url.path)
    }
}

public enum InstallerAttempt: Equatable, Sendable {
    case direct(CatalogInstallerPackage)
    case softwareUpdate(version: String)
}

public enum InstallerAttemptOrder {
    /// The catalog package is the primary attempt. softwareupdate runs only if that download fails.
    public static func preferred(package: CatalogInstallerPackage) -> [InstallerAttempt] {
        guard let version = package.version, InstallWorkflow.isOfficialVersionToken(version) else {
            return [.direct(package)]
        }
        return [.direct(package), .softwareUpdate(version: version)]
    }

    /// After softwareupdate fails, choose the catalog package for that product or version.
    public static func packageAfterSoftwareUpdate(
        requestedVersion: String,
        error: WorkflowError,
        packages: [CatalogInstallerPackage]
    ) -> CatalogInstallerPackage? {
        guard case .commandFailed(_, let message) = error else { return nil }
        let usable = packages.filter {
            AppleDownloadHosts.isInstallAssistantPackageURL($0.packageURL) && $0.expectedSize >= PackageSizeCheck.minimumFullInstallerBytes
        }
        if let key = InstallErrorMapping.productKey(in: message),
           let match = usable.first(where: { $0.productKey == key }) {
            return match
        }
        return usable
            .filter { $0.version == requestedVersion }
            .max { $0.expectedSize < $1.expectedSize }
    }

    public static func mayContinue(after failure: SpokenInstallError, to next: InstallerAttempt) -> Bool {
        switch next {
        case .direct:
            return failure.allowsDirectPackageFallback
        case .softwareUpdate:
            return failure.allowsSoftwareUpdateFallback
        }
    }
}

public struct InstallerOffer: Equatable, Sendable, Identifiable {
    public var releaseID: String
    public var marketingName: String
    public var version: String
    public var build: String?
    public var productKey: String
    public var package: CatalogInstallerPackage

    public var id: String { releaseID }

    public init(
        releaseID: String,
        marketingName: String,
        version: String,
        build: String?,
        productKey: String,
        package: CatalogInstallerPackage
    ) {
        self.releaseID = releaseID
        self.marketingName = marketingName
        self.version = version
        self.build = build
        self.productKey = productKey
        self.package = package
    }
}

public struct InstallerRefusal: Equatable, Sendable, Identifiable {
    public var id: String
    public var plainLanguage: String

    public init(id: String, plainLanguage: String) {
        self.id = id
        self.plainLanguage = plainLanguage
    }
}

public struct InstallerOfferSet: Equatable, Sendable {
    public var hostName: String
    public var offers: [InstallerOffer]
    public var refusals: [InstallerRefusal]

    public init(hostName: String, offers: [InstallerOffer], refusals: [InstallerRefusal]) {
        self.hostName = hostName
        self.offers = offers
        self.refusals = refusals
    }
}

public enum InstallerOffers {
    public static func hostReport(catalog: Catalog, reading: MachineReading) -> CompatibilityReport {
        let identifier = reading.modelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return CompatibilityReport.build(catalog: catalog, query: .identifier(identifier), reading: reading)
    }

    /// Bundled build token used only when the live catalog cannot be read. Nil when this Mac is not listed for that release.
    public static func bundledVersionIfInstallable(
        catalog: Catalog,
        hostReport: CompatibilityReport,
        releaseID: String
    ) -> String? {
        guard hostReport.found,
              let release = catalog.releases.first(where: { $0.id == releaseID }),
              let assessment = hostReport.versions.first(where: { $0.releaseID == releaseID }),
              assessment.claim == .listedOnApplePage || assessment.claim == .coveredByAppleSiliconStatement,
              InstallWorkflow.isOfficialVersionToken(release.latestBuild) else {
            return nil
        }
        return release.latestBuild
    }

    public static func differentMacExplanation(host: CompatibilityReport, lookup: CompatibilityReport?) -> String? {
        guard host.found, let lookup, lookup.found else { return nil }
        let hostNames = host.records.map(\.name)
        let lookupNames = lookup.records.map(\.name)
        guard hostNames != lookupNames else { return nil }
        return "You looked up \(lookupNames.joined(separator: " and ")). Installers on this screen are for this Mac, \(hostNames.joined(separator: " and "))."
    }

    /// Offers a version only when Apple's live catalog has it and this Mac is listed for that release.
    public static func make(
        catalog: Catalog,
        hostReport: CompatibilityReport,
        packages: [CatalogInstallerPackage]
    ) -> InstallerOfferSet {
        guard hostReport.found else {
            return InstallerOfferSet(hostName: "this Mac", offers: [], refusals: [unknownHost(hostReport)])
        }
        let hostName = hostReport.records.map(\.name).joined(separator: " and ")
        var offers: [InstallerOffer] = []
        var refusals: [InstallerRefusal] = []
        var matchedKeys = Set<String>()
        for release in catalog.compatibilityReleases {
            let assessment = hostReport.versions.first { $0.releaseID == release.id }
            let matching = packages.filter { package in
                guard let version = package.version,
                      InstallWorkflow.isOfficialVersionToken(version),
                      AppleDownloadHosts.isInstallAssistantPackageURL(package.packageURL),
                      SUCatalogParser.releaseID(for: version, catalog: catalog) == release.id else {
                    return false
                }
                return true
            }
            matching.forEach { matchedKeys.insert($0.productKey) }
            let usable = matching.filter { $0.expectedSize >= PackageSizeCheck.minimumFullInstallerBytes }
            let compatible = assessment.map(canInstall) ?? false
            if compatible, let best = preferred(usable), let version = best.version {
                offers.append(InstallerOffer(
                    releaseID: release.id,
                    marketingName: release.marketingName,
                    version: version,
                    build: best.build,
                    productKey: best.productKey,
                    package: best
                ))
            } else if compatible, !matching.isEmpty {
                refusals.append(InstallerRefusal(
                    id: release.id,
                    plainLanguage: "\(release.marketingName) is listed for \(hostName), but the package in Apple's catalog is too small to be a full installer. It was not offered."
                ))
            } else if compatible {
                refusals.append(InstallerRefusal(
                    id: release.id,
                    plainLanguage: "\(release.marketingName) is listed for \(hostName), but Apple's live catalog does not include an InstallAssistant package for it. It was not offered."
                ))
            } else if let best = preferred(usable), let version = best.version {
                refusals.append(InstallerRefusal(
                    id: release.id,
                    plainLanguage: "\(release.marketingName) \(version) is in Apple's live catalog as product \(best.productKey), but \(hostName) is not listed for it. It cannot be installed on this Mac."
                ))
            }
        }
        let unmapped = packages.filter { package in
            guard let version = package.version else { return false }
            return SUCatalogParser.releaseID(for: version, catalog: catalog) == nil && !matchedKeys.contains(package.productKey)
        }
        if !unmapped.isEmpty {
            let list = unmapped.map { "\($0.version ?? "unknown") (\($0.productKey))" }.joined(separator: ", ")
            refusals.append(InstallerRefusal(
                id: "unmapped",
                plainLanguage: "Apple's catalog also lists \(list). This app has no compatibility page for that version, so it was not offered."
            ))
        }
        return InstallerOfferSet(hostName: hostName, offers: offers, refusals: refusals)
    }

    private static func canInstall(_ assessment: VersionAssessment) -> Bool {
        assessment.claim == .listedOnApplePage || assessment.claim == .coveredByAppleSiliconStatement
    }

    private static func preferred(_ packages: [CatalogInstallerPackage]) -> CatalogInstallerPackage? {
        packages.max { lhs, rhs in
            let order = compareVersions(lhs.version ?? "", rhs.version ?? "")
            if order != .orderedSame {
                return order == .orderedAscending
            }
            if lhs.expectedSize != rhs.expectedSize {
                return lhs.expectedSize < rhs.expectedSize
            }
            return lhs.productKey < rhs.productKey
        }
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func unknownHost(_ report: CompatibilityReport) -> InstallerRefusal {
        let identifier = report.query.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let plain: String
        if identifier.isEmpty {
            if let probe = report.machine?.probeError, !probe.isEmpty {
                plain = "\(probe) No installer was offered."
            } else {
                plain = "This Mac did not return a model identifier, so no installer was offered."
            }
        } else {
            plain = "No Apple model in this catalog matches \(identifier). No installer was offered for this Mac."
        }
        return InstallerRefusal(id: "host", plainLanguage: plain)
    }
}
