import Foundation

/// Whether the selected macOS is newer than, the same as, or older than the installed system.
public enum VersionDirection: String, Equatable, Sendable {
    case upgrade
    case sameVersion
    case downgrade
    case unknown
}

public enum VersionDirectionLogic {
    public static func classify(installed: InstalledVersion?, releaseID: String) -> VersionDirection {
        guard let installed else { return .unknown }
        switch installed.action(forReleaseID: releaseID) {
        case .upgrade:
            return .upgrade
        case .currentlyInstalled:
            return .sameVersion
        case .downgrade:
            return .downgrade
        case .unknown:
            return .unknown
        }
    }
}

/// Plain explanation shown when the selected macOS is older than the one installed.
public enum DowngradeCopy {
    public static let limitation =
        "Apple's installer can't install an older macOS over a newer one on the local drive. It needs a bootable USB installer or an Apple restore."
    public static let separateEdition =
        "The full edition of macOS Manager is a separate product that creates a bootable USB installer. This App Store edition does not include that feature."

    public static var spoken: String {
        "\(limitation) \(separateEdition)"
    }
}

/// Apple's published storage and memory figures. Missing figures stay missing.
public enum AppleRequirements {
    public static let catalinaStorageURL = "https://support.apple.com/en-us/118458"
    public static let bigSurStorageURL = "https://support.apple.com/en-us/111980"
    /// 12.5 GB, decimal, matching Finder and Apple's "12.5GB" wording.
    public static let catalinaStorageLow: Int64 = 12_500_000_000
    /// Apple's "up to 18.5GB" figure for a Catalina upgrade from a release earlier than OS X El Capitan 10.11.5.
    public static let catalinaStorageHigh: Int64 = 18_500_000_000
    public static let bigSurStorageLow: Int64 = 35_500_000_000
    public static let bigSurStorageHigh: Int64 = 44_500_000_000
    /// 4 GB of memory. Macs report installed memory in gibibytes, and Apple's "4GB of memory" matches that size.
    public static let statedMemoryBytes: UInt64 = 4 * 1_073_741_824
    public static let lowBatteryPercent = 50

    public static func storage(releaseID: String, marketingName: String, installed: InstalledVersion?) -> StorageLookup {
        switch releaseID {
        case "10.15":
            return catalinaStorage(installed: installed)
        case "11":
            return bigSurStorage(installed: installed)
        default:
            return .notStated(detail: notStatedStorage(marketingName))
        }
    }

    public static func memory(releaseID: String, marketingName: String) -> MemoryLookup {
        switch releaseID {
        case "10.15":
            return .stated(
                bytes: statedMemoryBytes,
                sourceURL: catalinaStorageURL,
                detail: "Apple's macOS Catalina technical specifications state 4 gigabytes of memory."
            )
        case "11":
            return .stated(
                bytes: statedMemoryBytes,
                sourceURL: bigSurStorageURL,
                detail: "Apple's macOS Big Sur technical specifications state 4 gigabytes of memory."
            )
        default:
            return .notStated(
                detail: "Apple's current support pages for \(marketingName) do not state a minimum amount of memory. This check does not invent one."
            )
        }
    }

    public static func isElCapitan10115OrLater(_ installed: InstalledVersion) -> Bool {
        if installed.major > 10 { return true }
        if installed.major < 10 { return false }
        if installed.minor > 11 { return true }
        if installed.minor < 11 { return false }
        return installed.patch >= 5
    }

    public static func isSierraOrLater(_ installed: InstalledVersion) -> Bool {
        if installed.major > 10 { return true }
        return installed.major == 10 && installed.minor >= 12
    }

    private static func catalinaStorage(installed: InstalledVersion?) -> StorageLookup {
        let both =
            "Apple's macOS Catalina technical specifications state 12.5 gigabytes of available storage when upgrading from OS X El Capitan 10.11.5 or later, and up to 18.5 gigabytes when upgrading from an earlier release."
        if let installed {
            if isElCapitan10115OrLater(installed) {
                return .applicable(ApplicableStorage(
                    requiredBytes: catalinaStorageLow,
                    sourceURL: catalinaStorageURL,
                    detail: "\(both) This Mac is already on OS X El Capitan 10.11.5 or later, so this check uses 12.5 gigabytes."
                ))
            }
            return .applicable(ApplicableStorage(
                requiredBytes: catalinaStorageHigh,
                sourceURL: catalinaStorageURL,
                detail: "\(both) This Mac is on an earlier release, so this check uses Apple's higher figure of 18.5 gigabytes."
            ))
        }
        return .applicable(ApplicableStorage(
            requiredBytes: catalinaStorageHigh,
            sourceURL: catalinaStorageURL,
            detail: "\(both) The installed macOS version was not read, so this check uses the higher figure of 18.5 gigabytes."
        ))
    }

    private static func bigSurStorage(installed: InstalledVersion?) -> StorageLookup {
        let both =
            "Apple's macOS Big Sur technical specifications state 35.5 gigabytes of available storage when upgrading from macOS Sierra or later, and up to 44.5 gigabytes when upgrading from an earlier release."
        if let installed {
            if isSierraOrLater(installed) {
                return .applicable(ApplicableStorage(
                    requiredBytes: bigSurStorageLow,
                    sourceURL: bigSurStorageURL,
                    detail: "\(both) This Mac is already on macOS Sierra or later, so this check uses 35.5 gigabytes."
                ))
            }
            return .applicable(ApplicableStorage(
                requiredBytes: bigSurStorageHigh,
                sourceURL: bigSurStorageURL,
                detail: "\(both) This Mac is on an earlier release, so this check uses Apple's higher figure of 44.5 gigabytes."
            ))
        }
        return .applicable(ApplicableStorage(
            requiredBytes: bigSurStorageHigh,
            sourceURL: bigSurStorageURL,
            detail: "\(both) The installed macOS version was not read, so this check uses the higher figure of 44.5 gigabytes."
        ))
    }

    private static func notStatedStorage(_ marketingName: String) -> String {
        "Apple's current support pages for \(marketingName) do not state how much free space the install needs. This check does not invent a number."
    }
}

public struct ApplicableStorage: Equatable, Sendable {
    public var requiredBytes: Int64
    public var sourceURL: String
    public var detail: String

    public init(requiredBytes: Int64, sourceURL: String, detail: String) {
        self.requiredBytes = requiredBytes
        self.sourceURL = sourceURL
        self.detail = detail
    }
}

public enum StorageLookup: Equatable, Sendable {
    case applicable(ApplicableStorage)
    case notStated(detail: String)
}

public enum MemoryLookup: Equatable, Sendable {
    case stated(bytes: UInt64, sourceURL: String, detail: String)
    case notStated(detail: String)
}

/// Free space read from the startup volume with URL resource values, not raw disk access.
public enum FreeSpaceMeasurement: Equatable, Sendable {
    /// Includes space macOS says it can free. This is the figure closest to Storage settings.
    case importantUsage(Int64)
    /// Free bytes only. Purgeable space may not be included.
    case freeOnly(Int64)
    case unreadable

    public var bytes: Int64? {
        switch self {
        case .importantUsage(let bytes), .freeOnly(let bytes):
            return bytes
        case .unreadable:
            return nil
        }
    }
}

/// One power source, already copied out of IOKit so the decision can be tested without a Mac.
public struct PowerSourceSnapshot: Equatable, Sendable {
    public var type: String
    public var state: String
    public var currentCapacity: Int?
    public var maxCapacity: Int?
    public var isPresent: Bool

    public init(
        type: String,
        state: String,
        currentCapacity: Int?,
        maxCapacity: Int?,
        isPresent: Bool = true
    ) {
        self.type = type
        self.state = state
        self.currentCapacity = currentCapacity
        self.maxCapacity = maxCapacity
        self.isPresent = isPresent
    }
}

public enum PowerClassification: Equatable, Sendable {
    case noBattery
    case onACPower(percent: Int?)
    case onBattery(percent: Int?)
    case unreadable
}

public enum PowerSourceLogic {
    /// `nil` means the power-source list could not be read. An empty list means no battery was reported.
    public static func classify(_ sources: [PowerSourceSnapshot]?) -> PowerClassification {
        guard let sources else { return .unreadable }
        let batteries = sources.filter { source in
            source.isPresent && source.type.range(of: "battery", options: .caseInsensitive) != nil
        }
        guard !batteries.isEmpty else { return .noBattery }
        let lowest = batteries.compactMap { percent(current: $0.currentCapacity, max: $0.maxCapacity) }.min()
        if batteries.contains(where: { isBatteryPower($0.state) }) {
            return .onBattery(percent: lowest)
        }
        if batteries.allSatisfy({ isACPower($0.state) }) {
            return .onACPower(percent: lowest)
        }
        return .unreadable
    }

    public static func percent(current: Int?, max: Int?) -> Int? {
        guard let current, let max, max > 0, current >= 0 else { return nil }
        return min(100, (current * 100) / max)
    }

    private static func isBatteryPower(_ state: String) -> Bool {
        state.caseInsensitiveCompare("Battery Power") == .orderedSame
    }

    private static func isACPower(_ state: String) -> Bool {
        state.caseInsensitiveCompare("AC Power") == .orderedSame
    }
}

public enum SpokenBytes {
    public static func decimalGigabytes(_ bytes: Int64) -> String {
        spoken(Decimal(bytes) / Decimal(1_000_000_000))
    }

    public static func memoryGigabytes(_ bytes: UInt64) -> String {
        let gibibytes = Decimal(bytes) / Decimal(1_073_741_824)
        return spoken(gibibytes)
    }

    private static func spoken(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        let digits = formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
        return "\(digits) gigabytes"
    }
}

public enum CheckOutcome: String, Equatable, Sendable {
    case pass
    case fail
    case notStated
}

public struct ReadinessCheck: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var outcome: CheckOutcome
    public var detail: String
    public var sourceURL: String?
    public var sourceButtonTitle: String?

    public init(
        id: String,
        title: String,
        outcome: CheckOutcome,
        detail: String,
        sourceURL: String? = nil,
        sourceButtonTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.outcome = outcome
        self.detail = detail
        self.sourceURL = sourceURL
        self.sourceButtonTitle = sourceButtonTitle
    }
}

public struct ReadinessReport: Equatable, Sendable {
    public var marketingName: String
    public var ready: Bool
    public var headline: String
    public var checks: [ReadinessCheck]
    public var spokenSummary: String

    public func check(_ id: String) -> ReadinessCheck? {
        checks.first { $0.id == id }
    }
}

public enum ModelCompatibility {
    public static func isCompatible(_ claim: VersionClaim) -> Bool {
        claim == .listedOnApplePage || claim == .coveredByAppleSiliconStatement
    }

    public static func explanation(claim: VersionClaim, marketingName: String, nearMissNames: [String]) -> String {
        switch claim {
        case .listedOnApplePage:
            return "Apple's compatibility page lists this Mac's model name for \(marketingName)."
        case .coveredByAppleSiliconStatement:
            return "Apple's Apple silicon statement covers this Mac for \(marketingName). The exact model name does not have to appear on the list when that statement applies."
        case .differsAcrossRecords:
            return "Apple's records for this model identifier do not agree about \(marketingName). This check does not treat the Mac as compatible."
        case .noPerModelPage:
            return "This catalog has no per-model compatibility page for \(marketingName), so this check does not treat the Mac as compatible."
        case .notListed:
            var sentence = "Apple's compatibility table does not list this exact model for \(marketingName)."
            if nearMissNames.isEmpty {
                sentence += " A similar name is not treated as a match."
            } else {
                let names = nearMissNames.joined(separator: ", ")
                sentence += " Apple lists a similar name, \(names), and that similar name is not treated as a match."
            }
            return sentence
        }
    }
}

public enum ReadinessEvaluator {
    public static func evaluate(
        releaseID: String,
        marketingName: String,
        claim: VersionClaim,
        nearMissNames: [String] = [],
        installed: InstalledVersion?,
        freeSpace: FreeSpaceMeasurement,
        memoryBytes: UInt64?,
        powerSources: [PowerSourceSnapshot]?
    ) -> ReadinessReport {
        let checks = [
            modelCheck(claim: claim, marketingName: marketingName, nearMissNames: nearMissNames),
            storageCheck(releaseID: releaseID, marketingName: marketingName, installed: installed, freeSpace: freeSpace),
            memoryCheck(releaseID: releaseID, marketingName: marketingName, memoryBytes: memoryBytes),
            directionCheck(releaseID: releaseID, marketingName: marketingName, installed: installed),
            powerCheck(PowerSourceLogic.classify(powerSources)),
        ]
        let ready = !checks.contains { $0.outcome == .fail }
        let headline = ready ? "Ready" : "Not ready, here's why"
        let lead = ready ? "Ready." : "Not ready, here's why."
        let spoken = ([lead] + checks.map(\.detail)).joined(separator: " ")
        return ReadinessReport(
            marketingName: marketingName,
            ready: ready,
            headline: headline,
            checks: checks,
            spokenSummary: spoken
        )
    }

    private static func modelCheck(claim: VersionClaim, marketingName: String, nearMissNames: [String]) -> ReadinessCheck {
        let compatible = ModelCompatibility.isCompatible(claim)
        return ReadinessCheck(
            id: "model",
            title: "Model",
            outcome: compatible ? .pass : .fail,
            detail: ModelCompatibility.explanation(claim: claim, marketingName: marketingName, nearMissNames: nearMissNames)
        )
    }

    private static func storageCheck(
        releaseID: String,
        marketingName: String,
        installed: InstalledVersion?,
        freeSpace: FreeSpaceMeasurement
    ) -> ReadinessCheck {
        let lookup = AppleRequirements.storage(releaseID: releaseID, marketingName: marketingName, installed: installed)
        switch lookup {
        case .notStated(let detail):
            return ReadinessCheck(
                id: "storage",
                title: "Free space",
                outcome: .notStated,
                detail: detail + " " + measuredSpaceSentence(freeSpace)
            )
        case .applicable(let requirement):
            guard let available = freeSpace.bytes else {
                return ReadinessCheck(
                    id: "storage",
                    title: "Free space",
                    outcome: .fail,
                    detail: "\(requirement.detail) Free space on the startup volume could not be read, so this check cannot compare it with Apple's figure.",
                    sourceURL: requirement.sourceURL,
                    sourceButtonTitle: "Open Apple's technical specifications"
                )
            }
            let comparison: String
            let outcome: CheckOutcome
            if available >= requirement.requiredBytes {
                comparison = "Free space on the startup volume is \(SpokenBytes.decimalGigabytes(available)). That meets Apple's stated requirement of \(SpokenBytes.decimalGigabytes(requirement.requiredBytes))."
                outcome = .pass
            } else {
                comparison = "Free space on the startup volume is \(SpokenBytes.decimalGigabytes(available)). That is less than Apple's stated requirement of \(SpokenBytes.decimalGigabytes(requirement.requiredBytes))."
                outcome = .fail
            }
            return ReadinessCheck(
                id: "storage",
                title: "Free space",
                outcome: outcome,
                detail: "\(requirement.detail) \(comparison) \(measurementNote(freeSpace))",
                sourceURL: requirement.sourceURL,
                sourceButtonTitle: "Open Apple's technical specifications"
            )
        }
    }

    private static func memoryCheck(releaseID: String, marketingName: String, memoryBytes: UInt64?) -> ReadinessCheck {
        switch AppleRequirements.memory(releaseID: releaseID, marketingName: marketingName) {
        case .notStated(let detail):
            let measured: String
            if let memoryBytes {
                measured = " This Mac reports \(SpokenBytes.memoryGigabytes(memoryBytes)) of memory."
            } else {
                measured = " Memory could not be read."
            }
            return ReadinessCheck(id: "memory", title: "Memory", outcome: .notStated, detail: detail + measured)
        case .stated(let bytes, let sourceURL, let detail):
            guard let memoryBytes else {
                return ReadinessCheck(
                    id: "memory",
                    title: "Memory",
                    outcome: .fail,
                    detail: "\(detail) This Mac's memory could not be read, so this check cannot confirm it.",
                    sourceURL: sourceURL,
                    sourceButtonTitle: "Open Apple's technical specifications"
                )
            }
            if memoryBytes >= bytes {
                return ReadinessCheck(
                    id: "memory",
                    title: "Memory",
                    outcome: .pass,
                    detail: "\(detail) This Mac reports \(SpokenBytes.memoryGigabytes(memoryBytes)) of memory, which meets that requirement.",
                    sourceURL: sourceURL,
                    sourceButtonTitle: "Open Apple's technical specifications"
                )
            }
            return ReadinessCheck(
                id: "memory",
                title: "Memory",
                outcome: .fail,
                detail: "\(detail) This Mac reports \(SpokenBytes.memoryGigabytes(memoryBytes)) of memory, which is less than that requirement.",
                sourceURL: sourceURL,
                sourceButtonTitle: "Open Apple's technical specifications"
            )
        }
    }

    private static func directionCheck(releaseID: String, marketingName: String, installed: InstalledVersion?) -> ReadinessCheck {
        let direction = VersionDirectionLogic.classify(installed: installed, releaseID: releaseID)
        let running = installed?.rawString
        switch direction {
        case .upgrade:
            return ReadinessCheck(
                id: "direction",
                title: "Upgrade, same version, or downgrade",
                outcome: .pass,
                detail: "This Mac is running \(running ?? "an older macOS"). Choosing \(marketingName) would be an upgrade."
            )
        case .sameVersion:
            return ReadinessCheck(
                id: "direction",
                title: "Upgrade, same version, or downgrade",
                outcome: .pass,
                detail: "This Mac is running \(running ?? "this version"). Choosing \(marketingName) is the same version of macOS. It is not an upgrade or a downgrade."
            )
        case .downgrade:
            return ReadinessCheck(
                id: "direction",
                title: "Upgrade, same version, or downgrade",
                outcome: .fail,
                detail: "This Mac is running \(running ?? "a newer macOS"). Choosing \(marketingName) would be a downgrade. \(DowngradeCopy.spoken)"
            )
        case .unknown:
            return ReadinessCheck(
                id: "direction",
                title: "Upgrade, same version, or downgrade",
                outcome: .fail,
                detail: "The installed macOS version was not read, so this check cannot say whether choosing \(marketingName) would be an upgrade, the same version, or a downgrade."
            )
        }
    }

    private static let powerWarningNote =
        "This app warns when a Mac is on battery or below 50 percent. That percentage is this app's warning, not a figure published by Apple."

    private static func powerCheck(_ power: PowerClassification) -> ReadinessCheck {
        let limit = AppleRequirements.lowBatteryPercent
        switch power {
        case .noBattery:
            return ReadinessCheck(
                id: "power",
                title: "Power",
                outcome: .pass,
                detail: "This Mac has no internal battery, so there is no battery warning. A desktop gets its power from the power cord. \(powerWarningNote)"
            )
        case .onACPower(let percent):
            guard let percent else {
                return ReadinessCheck(
                    id: "power",
                    title: "Power",
                    outcome: .fail,
                    detail: "The Mac is plugged in, but the battery level could not be read. This check warns when the battery is below \(limit) percent, so it cannot say the Mac is ready. \(powerWarningNote)"
                )
            }
            if percent < limit {
                return ReadinessCheck(
                    id: "power",
                    title: "Power",
                    outcome: .fail,
                    detail: "The battery is at \(percent) percent, which is below \(limit) percent. Plug the Mac in, or leave it plugged in, until the battery reaches at least \(limit) percent. \(powerWarningNote)"
                )
            }
            return ReadinessCheck(
                id: "power",
                title: "Power",
                outcome: .pass,
                detail: "The Mac is plugged in and the battery is at \(percent) percent, which is not below \(limit) percent. \(powerWarningNote)"
            )
        case .onBattery(let percent):
            if let percent, percent < limit {
                return ReadinessCheck(
                    id: "power",
                    title: "Power",
                    outcome: .fail,
                    detail: "The Mac is running on battery power. The battery is at \(percent) percent, which is below \(limit) percent. Plug it in before you install. \(powerWarningNote)"
                )
            }
            if let percent {
                return ReadinessCheck(
                    id: "power",
                    title: "Power",
                    outcome: .fail,
                    detail: "The Mac is running on battery power. The battery is at \(percent) percent. Plug it in before you install. \(powerWarningNote)"
                )
            }
            return ReadinessCheck(
                id: "power",
                title: "Power",
                outcome: .fail,
                detail: "The Mac is running on battery power. The battery level could not be read. Plug it in before you install. \(powerWarningNote)"
            )
        case .unreadable:
            return ReadinessCheck(
                id: "power",
                title: "Power",
                outcome: .fail,
                detail: "Power could not be read. If this Mac has a battery, plug it in before you install. \(powerWarningNote)"
            )
        }
    }

    private static func measuredSpaceSentence(_ freeSpace: FreeSpaceMeasurement) -> String {
        guard let bytes = freeSpace.bytes else {
            return "Free space on the startup volume could not be read."
        }
        return "Free space on the startup volume is \(SpokenBytes.decimalGigabytes(bytes)). \(measurementNote(freeSpace))"
    }

    private static func measurementNote(_ freeSpace: FreeSpaceMeasurement) -> String {
        switch freeSpace {
        case .importantUsage:
            return "The number includes space macOS says it can free."
        case .freeOnly:
            return "The number is free space only. It may not include space macOS can free."
        case .unreadable:
            return ""
        }
    }
}

public struct ChecklistAction: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var url: String
    public var hint: String

    public init(id: String, title: String, url: String, hint: String) {
        self.id = id
        self.title = title
        self.url = url
        self.hint = hint
    }
}

public struct ChecklistItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var actions: [ChecklistAction]

    public init(id: String, title: String, detail: String, actions: [ChecklistAction] = []) {
        self.id = id
        self.title = title
        self.detail = detail
        self.actions = actions
    }
}

/// Addresses the checklist may open. System Settings uses Apple's preference URL. Help pages are https.
public enum ChecklistLinks {
    public static let timeMachineSettings = "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension"
    public static let timeMachineHelp = "https://support.apple.com/guide/mac-help/back-up-your-mac-with-time-machine-mh35860/mac"
}

public enum PreinstallChecklist {
    public static func items(voiceOverGuideURL: String) -> [ChecklistItem] {
        [
            ChecklistItem(
                id: "backup",
                title: "Back up this Mac",
                detail: "Before you install, back up with Time Machine. Apple recommends a backup before an upgrade. The first button opens Time Machine in System Settings. This app does not create the backup. If System Settings does not open, use Apple's Time Machine guide.",
                actions: [
                    ChecklistAction(
                        id: "open-time-machine-settings",
                        title: "Open Time Machine in System Settings",
                        url: ChecklistLinks.timeMachineSettings,
                        hint: "Opens Time Machine in System Settings. This app does not run a backup and does not change the disk."
                    ),
                    ChecklistAction(
                        id: "open-time-machine-guide",
                        title: "Open Apple's Time Machine guide",
                        url: ChecklistLinks.timeMachineHelp,
                        hint: "Opens Apple's Mac User Guide page about backing up with Time Machine. This app does not run a backup."
                    ),
                ]
            ),
            ChecklistItem(
                id: "power",
                title: "Stay plugged in",
                detail: "If this Mac has a battery, plug it in and leave it plugged in until installation finishes. A desktop Mac should stay connected to its power cord."
            ),
            ChecklistItem(
                id: "internet",
                title: "Use a stable internet connection",
                detail: "Apple says the installer needs a stable internet connection to download macOS and to get firmware and other information for this Mac. Stay connected until the Mac has finished restarting."
            ),
            ChecklistItem(
                id: "restarts",
                title: "Expect restarts",
                detail: "The Mac may restart more than once. The screen may show a progress bar or go blank. That can be normal. Leave the Mac alone until it reaches the desktop or asks you to continue setup."
            ),
            ChecklistItem(
                id: "voiceover",
                title: "VoiceOver during installation",
                detail: "VoiceOver may be unavailable for a short time when the Mac restarts. To turn VoiceOver on or off, press Command-F5. If the Mac has Touch ID, you can press and hold the Command key, then press Touch ID three times. After a restart, press Command-F5 again if VoiceOver does not speak.",
                actions: [
                    ChecklistAction(
                        id: "open-voiceover-guide",
                        title: "Open Apple's VoiceOver on and off guide",
                        url: voiceOverGuideURL,
                        hint: "Opens Apple's guide for turning VoiceOver on or off. This app does not change VoiceOver settings."
                    ),
                ]
            ),
        ]
    }
}
