import Foundation

public enum VersionClaim: Equatable, Sendable {
    case listedOnApplePage
    case coveredByAppleSiliconStatement
    case notListed
    case differsAcrossRecords
    case noPerModelPage

    public var label: String {
        switch self {
        case .listedOnApplePage:
            return "Listed on Apple's compatibility page"
        case .coveredByAppleSiliconStatement:
            return "Covered by Apple's Apple silicon statement"
        case .notListed:
            return "Not listed under this exact name"
        case .differsAcrossRecords:
            return "Apple's records for this identifier do not agree"
        case .noPerModelPage:
            return "No per-model compatibility page in this catalog"
        }
    }
}

public struct VersionAssessment: Equatable, Sendable, Identifiable {
    public var releaseID: String
    public var marketingName: String
    public var latestBuild: String
    public var compatibilityPageURL: String?
    public var claim: VersionClaim
    public var exactModelNames: [String]
    public var notListedModelNames: [String]
    public var nearMissNames: [String]
    public var blanketStatement: String?
    public var blanketURL: String?

    public var id: String { releaseID }
}

public enum NewestStatement: Equatable, Sendable {
    case stated(String, footnote: String?)
    case notStated
    case disagrees([String])
}

public struct CompatibilityReport: Equatable, Sendable {
    public var query: ModelQuery
    public var records: [ModelRecord]
    public var found: Bool
    public var processor: ProcessorClass
    public var t2: T2Status
    public var architecture: ArchitectureComparison
    public var machine: MachineReading?
    public var newest: NewestStatement
    public var versions: [VersionAssessment]
    public var factoryOperatingSystem: String
    public var installersCurrentlyOffered: String
    public var sentences: [String]

    public var spokenSummary: String {
        sentences.joined(separator: " ")
    }

    public var briefAnnouncement: String {
        guard found else { return spokenSummary }
        let name = records.count == 1 ? (records.first?.name ?? "a Mac") : "\(records.count) Apple models"
        let newestText: String
        switch newest {
        case .stated(let text, _):
            newestText = "Newest system named by Apple: \(text)."
        case .notStated:
            newestText = "Apple's identify page does not name a newest system."
        case .disagrees:
            newestText = "Apple's records disagree about the newest system."
        }
        let top = versions.first.map { "\($0.marketingName): \($0.claim.label)." } ?? ""
        let sandbox = machine.map { " \($0.sandboxStatus)" } ?? ""
        return "Found \(name). Processor class \(processor.label). \(newestText) \(top) The full result is on screen.\(sandbox)"
    }

    public static let factoryOperatingSystemText =
        "The macOS version that originally shipped on this Mac is not in this catalog. Apple's identify pages used here do not state it."

    public var compatibleVersions: [VersionAssessment] {
        versions.filter {
            $0.claim == .listedOnApplePage || $0.claim == .coveredByAppleSiliconStatement
        }
    }

    public static let installersCurrentlyOfferedText =
        "This edition does not run softwareupdate itself and does not download an installer. A button for each compatible version opens Apple's official installer or Software Update page so you can install, upgrade, or downgrade on this Mac. Apple handles the download and progress."

    public static func build(
        catalog: Catalog,
        query: ModelQuery,
        reading: MachineReading? = nil
    ) -> CompatibilityReport {
        let trimmed = query.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return empty(query: query, reading: reading, sentence: "Enter a model identifier, model name, or part number.")
        }
        let records = catalog.records(for: query)
        guard !records.isEmpty else {
            return empty(
                query: query,
                reading: reading,
                sentence: "No Apple model in this catalog matches \(trimmed). Nothing is claimed about which macOS it supports."
            )
        }
        let processors = records.map { ProcessorRules.processor(for: $0, rules: catalog.rules) }
        let processor = ProcessorRules.combinedProcessor(processors)
        let t2Values = zip(records, processors).map { record, processor in
            ProcessorRules.t2(for: record, processor: processor, rules: catalog.rules)
        }
        let t2 = ProcessorRules.combinedT2(t2Values)
        let architecture = ProcessorRules.compare(machine: reading?.machine, processor: processor)
        let suppressBlanket = architecture == .contradictsCatalog || processor.kind == .unknown
        let versions = catalog.compatibilityReleases.map { release in
            assess(
                release: release,
                records: records,
                processors: processors,
                suppressBlanket: suppressBlanket
            )
        }
        let newest = newestStatement(records)
        let sentences = speak(
            query: query,
            trimmed: trimmed,
            records: records,
            processor: processor,
            t2: t2,
            architecture: architecture,
            reading: reading,
            newest: newest,
            versions: versions,
            retrieved: catalog.retrieved
        )
        return CompatibilityReport(
            query: query,
            records: records,
            found: true,
            processor: processor,
            t2: t2,
            architecture: architecture,
            machine: reading,
            newest: newest,
            versions: versions,
            factoryOperatingSystem: factoryOperatingSystemText,
            installersCurrentlyOffered: installersCurrentlyOfferedText,
            sentences: sentences
        )
    }

    private static func empty(query: ModelQuery, reading: MachineReading?, sentence: String) -> CompatibilityReport {
        CompatibilityReport(
            query: query,
            records: [],
            found: false,
            processor: .unknown(explanation: "No matching Apple model record."),
            t2: .unknown(explanation: "No matching Apple model record."),
            architecture: .readingUnavailable,
            machine: reading,
            newest: .notStated,
            versions: [],
            factoryOperatingSystem: factoryOperatingSystemText,
            installersCurrentlyOffered: installersCurrentlyOfferedText,
            sentences: [sentence]
        )
    }

    private static func assess(
        release: OperatingSystemRelease,
        records: [ModelRecord],
        processors: [ProcessorClass],
        suppressBlanket: Bool
    ) -> VersionAssessment {
        guard release.hasPerModelCompatibilityPage else {
            return VersionAssessment(
                releaseID: release.id,
                marketingName: release.marketingName,
                latestBuild: release.latestBuild,
                compatibilityPageURL: release.compatibilityPageURL,
                claim: .noPerModelPage,
                exactModelNames: [],
                notListedModelNames: records.map(\.name),
                nearMissNames: [],
                blanketStatement: nil,
                blanketURL: nil
            )
        }
        var exact: [String] = []
        var missing: [String] = []
        var near = Set<String>()
        var blanketCount = 0
        for (record, processor) in zip(records, processors) {
            if release.listedModelNames.contains(record.name) {
                exact.append(record.name)
            } else {
                missing.append(record.name)
                for listed in release.listedModelNames where ModelNameComparison.isNearMiss(modelName: record.name, listedName: listed) {
                    near.insert(listed)
                }
            }
            if release.appleSiliconBlanket != nil, processor.kind == .appleSilicon, !suppressBlanket {
                blanketCount += 1
            }
        }
        let claim: VersionClaim
        if exact.count == records.count {
            claim = .listedOnApplePage
        } else if !exact.isEmpty {
            claim = .differsAcrossRecords
        } else if blanketCount == records.count, release.appleSiliconBlanket != nil {
            claim = .coveredByAppleSiliconStatement
        } else {
            claim = .notListed
        }
        return VersionAssessment(
            releaseID: release.id,
            marketingName: release.marketingName,
            latestBuild: release.latestBuild,
            compatibilityPageURL: release.compatibilityPageURL,
            claim: claim,
            exactModelNames: unique(exact),
            notListedModelNames: unique(missing),
            nearMissNames: near.sorted(),
            blanketStatement: claim == .coveredByAppleSiliconStatement ? release.appleSiliconBlanket?.statement : nil,
            blanketURL: claim == .coveredByAppleSiliconStatement ? release.appleSiliconBlanket?.url : nil
        )
    }

    private static func newestStatement(_ records: [ModelRecord]) -> NewestStatement {
        let texts = unique(records.compactMap(\.newestOperatingSystemText))
        if texts.count > 1 {
            return .disagrees(texts)
        }
        if let text = texts.first {
            let footnotes = unique(records.compactMap(\.newestOperatingSystemFootnote))
            return .stated(text, footnote: footnotes.first)
        }
        return .notStated
    }

    private static func speak(
        query: ModelQuery,
        trimmed: String,
        records: [ModelRecord],
        processor: ProcessorClass,
        t2: T2Status,
        architecture: ArchitectureComparison,
        reading: MachineReading?,
        newest: NewestStatement,
        versions: [VersionAssessment],
        retrieved: String
    ) -> [String] {
        var lines: [String] = []
        if records.count == 1, let record = records.first {
            lines.append("Apple's page calls \(trimmed) \(record.name).")
        } else {
            let names = records.map(\.name).joined(separator: ", ")
            lines.append("Apple uses \(trimmed) for more than one model: \(names). Read each one. This result does not pick between them.")
        }
        if let chip = unique(records.compactMap(\.chipLabel)).first, records.count == 1 {
            lines.append("Apple's name or description includes the chip \(chip).")
        }
        lines.append("Processor class: \(processor.label). \(processor.explanation)")
        lines.append(architecture.spoken)
        if let version = reading?.operatingSystemVersion, !version.isEmpty {
            lines.append("The reading says this Mac is running \(version). That is the installed system, not a list of compatible systems.")
        }
        if let sandbox = reading?.sandboxStatus, !sandbox.isEmpty {
            lines.append(sandbox)
        }
        lines.append("T2: \(t2.label). \(t2.explanation)")
        switch newest {
        case .stated(let text, let footnote):
            lines.append("Apple's identify page names the newest compatible system as \(text).")
            if let footnote {
                lines.append(footnote)
            }
        case .notStated:
            lines.append("Apple's identify page used here does not name a newest compatible system for this model.")
        case .disagrees(let texts):
            lines.append("The newest system on Apple's identify page disagrees across these records: \(texts.joined(separator: ", ")).")
        }
        lines.append(factoryOperatingSystemText)
        lines.append(installersCurrentlyOfferedText)
        if let current = versions.first {
            lines.append("\(current.marketingName): \(current.claim.label).")
            if !current.nearMissNames.isEmpty, current.claim != .listedOnApplePage {
                lines.append("A similar name on that page is not treated as a match: \(current.nearMissNames.joined(separator: ", ")).")
            }
        }
        lines.append("The other compatibility rows are on screen. Facts were retrieved \(retrieved).")
        lines.append("This result does not download macOS and does not erase a drive.")
        return lines
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
