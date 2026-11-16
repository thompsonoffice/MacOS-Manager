import XCTest
@testable import MacOSManagerStoreCore

final class ReadinessTests: XCTestCase {
    private let gigabyte: Int64 = 1_000_000_000

    func testSpokenGigabytesUseDecimalUnits() {
        XCTAssertEqual(SpokenBytes.decimalGigabytes(12_500_000_000), "12.5 gigabytes")
        XCTAssertEqual(SpokenBytes.decimalGigabytes(18_500_000_000), "18.5 gigabytes")
        XCTAssertEqual(SpokenBytes.decimalGigabytes(35_500_000_000), "35.5 gigabytes")
        XCTAssertEqual(SpokenBytes.decimalGigabytes(44_500_000_000), "44.5 gigabytes")
        XCTAssertEqual(SpokenBytes.decimalGigabytes(80_000_000_000), "80 gigabytes")
        XCTAssertEqual(SpokenBytes.memoryGigabytes(8 * 1_073_741_824), "8 gigabytes")
        XCTAssertEqual(SpokenBytes.memoryGigabytes(4_000_000_000), "3.7 gigabytes")
    }

    func testCatalinaFreeSpaceUsesTheLowerFigureFromElCapitan10115Onward() {
        let mojave = installed(major: 10, minor: 14, patch: 6)
        let requirement = AppleRequirements.storage(releaseID: "10.15", marketingName: "macOS Catalina 10.15", installed: mojave)
        guard case .applicable(let storage) = requirement else {
            return XCTFail("Expected a stated Catalina requirement")
        }
        XCTAssertEqual(storage.requiredBytes, 12_500_000_000)
        XCTAssertEqual(storage.sourceURL, "https://support.apple.com/en-us/118458")

        let exact = evaluateCatalina(installed: mojave, freeSpace: .importantUsage(12_500_000_000), memory: fourGigabytes)
        XCTAssertEqual(exact.check("storage")?.outcome, .pass)
        XCTAssertTrue(exact.ready)

        let oneByteUnder = evaluateCatalina(installed: mojave, freeSpace: .importantUsage(12_500_000_000 - 1), memory: fourGigabytes)
        XCTAssertEqual(oneByteUnder.check("storage")?.outcome, .fail)
        XCTAssertFalse(oneByteUnder.ready)
        XCTAssertTrue(oneByteUnder.spokenSummary.hasPrefix("Not ready, here's why."))
    }

    func testCatalinaFreeSpaceUsesTheHigherFigureBeforeElCapitan10115() {
        let justBefore = installed(major: 10, minor: 11, patch: 4)
        let requirement = AppleRequirements.storage(releaseID: "10.15", marketingName: "macOS Catalina 10.15", installed: justBefore)
        guard case .applicable(let storage) = requirement else {
            return XCTFail("Expected the higher Catalina figure")
        }
        XCTAssertEqual(storage.requiredBytes, 18_500_000_000)
        XCTAssertFalse(AppleRequirements.isElCapitan10115OrLater(justBefore))
        XCTAssertTrue(AppleRequirements.isElCapitan10115OrLater(installed(major: 10, minor: 11, patch: 5)))

        let meetsCeiling = evaluateCatalina(installed: justBefore, freeSpace: .freeOnly(18_500_000_000), memory: fourGigabytes)
        XCTAssertEqual(meetsCeiling.check("storage")?.outcome, .pass)
        XCTAssertTrue(meetsCeiling.check("storage")?.detail.contains("free space only") == true)

        let underCeiling = evaluateCatalina(installed: justBefore, freeSpace: .importantUsage(18_500_000_000 - 1), memory: fourGigabytes)
        XCTAssertEqual(underCeiling.check("storage")?.outcome, .fail)
    }

    func testUnknownInstalledVersionUsesCatalinasHigherStorageFigure() {
        let requirement = AppleRequirements.storage(releaseID: "10.15", marketingName: "macOS Catalina 10.15", installed: nil)
        guard case .applicable(let storage) = requirement else {
            return XCTFail("Expected the higher figure when the installed version is unknown")
        }
        XCTAssertEqual(storage.requiredBytes, 18_500_000_000)
        let report = evaluateCatalina(installed: nil, freeSpace: .importantUsage(18_500_000_000), memory: fourGigabytes)
        XCTAssertEqual(report.check("storage")?.outcome, .pass)
        XCTAssertEqual(report.check("direction")?.outcome, .fail)
        XCTAssertFalse(report.ready)
    }

    func testBigSurFreeSpaceThresholdsFollowSierra() {
        let sierra = installed(major: 10, minor: 12, patch: 0)
        let elCapitan = installed(major: 10, minor: 11, patch: 6)
        XCTAssertTrue(AppleRequirements.isSierraOrLater(sierra))
        XCTAssertFalse(AppleRequirements.isSierraOrLater(elCapitan))

        let fromSierra = AppleRequirements.storage(releaseID: "11", marketingName: "macOS Big Sur 11", installed: sierra)
        guard case .applicable(let low) = fromSierra else { return XCTFail("Expected Big Sur's lower figure") }
        XCTAssertEqual(low.requiredBytes, 35_500_000_000)
        XCTAssertEqual(low.sourceURL, "https://support.apple.com/en-us/111980")

        let fromEarlier = AppleRequirements.storage(releaseID: "11", marketingName: "macOS Big Sur 11", installed: elCapitan)
        guard case .applicable(let high) = fromEarlier else { return XCTFail("Expected Big Sur's higher figure") }
        XCTAssertEqual(high.requiredBytes, 44_500_000_000)

        let meets = evaluate(
            releaseID: "11",
            marketingName: "macOS Big Sur 11",
            installed: sierra,
            freeSpace: .importantUsage(35_500_000_000),
            memory: fourGigabytes,
            power: ac(percent: 50)
        )
        XCTAssertEqual(meets.check("storage")?.outcome, .pass)
        XCTAssertTrue(meets.ready)
        XCTAssertTrue(meets.spokenSummary.hasPrefix("Ready."))

        let under = evaluate(
            releaseID: "11",
            marketingName: "macOS Big Sur 11",
            installed: sierra,
            freeSpace: .importantUsage(35_500_000_000 - 1),
            memory: fourGigabytes,
            power: ac(percent: 100)
        )
        XCTAssertEqual(under.check("storage")?.outcome, .fail)
        XCTAssertFalse(under.ready)
    }

    func testUnreadableFreeSpaceFailsOnlyWhenAppleStatesAFigure() {
        let catalina = evaluateCatalina(installed: installed(major: 10, minor: 15, patch: 7), freeSpace: .unreadable, memory: 8 * gigabyteU)
        XCTAssertEqual(catalina.check("storage")?.outcome, .fail)

        let sequoia = evaluate(
            releaseID: "15",
            marketingName: "macOS Sequoia 15",
            installed: installed(major: 14, minor: 0, patch: 0),
            freeSpace: .unreadable,
            memory: 8 * gigabyteU,
            power: noBattery()
        )
        XCTAssertEqual(sequoia.check("storage")?.outcome, .notStated)
        XCTAssertTrue(sequoia.check("storage")?.detail.contains("could not be read") == true)
        XCTAssertTrue(sequoia.check("storage")?.detail.contains("does not invent") == true)
    }

    func testNewerReleasesDoNotInventStorageOrMemoryNumbers() {
        let pages = ["12", "13", "14", "15", "26", "27"]
        let names = [
            "12": "macOS Monterey 12",
            "13": "macOS Ventura 13",
            "14": "macOS Sonoma 14",
            "15": "macOS Sequoia 15",
            "26": "macOS Tahoe 26",
            "27": "macOS 27 Golden Gate",
        ]
        for id in pages {
            let storage = AppleRequirements.storage(releaseID: id, marketingName: names[id] ?? id, installed: installed(major: 14, minor: 0, patch: 0))
            guard case .notStated = storage else {
                return XCTFail("\(id) should not have an invented storage number")
            }
            let memory = AppleRequirements.memory(releaseID: id, marketingName: names[id] ?? id)
            guard case .notStated = memory else {
                return XCTFail("\(id) should not have an invented memory number")
            }
            let report = evaluate(
                releaseID: id,
                marketingName: names[id] ?? id,
                installed: installed(major: 14, minor: 0, patch: 0),
                freeSpace: .importantUsage(1),
                memory: 1,
                power: noBattery()
            )
            XCTAssertEqual(report.check("storage")?.outcome, .notStated, id)
            XCTAssertEqual(report.check("memory")?.outcome, .notStated, id)
            if id == "12" || id == "13" {
                XCTAssertEqual(report.check("direction")?.outcome, .fail, id)
                XCTAssertFalse(report.ready, id)
            } else {
                XCTAssertEqual(report.check("direction")?.outcome, .pass, id)
                XCTAssertTrue(report.ready, id)
            }
        }
    }

    func testMemoryThresholdIsFourDecimalGigabytesWhenAppleStatesIt() {
        let mojave = installed(major: 10, minor: 14, patch: 6)
        XCTAssertEqual(AppleRequirements.statedMemoryBytes, fourGigabytes)
        let meets = evaluateCatalina(installed: mojave, freeSpace: .importantUsage(80 * gigabyte), memory: fourGigabytes)
        XCTAssertEqual(meets.check("memory")?.outcome, .pass)
        XCTAssertTrue(meets.check("memory")?.detail.contains("4 gigabytes") == true)

        let under = evaluateCatalina(installed: mojave, freeSpace: .importantUsage(80 * gigabyte), memory: fourGigabytes - 1)
        XCTAssertEqual(under.check("memory")?.outcome, .fail)
        XCTAssertFalse(under.ready)

        let missing = evaluateCatalina(installed: mojave, freeSpace: .importantUsage(80 * gigabyte), memory: nil)
        XCTAssertEqual(missing.check("memory")?.outcome, .fail)
    }

    func testBatteryStatesWarnOnBatteryAndBelowFiftyPercent() {
        let base = installed(major: 14, minor: 5, patch: 0)
        let pluggedInAtFifty = evaluate(
            releaseID: "15",
            marketingName: "macOS Sequoia 15",
            installed: base,
            freeSpace: .importantUsage(80 * gigabyte),
            memory: 8 * gigabyteU,
            power: ac(percent: 50)
        )
        XCTAssertEqual(pluggedInAtFifty.check("power")?.outcome, .pass)
        XCTAssertTrue(pluggedInAtFifty.ready)

        let pluggedInAtFortyNine = evaluate(
            releaseID: "15",
            marketingName: "macOS Sequoia 15",
            installed: base,
            freeSpace: .importantUsage(80 * gigabyte),
            memory: 8 * gigabyteU,
            power: ac(percent: 49)
        )
        XCTAssertEqual(pluggedInAtFortyNine.check("power")?.outcome, .fail)
        XCTAssertTrue(pluggedInAtFortyNine.check("power")?.detail.contains("Plug the Mac in") == true)
        XCTAssertFalse(pluggedInAtFortyNine.ready)

        let onBatteryHigh = evaluate(
            releaseID: "15",
            marketingName: "macOS Sequoia 15",
            installed: base,
            freeSpace: .importantUsage(80 * gigabyte),
            memory: 8 * gigabyteU,
            power: battery(percent: 90)
        )
        XCTAssertEqual(onBatteryHigh.check("power")?.outcome, .fail)
        XCTAssertTrue(onBatteryHigh.check("power")?.detail.contains("running on battery") == true)

        let onBatteryLow = evaluate(
            releaseID: "15",
            marketingName: "macOS Sequoia 15",
            installed: base,
            freeSpace: .importantUsage(80 * gigabyte),
            memory: 8 * gigabyteU,
            power: battery(percent: 20)
        )
        XCTAssertEqual(onBatteryLow.check("power")?.outcome, .fail)
        XCTAssertTrue(onBatteryLow.check("power")?.detail.contains("below 50 percent") == true)

        let onBatteryUnknownLevel = evaluate(
            releaseID: "15",
            marketingName: "macOS Sequoia 15",
            installed: base,
            freeSpace: .importantUsage(80 * gigabyte),
            memory: 8 * gigabyteU,
            power: [PowerSourceSnapshot(type: "InternalBattery", state: "Battery Power", currentCapacity: nil, maxCapacity: nil)]
        )
        XCTAssertEqual(onBatteryUnknownLevel.check("power")?.outcome, .fail)

        let desktop = evaluate(
            releaseID: "15",
            marketingName: "macOS Sequoia 15",
            installed: base,
            freeSpace: .importantUsage(80 * gigabyte),
            memory: 8 * gigabyteU,
            power: noBattery()
        )
        XCTAssertEqual(desktop.check("power")?.outcome, .pass)
        XCTAssertTrue(desktop.check("power")?.detail.contains("no internal battery") == true)
        XCTAssertTrue(desktop.ready)

        let unreadable = evaluate(
            releaseID: "15",
            marketingName: "macOS Sequoia 15",
            installed: base,
            freeSpace: .importantUsage(80 * gigabyte),
            memory: 8 * gigabyteU,
            power: nil
        )
        XCTAssertEqual(unreadable.check("power")?.outcome, .fail)
    }

    func testPowerClassificationIgnoresDesktopsUpsAndAbsentBatteries() {
        XCTAssertEqual(PowerSourceLogic.classify([]), .noBattery)
        XCTAssertEqual(PowerSourceLogic.classify(nil), .unreadable)
        XCTAssertEqual(
            PowerSourceLogic.classify([
                PowerSourceSnapshot(type: "UPS", state: "AC Power", currentCapacity: 100, maxCapacity: 100),
            ]),
            .noBattery
        )
        XCTAssertEqual(
            PowerSourceLogic.classify([
                PowerSourceSnapshot(type: "InternalBattery", state: "AC Power", currentCapacity: 40, maxCapacity: 100, isPresent: false),
            ]),
            .noBattery
        )
        XCTAssertEqual(PowerSourceLogic.percent(current: 50, max: 100), 50)
        XCTAssertEqual(PowerSourceLogic.percent(current: 49, max: 100), 49)
        XCTAssertEqual(PowerSourceLogic.percent(current: 1, max: 2), 50)
        XCTAssertEqual(PowerSourceLogic.percent(current: 100, max: 0), nil)
        XCTAssertEqual(
            PowerSourceLogic.classify([
                PowerSourceSnapshot(type: "InternalBattery", state: "AC Power", currentCapacity: 80, maxCapacity: 200),
            ]),
            .onACPower(percent: 40)
        )
        XCTAssertEqual(
            PowerSourceLogic.classify([
                PowerSourceSnapshot(type: "InternalBattery", state: "Battery Power", currentCapacity: 10, maxCapacity: 100),
                PowerSourceSnapshot(type: "InternalBattery", state: "AC Power", currentCapacity: 90, maxCapacity: 100),
            ]),
            .onBattery(percent: 10)
        )
    }

    func testUpgradeSameVersionAndDowngradeClassification() {
        let sonoma = installed(major: 14, minor: 6, patch: 1, raw: "Version 14.6.1")
        XCTAssertEqual(VersionDirectionLogic.classify(installed: sonoma, releaseID: "15"), .upgrade)
        XCTAssertEqual(VersionDirectionLogic.classify(installed: sonoma, releaseID: "14"), .sameVersion)
        XCTAssertEqual(VersionDirectionLogic.classify(installed: sonoma, releaseID: "13"), .downgrade)
        XCTAssertEqual(VersionDirectionLogic.classify(installed: sonoma, releaseID: "10.15"), .downgrade)
        XCTAssertEqual(VersionDirectionLogic.classify(installed: nil, releaseID: "15"), .unknown)
        XCTAssertEqual(VersionDirectionLogic.classify(installed: sonoma, releaseID: "not-a-release"), .unknown)

        let upgrade = evaluate(
            releaseID: "15",
            marketingName: "macOS Sequoia 15",
            installed: sonoma,
            freeSpace: .importantUsage(80 * gigabyte),
            memory: 8 * gigabyteU,
            power: noBattery()
        )
        XCTAssertEqual(upgrade.check("direction")?.outcome, .pass)
        XCTAssertTrue(upgrade.check("direction")?.detail.contains("would be an upgrade") == true)

        let same = evaluate(
            releaseID: "14",
            marketingName: "macOS Sonoma 14",
            installed: sonoma,
            freeSpace: .importantUsage(80 * gigabyte),
            memory: 8 * gigabyteU,
            power: noBattery()
        )
        XCTAssertEqual(same.check("direction")?.outcome, .pass)
        XCTAssertTrue(same.check("direction")?.detail.contains("same version") == true)
        XCTAssertTrue(same.ready)

        let downgrade = evaluate(
            releaseID: "13",
            marketingName: "macOS Ventura 13",
            installed: sonoma,
            freeSpace: .importantUsage(80 * gigabyte),
            memory: 8 * gigabyteU,
            power: ac(percent: 100)
        )
        XCTAssertEqual(downgrade.check("direction")?.outcome, .fail)
        XCTAssertFalse(downgrade.ready)
        XCTAssertTrue(downgrade.spokenSummary.hasPrefix("Not ready, here's why."))
        let detail = downgrade.check("direction")?.detail ?? ""
        XCTAssertTrue(detail.contains(DowngradeCopy.limitation))
        XCTAssertTrue(detail.contains("bootable USB installer"))
        XCTAssertTrue(detail.contains("Apple restore"))
        XCTAssertTrue(detail.contains("full edition"))
        XCTAssertTrue(detail.contains("separate product"))
        XCTAssertFalse(detail.contains("http"))
        XCTAssertFalse(detail.contains("$"))
        XCTAssertFalse(detail.localizedCaseInsensitiveContains("price"))
        XCTAssertFalse(detail.localizedCaseInsensitiveContains("buy"))
    }

    func testIncompatibleModelIsNotReadyEvenWhenTheMacHasRoom() {
        let report = ReadinessEvaluator.evaluate(
            releaseID: "27",
            marketingName: "macOS 27 Golden Gate",
            claim: .notListed,
            nearMissNames: ["Mac mini (M6 or M5 Pro)"],
            installed: installed(major: 15, minor: 1, patch: 0),
            freeSpace: .importantUsage(200 * gigabyte),
            memoryBytes: 16 * gigabyteU,
            powerSources: noBattery()
        )
        XCTAssertEqual(report.check("model")?.outcome, .fail)
        XCTAssertTrue(report.check("model")?.detail.contains("similar name") == true)
        XCTAssertFalse(report.ready)
        XCTAssertFalse(ModelCompatibility.isCompatible(.notListed))
        XCTAssertFalse(ModelCompatibility.isCompatible(.differsAcrossRecords))
        XCTAssertTrue(ModelCompatibility.isCompatible(.listedOnApplePage))
        XCTAssertTrue(ModelCompatibility.isCompatible(.coveredByAppleSiliconStatement))
    }

    func testChecklistUsesSystemSettingsAndPlainVoiceOverGuidance() throws {
        let catalog = try Catalog.loadBundled()
        let items = PreinstallChecklist.items(voiceOverGuideURL: catalog.rules.voiceOverGuideURL)
        XCTAssertEqual(items.map(\.id), ["backup", "power", "internet", "restarts", "voiceover"])
        let backup = try XCTUnwrap(items.first { $0.id == "backup" })
        XCTAssertTrue(backup.detail.contains("Time Machine"))
        XCTAssertEqual(backup.actions.first?.url, "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension")
        XCTAssertEqual(backup.actions.last?.url, ChecklistLinks.timeMachineHelp)
        XCTAssertTrue(backup.actions.last?.url.hasPrefix("https://support.apple.com/") == true)

        let voiceOver = try XCTUnwrap(items.first { $0.id == "voiceover" })
        XCTAssertTrue(voiceOver.detail.contains("Command-F5"))
        XCTAssertTrue(voiceOver.detail.contains("unavailable"))
        XCTAssertTrue(voiceOver.detail.contains("restarts"))
        XCTAssertEqual(voiceOver.actions.first?.url, catalog.rules.voiceOverGuideURL)

        let internet = try XCTUnwrap(items.first { $0.id == "internet" })
        XCTAssertTrue(internet.detail.localizedCaseInsensitiveContains("stable internet"))
        let restarts = try XCTUnwrap(items.first { $0.id == "restarts" })
        XCTAssertTrue(restarts.detail.localizedCaseInsensitiveContains("restart"))

        let blob = items.map { "\($0.title) \($0.detail) \($0.actions.map(\.title).joined(separator: " "))" }.joined(separator: " ")
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("buy"))
        XCTAssertFalse(blob.contains("$"))
        XCTAssertFalse(blob.contains("itch.io"))
        for action in items.flatMap(\.actions) {
            let allowed = action.url == ChecklistLinks.timeMachineSettings
                || action.url.hasPrefix("https://support.apple.com/")
            XCTAssertTrue(allowed, action.url)
        }
    }

    private var gigabyteU: UInt64 { 1_000_000_000 }
    private var fourGigabytes: UInt64 { 4 * 1_073_741_824 }

    private func installed(major: Int, minor: Int, patch: Int, raw: String? = nil) -> InstalledVersion {
        InstalledVersion(
            rawString: raw ?? "Version \(major).\(minor).\(patch)",
            major: major,
            minor: minor,
            patch: patch
        )
    }

    private func ac(percent: Int) -> [PowerSourceSnapshot] {
        [PowerSourceSnapshot(type: "InternalBattery", state: "AC Power", currentCapacity: percent, maxCapacity: 100)]
    }

    private func battery(percent: Int) -> [PowerSourceSnapshot] {
        [PowerSourceSnapshot(type: "InternalBattery", state: "Battery Power", currentCapacity: percent, maxCapacity: 100)]
    }

    private func noBattery() -> [PowerSourceSnapshot] {
        []
    }

    private func evaluateCatalina(
        installed: InstalledVersion?,
        freeSpace: FreeSpaceMeasurement,
        memory: UInt64?
    ) -> ReadinessReport {
        evaluate(
            releaseID: "10.15",
            marketingName: "macOS Catalina 10.15",
            installed: installed,
            freeSpace: freeSpace,
            memory: memory,
            power: noBattery()
        )
    }

    private func evaluate(
        releaseID: String,
        marketingName: String,
        installed: InstalledVersion?,
        freeSpace: FreeSpaceMeasurement,
        memory: UInt64?,
        power: [PowerSourceSnapshot]?
    ) -> ReadinessReport {
        ReadinessEvaluator.evaluate(
            releaseID: releaseID,
            marketingName: marketingName,
            claim: .listedOnApplePage,
            installed: installed,
            freeSpace: freeSpace,
            memoryBytes: memory,
            powerSources: power
        )
    }
}
