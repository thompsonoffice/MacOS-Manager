import Foundation

public enum ProcessorClass: Equatable, Sendable {
    case appleSilicon(explanation: String)
    case intel(explanation: String)
    case unknown(explanation: String)

    public var label: String {
        switch self {
        case .appleSilicon:
            return "Apple silicon"
        case .intel:
            return "Intel"
        case .unknown:
            return "Unknown"
        }
    }

    public var explanation: String {
        switch self {
        case .appleSilicon(let explanation), .intel(let explanation), .unknown(let explanation):
            return explanation
        }
    }

    var kind: Kind {
        switch self {
        case .appleSilicon:
            return .appleSilicon
        case .intel:
            return .intel
        case .unknown:
            return .unknown
        }
    }

    enum Kind {
        case appleSilicon
        case intel
        case unknown
    }
}

public enum T2Status: Equatable, Sendable {
    case listedByApple(explanation: String)
    case notOnAppleList(explanation: String)
    case notApplicableBecauseAppleSilicon(explanation: String)
    case unknown(explanation: String)

    public var label: String {
        switch self {
        case .listedByApple:
            return "Listed by Apple as a T2 Mac"
        case .notOnAppleList:
            return "Not on Apple's T2 list"
        case .notApplicableBecauseAppleSilicon:
            return "Not a T2 Mac"
        case .unknown:
            return "Unknown"
        }
    }

    public var explanation: String {
        switch self {
        case .listedByApple(let explanation),
             .notOnAppleList(let explanation),
             .notApplicableBecauseAppleSilicon(let explanation),
             .unknown(let explanation):
            return explanation
        }
    }
}

public enum ArchitectureComparison: Equatable, Sendable {
    case consistent
    case contradictsCatalog
    case catalogProcessorUnknown
    case readingUnavailable

    public var spoken: String {
        switch self {
        case .consistent:
            return "The hw.machine value agrees with that processor class."
        case .contradictsCatalog:
            return "The hw.machine value does not agree with the processor class from Apple's model list. Neither fact is discarded. macOS 27's Apple silicon statement is not applied while they disagree."
        case .catalogProcessorUnknown:
            return "hw.machine was read, and the processor class from Apple's model list is unknown."
        case .readingUnavailable:
            return "hw.machine was not read. The processor class comes only from Apple's published model rules."
        }
    }
}

public struct MachineReading: Equatable, Sendable {
    public var modelIdentifier: String?
    public var machine: String?
    public var operatingSystemVersion: String?
    public var probeMethod: String
    public var sandboxStatus: String
    public var probeError: String?

    public init(
        modelIdentifier: String?,
        machine: String?,
        operatingSystemVersion: String?,
        probeMethod: String,
        sandboxStatus: String,
        probeError: String?
    ) {
        self.modelIdentifier = modelIdentifier
        self.machine = machine
        self.operatingSystemVersion = operatingSystemVersion
        self.probeMethod = probeMethod
        self.sandboxStatus = sandboxStatus
        self.probeError = probeError
    }
}

enum ProcessorRules {
    static func processor(for record: ModelRecord, rules: CatalogRules) -> ProcessorClass {
        let article = "Apple's article \(rules.appleSiliconArticleURL), published \(rules.appleSiliconArticlePublished), lists which Macs use Apple silicon. This is not a live reading of the chip."
        if record.yearSource == "conflict" || (record.yearIntroduced == nil && record.family != "MacBook Neo") {
            return .unknown(explanation: "The introduction year is unknown, so Apple's Apple silicon rules cannot be applied. \(article)")
        }
        switch record.family {
        case "MacBook Neo":
            return .appleSilicon(explanation: "Apple lists MacBook Neo as Apple silicon. \(article)")
        case "MacBook Pro":
            if record.name == "MacBook Pro (13-inch, M1, 2020)" {
                return .appleSilicon(explanation: "Apple names MacBook Pro (13-inch, M1, 2020) in the Apple silicon list. \(article)")
            }
            return introduced(record, atLeast: 2021)
                ? .appleSilicon(explanation: "Apple includes MacBook Pro models introduced in 2021 or later. \(article)")
                : .intel(explanation: "This MacBook Pro is outside the models Apple lists as Apple silicon. \(article) Apple says a Mac with an Intel processor is not a Mac with Apple silicon.")
        case "MacBook Air":
            if record.name == "MacBook Air (M1, 2020)" {
                return .appleSilicon(explanation: "Apple names MacBook Air (M1, 2020) in the Apple silicon list. \(article)")
            }
            return introduced(record, atLeast: 2022)
                ? .appleSilicon(explanation: "Apple includes MacBook Air models introduced in 2022 or later. \(article)")
                : .intel(explanation: "This MacBook Air is outside the models Apple lists as Apple silicon. \(article)")
        case "iMac":
            return introduced(record, atLeast: 2021)
                ? .appleSilicon(explanation: "Apple includes iMac models introduced in 2021 or later. \(article)")
                : .intel(explanation: "This iMac is outside the models Apple lists as Apple silicon. \(article)")
        case "Mac mini":
            return introduced(record, atLeast: 2020)
                ? .appleSilicon(explanation: "Apple includes Mac mini models introduced in 2020 or later. \(article)")
                : .intel(explanation: "This Mac mini is outside the models Apple lists as Apple silicon. \(article)")
        case "Mac Studio":
            return introduced(record, atLeast: 2022)
                ? .appleSilicon(explanation: "Apple includes Mac Studio models introduced in 2022 or later. \(article)")
                : .intel(explanation: "This Mac Studio is outside the models Apple lists as Apple silicon. \(article)")
        case "Mac Pro":
            return introduced(record, atLeast: 2023)
                ? .appleSilicon(explanation: "Apple includes Mac Pro models introduced in 2023 or later. \(article)")
                : .intel(explanation: "This Mac Pro is outside the models Apple lists as Apple silicon. \(article)")
        case "Mac Pro Server", "MacBook", "iMac Pro":
            return .intel(explanation: "Apple's Apple silicon list does not include this model. \(article)")
        default:
            return .unknown(explanation: "This model family is not in Apple's Apple silicon rules. \(article)")
        }
    }

    static func t2(for record: ModelRecord, processor: ProcessorClass, rules: CatalogRules) -> T2Status {
        let article = "Apple's T2 article \(rules.t2ArticleURL), published \(rules.t2ArticlePublished)."
        switch processor.kind {
        case .appleSilicon:
            return .notApplicableBecauseAppleSilicon(explanation: "Apple describes the T2 chip as custom silicon for Intel-based Macs. \(article)")
        case .unknown:
            return .unknown(explanation: "The processor class is unknown, so the T2 list is not applied. \(article)")
        case .intel:
            break
        }
        let listed: Bool
        switch record.family {
        case "MacBook Pro":
            listed = year(record, in: 2018...2020) && record.name != "MacBook Pro (13-inch, M1, 2020)"
        case "MacBook Air":
            listed = year(record, in: 2018...2020) && record.name != "MacBook Air (M1, 2020)"
        case "iMac":
            listed = record.name == "iMac (Retina 5K, 27-inch, 2020)"
        case "iMac Pro":
            listed = true
        case "Mac mini":
            listed = record.yearIntroduced == 2018
        case "Mac Pro":
            listed = record.yearIntroduced == 2019
        default:
            listed = false
        }
        if listed {
            return .listedByApple(explanation: "This model falls inside the groups on \(article)")
        }
        return .notOnAppleList(explanation: "Apple's T2 list does not include this model. That is not a live System Information reading. \(article)")
    }

    static func compare(machine: String?, processor: ProcessorClass) -> ArchitectureComparison {
        guard let machine = machine?.trimmingCharacters(in: .whitespacesAndNewlines), !machine.isEmpty else {
            return .readingUnavailable
        }
        let arm = machine.caseInsensitiveCompare("arm64") == .orderedSame
        let intel = machine.caseInsensitiveCompare("x86_64") == .orderedSame
        guard arm || intel else {
            return .readingUnavailable
        }
        switch processor.kind {
        case .unknown:
            return .catalogProcessorUnknown
        case .appleSilicon:
            return arm ? .consistent : .contradictsCatalog
        case .intel:
            return intel ? .consistent : .contradictsCatalog
        }
    }

    static func combinedProcessor(_ values: [ProcessorClass]) -> ProcessorClass {
        guard let first = values.first else {
            return .unknown(explanation: "No Apple model record was found.")
        }
        if values.allSatisfy({ $0.kind == first.kind }) {
            return first
        }
        return .unknown(explanation: "Apple's identify page uses this identifier on models whose processor classes do not agree. Nothing is chosen between them.")
    }

    static func combinedT2(_ values: [T2Status]) -> T2Status {
        guard let first = values.first else {
            return .unknown(explanation: "No Apple model record was found.")
        }
        if values.allSatisfy({ t2Kind($0) == t2Kind(first) }) {
            return first
        }
        return .unknown(explanation: "The Apple records for this identifier do not agree about the T2 chip.")
    }

    private static func introduced(_ record: ModelRecord, atLeast minimum: Int) -> Bool {
        guard let year = record.yearIntroduced else { return false }
        return year >= minimum
    }

    private static func year(_ record: ModelRecord, in range: ClosedRange<Int>) -> Bool {
        guard let year = record.yearIntroduced else { return false }
        return range.contains(year)
    }

    private static func t2Kind(_ status: T2Status) -> String {
        switch status {
        case .listedByApple:
            return "listed"
        case .notOnAppleList:
            return "absent"
        case .notApplicableBecauseAppleSilicon:
            return "silicon"
        case .unknown:
            return "unknown"
        }
    }
}

enum ModelNameComparison {
    static func isNearMiss(modelName: String, listedName: String) -> Bool {
        if modelName.caseInsensitiveCompare(listedName) == .orderedSame {
            return false
        }
        if modelName.hasPrefix(listedName) || listedName.hasPrefix(modelName) {
            return true
        }
        // Apple sometimes closes a name, then later adds ", Four ports" inside it.
        if listedName.hasSuffix(")"), modelName.hasSuffix(")") {
            let stem = listedName.dropLast()
            if modelName.hasPrefix(stem + ", ") {
                return true
            }
        }
        if modelName.replacingOccurrences(of: "Nov ", with: "") == listedName {
            return true
        }
        if listedName.replacingOccurrences(of: "Nov ", with: "") == modelName {
            return true
        }
        if let parts = orComponents(listedName), parts.contains(modelName) {
            return true
        }
        return false
    }

    private static func orComponents(_ listedName: String) -> [String]? {
        guard listedName.hasSuffix(")"), listedName.contains(" or "),
              let open = listedName.lastIndex(of: "(") else {
            return nil
        }
        let family = listedName[..<open].trimmingCharacters(in: .whitespaces)
        var inside = String(listedName[listedName.index(after: open)...])
        guard inside.hasSuffix(")") else { return nil }
        inside.removeLast()
        let parts = inside.components(separatedBy: " or ")
        guard parts.count == 2 else { return nil }
        return parts.map { "\(family) (\($0))" }
    }
}
