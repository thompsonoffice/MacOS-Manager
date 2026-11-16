import XCTest
@testable import MacOSManagerStoreCore

final class CompatibilityLookupTests: XCTestCase {
    private var catalog: Catalog!

    override func setUpWithError() throws {
        catalog = try Catalog.loadBundled()
    }

    func testCatalogErrorIsSpokenInPlainLanguage() {
        let missing: Error = CatalogError.missingResource
        XCTAssertEqual(
            missing.localizedDescription,
            "The Apple facts catalog is missing from the app resources."
        )
        let invalid = CatalogError.invalidJSON("Example.")
        XCTAssertEqual((invalid as Error).localizedDescription, invalid.description)
        XCTAssertFalse(missing.localizedDescription.contains("could not be completed"))
    }

    func testCatalogDateAndScope() {
        XCTAssertEqual(catalog.retrieved, "2026-11-06")
        XCTAssertEqual(catalog.compatibilityReleases.map(\.id), ["27", "26", "15", "14", "13", "12", "11", "10.15"])
        XCTAssertGreaterThan(catalog.models.count, 140)
    }

    func testEveryCompatibilityNameIsExactOrANearMiss() {
        let modelNames = Set(catalog.models.map(\.name))
        for release in catalog.releases where release.hasPerModelCompatibilityPage {
            for listed in release.listedModelNames {
                if modelNames.contains(listed) {
                    continue
                }
                let near = catalog.models.contains {
                    ModelNameComparison.isNearMiss(modelName: $0.name, listedName: listed)
                }
                XCTAssertTrue(near, "\(release.id) lists \(listed), which matches no model and is not a near miss")
            }
        }
    }

    func testMacBookProM6IsListedForGoldenGateAndNotTahoe() throws {
        let report = CompatibilityReport.build(catalog: catalog, query: .identifier("mac18,1"))
        XCTAssertTrue(report.found)
        XCTAssertEqual(report.records.map(\.name), ["MacBook Pro (14-inch, M6)"])
        XCTAssertEqual(report.records.first?.identifiers, ["Mac18,1"])
        XCTAssertEqual(report.processor.label, "Apple silicon")
        XCTAssertEqual(claim("27", report), .listedOnApplePage)
        XCTAssertEqual(claim("26", report), .notListed)
        if case .stated(let text, _) = report.newest {
            XCTAssertEqual(text, "macOS 27 Golden Gate")
        } else {
            XCTFail("Expected a newest system statement")
        }
        XCTAssertTrue(report.spokenSummary.contains("does not run softwareupdate"))
        XCTAssertTrue(report.spokenSummary.contains("does not erase"))
        XCTAssertTrue(report.briefAnnouncement.contains("MacBook Pro (14-inch, M6)"))
        XCTAssertFalse(report.briefAnnouncement.contains("erase"))
        XCTAssertTrue(report.factoryOperatingSystem.contains("not in this catalog"))
        XCTAssertEqual(report.compatibleVersions.map(\.releaseID).first, "27")
        XCTAssertFalse(report.compatibleVersions.contains { $0.releaseID == "26" })
    }

    func testIntel2019MacBookProIsTahoeAndNotGoldenGateByName() {
        let report = CompatibilityReport.build(catalog: catalog, query: .identifier("MacBookPro16,1"))
        XCTAssertEqual(report.records.map(\.name), ["MacBook Pro (16-inch, 2019)"])
        XCTAssertEqual(report.processor.label, "Intel")
        XCTAssertEqual(report.t2.label, "Listed by Apple as a T2 Mac")
        XCTAssertEqual(claim("26", report), .listedOnApplePage)
        XCTAssertEqual(claim("27", report), .notListed)
        XCTAssertNil(version("27", report)?.blanketStatement)
        XCTAssertTrue(report.compatibleVersions.contains { $0.releaseID == "26" })
        XCTAssertFalse(report.compatibleVersions.contains { $0.releaseID == "27" })
    }

    func testM6MacMiniUsesTheAppleSiliconStatementWithoutAnExactName() {
        let report = CompatibilityReport.build(catalog: catalog, query: .identifier("Mac18,5"))
        XCTAssertEqual(report.records.first?.name, "Mac mini (M6)")
        XCTAssertEqual(claim("27", report), .coveredByAppleSiliconStatement)
        XCTAssertEqual(
            version("27", report)?.nearMissNames,
            ["Mac mini (M6 or M5 Pro)"]
        )
        XCTAssertTrue(version("27", report)?.blanketStatement?.contains("any Mac with Apple silicon") == true)
        XCTAssertEqual(claim("26", report), .notListed)
        XCTAssertTrue(report.compatibleVersions.contains { $0.releaseID == "27" && $0.claim == .coveredByAppleSiliconStatement })
    }

    func testSharedMacProIdentifierDoesNotCollapseTheRackAndTower() {
        let report = CompatibilityReport.build(catalog: catalog, query: .identifier("Mac14,8"))
        XCTAssertEqual(
            Set(report.records.map(\.name)),
            ["Mac Pro (2023)", "Mac Pro (Rack, 2023)"]
        )
        XCTAssertEqual(claim("27", report), .differsAcrossRecords)
        XCTAssertTrue(report.spokenSummary.contains("does not pick"))
        XCTAssertFalse(report.compatibleVersions.contains { $0.releaseID == "27" })
    }

    func testShared2018And2019IdentifierKeepsBothNames() {
        let report = CompatibilityReport.build(catalog: catalog, query: .identifier("MacBookPro15,1"))
        XCTAssertEqual(report.records.count, 2)
        XCTAssertEqual(report.processor.label, "Intel")
        XCTAssertEqual(claim("15", report), .listedOnApplePage)
        if case .stated(let text, _) = report.newest {
            XCTAssertEqual(text, "macOS Sequoia")
        } else {
            XCTFail("Both records name Sequoia")
        }
    }

    func testSonomaPageShorterIMacNameIsNotAMatch() {
        let report = CompatibilityReport.build(catalog: catalog, query: .identifier("Mac15,5"))
        XCTAssertEqual(report.records.first?.name, "iMac (24-inch, 2023, Four ports)")
        XCTAssertEqual(claim("14", report), .notListed)
        XCTAssertEqual(version("14", report)?.nearMissNames, ["iMac (24-inch, 2023)"])
        XCTAssertEqual(claim("15", report), .listedOnApplePage)
    }

    func testNovember2023NameIsNotTreatedAsTheJanuary2023Name() {
        let report = CompatibilityReport.build(catalog: catalog, query: .identifier("Mac15,3"))
        XCTAssertEqual(report.records.first?.name, "MacBook Pro (14-inch, Nov 2023)")
        XCTAssertEqual(claim("27", report), .coveredByAppleSiliconStatement)
        XCTAssertEqual(version("27", report)?.nearMissNames, ["MacBook Pro (14-inch, 2023)"])
        XCTAssertNotEqual(claim("26", report), .listedOnApplePage)
    }

    func testUnknownIdentifierClaimsNothing() {
        let report = CompatibilityReport.build(catalog: catalog, query: .identifier("NotAMac9,9"))
        XCTAssertFalse(report.found)
        XCTAssertTrue(report.versions.isEmpty)
        XCTAssertTrue(report.compatibleVersions.isEmpty)
        XCTAssertTrue(report.spokenSummary.contains("Nothing is claimed"))
    }

    func testPartNumberFindsTheM6MacBookPro() {
        let report = CompatibilityReport.build(catalog: catalog, query: .partNumber("MHWT4LL/A"))
        XCTAssertEqual(report.records.map(\.identifiers), [["Mac18,1"]])
        let catalogForm = CompatibilityReport.build(catalog: catalog, query: .partNumber("mhwT4xx/A"))
        XCTAssertEqual(catalogForm.records.map(\.name), report.records.map(\.name))
    }

    func testContradictoryMachineReadingSuppressesTheSiliconStatement() {
        let reading = MachineReading(
            modelIdentifier: "Mac18,5",
            machine: "x86_64",
            operatingSystemVersion: "Version 15.8.2 (Build 24G123)",
            probeMethod: "fixture",
            sandboxStatus: "not verified",
            probeError: nil
        )
        let report = CompatibilityReport.build(
            catalog: catalog,
            query: .identifier("Mac18,5"),
            reading: reading
        )
        XCTAssertEqual(report.architecture, .contradictsCatalog)
        XCTAssertEqual(claim("27", report), .notListed)
        XCTAssertNil(version("27", report)?.blanketStatement)
        XCTAssertTrue(report.spokenSummary.contains("Version 15.8.2"))
    }

    func testArm64ReadingAgreesWithTheM6MacBookPro() {
        let reading = MachineReading(
            modelIdentifier: "Mac18,1",
            machine: "arm64",
            operatingSystemVersion: nil,
            probeMethod: "fixture",
            sandboxStatus: "not verified",
            probeError: nil
        )
        let report = CompatibilityReport.build(catalog: catalog, query: .identifier("Mac18,1"), reading: reading)
        XCTAssertEqual(report.architecture, .consistent)
        XCTAssertEqual(claim("27", report), .listedOnApplePage)
        XCTAssertTrue(report.spokenSummary.contains("not verified"))
        XCTAssertTrue(report.briefAnnouncement.contains("not verified"))
    }

    func testMacBookAirExceptions() {
        let m1 = CompatibilityReport.build(catalog: catalog, query: .identifier("MacBookAir10,1"))
        XCTAssertEqual(m1.processor.label, "Apple silicon")
        XCTAssertEqual(m1.t2.label, "Not a T2 Mac")
        let intel2020 = CompatibilityReport.build(catalog: catalog, query: .identifier("MacBookAir9,1"))
        XCTAssertEqual(intel2020.records.first?.name, "MacBook Air (Retina, 13-inch, 2020)")
        XCTAssertEqual(intel2020.processor.label, "Intel")
        XCTAssertEqual(intel2020.t2.label, "Listed by Apple as a T2 Mac")
    }

    func testMarketingNameLookupIsExact() {
        let exact = CompatibilityReport.build(
            catalog: catalog,
            query: .marketingName("MacBook Neo (13-inch, A18 Pro)")
        )
        XCTAssertTrue(exact.found)
        XCTAssertEqual(exact.records.first?.identifiers, [])
        XCTAssertEqual(exact.processor.label, "Apple silicon")
        XCTAssertEqual(claim("27", exact), .listedOnApplePage)
        XCTAssertEqual(claim("26", exact), .listedOnApplePage)
        let shorter = CompatibilityReport.build(catalog: catalog, query: .marketingName("MacBook Neo"))
        XCTAssertFalse(shorter.found)
    }

    func testMojaveFootnoteIsKeptForThe2012MacPro() {
        let report = CompatibilityReport.build(catalog: catalog, query: .identifier("MacPro5,1"))
        if case .stated(let text, let footnote) = report.newest {
            XCTAssertEqual(text, "macOS Mojave")
            XCTAssertTrue(footnote?.contains("Metal-capable graphics card") == true)
        } else {
            XCTFail("Expected the Mojave statement and footnote")
        }
        XCTAssertGreaterThan(report.records.count, 1)
    }

    func testAppStoreRouteOpensAppleHttpsProductPage() throws {
        let sequoia = try XCTUnwrap(DownloadRoute.officialRoute(catalog: catalog, releaseID: "15"))
        XCTAssertEqual(sequoia.kind, .appStore)
        XCTAssertEqual(sequoia.url, "https://apps.apple.com/app/macos-sequoia/id6596773750")
        XCTAssertTrue(sequoia.explanation.contains("Apple handles the download"))
        XCTAssertFalse(sequoia.url.contains("cdn-apple.com"))
    }

    func testGoldenGateAndTahoeOpenSupportArticlesNotInstallers() throws {
        let golden = try XCTUnwrap(DownloadRoute.officialRoute(catalog: catalog, releaseID: "27"))
        XCTAssertEqual(golden.kind, .supportArticle)
        XCTAssertEqual(golden.url, "https://support.apple.com/en-us/127455")
        let tahoe = try XCTUnwrap(DownloadRoute.officialRoute(catalog: catalog, releaseID: "26"))
        XCTAssertEqual(tahoe.kind, .supportArticle)
        XCTAssertEqual(tahoe.url, "https://support.apple.com/en-us/122867")
    }

    func testOlderVersionsOpenTheDownloadArticleNotADiskImage() throws {
        let lion = try XCTUnwrap(DownloadRoute.officialRoute(catalog: catalog, releaseID: "10.7"))
        XCTAssertEqual(lion.kind, .supportArticle)
        XCTAssertEqual(lion.url, catalog.rules.downloadArticleURL)
        XCTAssertFalse(lion.url.contains(".dmg"))
        let mojave = try XCTUnwrap(DownloadRoute.officialRoute(catalog: catalog, releaseID: "10.14"))
        XCTAssertEqual(mojave.kind, .appStore)
        XCTAssertEqual(mojave.url, "https://apps.apple.com/app/macos-mojave/id1398502828")
    }

    func testStoreCatalogOmitsInstallerDiskImagesAndSettingsDeepLinks() {
        for release in catalog.releases {
            XCTAssertNil(release.download.diskImageURL, "Store catalog must not ship \(release.id) disk image URL")
        }
        XCTAssertTrue(catalog.rules.softwareUpdateSettingsURL.isEmpty)
        XCTAssertEqual(catalog.rules.downloadArticleURL, "https://support.apple.com/en-us/102662")
    }

    func testInstalledVersionMarksTheMatchingCatalogRelease() {
        let sequoia = InstalledVersion(
            version: OperatingSystemVersion(majorVersion: 15, minorVersion: 8, patchVersion: 2),
            rawString: "Version 15.8.2 (Build 24G123)"
        )
        XCTAssertEqual(sequoia.catalogReleaseID, "15")
        XCTAssertTrue(sequoia.marks(releaseID: "15"))
        XCTAssertFalse(sequoia.marks(releaseID: "14"))
        XCTAssertTrue(sequoia.spoken.contains("currently running"))

        let tahoe = InstalledVersion(
            version: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0),
            rawString: "Version 26.1"
        )
        XCTAssertTrue(tahoe.marks(releaseID: "26"))
        XCTAssertFalse(tahoe.marks(releaseID: "27"))

        let catalina = InstalledVersion(
            version: OperatingSystemVersion(majorVersion: 10, minorVersion: 15, patchVersion: 8),
            rawString: "Version 10.15.8"
        )
        XCTAssertEqual(catalina.catalogReleaseID, "10.15")
        XCTAssertTrue(catalina.marks(releaseID: "10.15"))
        XCTAssertFalse(catalina.marks(releaseID: "10.14"))
    }

    func testInstalledVersionUpgradeAndDowngradeActions() {
        let sonoma = InstalledVersion(
            version: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0),
            rawString: "Version 14.0"
        )
        XCTAssertEqual(sonoma.action(forReleaseID: "14"), .currentlyInstalled)
        XCTAssertEqual(sonoma.action(forReleaseID: "15"), .upgrade)
        XCTAssertEqual(sonoma.action(forReleaseID: "27"), .upgrade)
        XCTAssertEqual(sonoma.action(forReleaseID: "13"), .downgrade)
        XCTAssertEqual(sonoma.action(forReleaseID: "10.15"), .downgrade)
    }

    func testUnknownRouteIDReturnsNil() {
        XCTAssertNil(DownloadRoute.officialRoute(catalog: catalog, releaseID: "not-a-release"))
    }

    private func claim(_ id: String, _ report: CompatibilityReport) -> VersionClaim? {
        version(id, report)?.claim
    }

    private func version(_ id: String, _ report: CompatibilityReport) -> VersionAssessment? {
        report.versions.first { $0.releaseID == id }
    }
}
