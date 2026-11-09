import XCTest
@testable import MacOSManagerCore

final class InstallerDownloadTests: XCTestCase {
    private var catalog: Catalog!

    override func setUpWithError() throws {
        catalog = try Catalog.loadBundled()
    }

    func testCatalogParserKeepsTheVenturaInstallAssistantAndDropsOtherPackages() throws {
        let packages = try SUCatalogParser.parse(Data(fixtureCatalog.utf8))
        XCTAssertEqual(packages.map(\.productKey), ["093-22004"])
        let ventura = try XCTUnwrap(packages.first)
        XCTAssertEqual(
            ventura.packageURL.absoluteString,
            "https://swcdn.apple.com/content/downloads/09/46/093-22004-A_QNZEDC334I/phigx2zvoggml6sh79my4y51fnvgy8hix4/InstallAssistant.pkg"
        )
        XCTAssertEqual(ventura.expectedSize, 12_205_110_942)
        XCTAssertEqual(ventura.sharedSupportIdentifier, "com.apple.pkg.InstallAssistant.macOSVentura")
        XCTAssertEqual(
            ventura.distributionURL?.absoluteString,
            "https://swdist.apple.com/content/downloads/09/46/093-22004-A_QNZEDC334I/phigx2zvoggml6sh79my4y51fnvgy8hix4/093-22004.English.dist"
        )
        XCTAssertNil(ventura.version)
    }

    func testCatalogParserRejectsCompressedDataAndHostileAddresses() throws {
        XCTAssertThrowsError(try SUCatalogParser.parse(Data([0x1f, 0x8b, 0x08, 0x00]))) { error in
            XCTAssertEqual(error as? SUCatalogError, .stillCompressed)
        }
        XCTAssertFalse(AppleDownloadHosts.isInstallAssistantPackageURL(URL(string: "http://swcdn.apple.com/InstallAssistant.pkg")!))
        XCTAssertFalse(AppleDownloadHosts.isInstallAssistantPackageURL(URL(string: "https://swcdn.apple.com.evil.example/InstallAssistant.pkg")!))
        XCTAssertFalse(AppleDownloadHosts.isInstallAssistantPackageURL(URL(string: "https://user:pass@swcdn.apple.com/a/InstallAssistant.pkg")!))
        XCTAssertFalse(AppleDownloadHosts.isInstallAssistantPackageURL(URL(string: "https://swcdn.apple.com/a/InstallAssistant.pkg?x=1")!))
        XCTAssertFalse(AppleDownloadHosts.isInstallAssistantPackageURL(URL(string: "https://swcdn.apple.com/a/Info.plist")!))
        XCTAssertTrue(AppleDownloadHosts.isInstallAssistantPackageURL(URL(string: "https://SWCDN.APPLE.COM/content/downloads/x/InstallAssistant.pkg")!))
        XCTAssertTrue(AppleCatalogList.mergedCatalogURLs.allSatisfy(AppleDownloadHosts.isCatalogURL))
        XCTAssertFalse(SUCatalogParser.isProductKey("../etc"))
        XCTAssertFalse(SUCatalogParser.isProductKey("093 22004"))
    }

    func testDistributionParserReadsAuxinfoAndIgnoresADecoyVersion() {
        let metadata = DistributionDocumentParser.parse(fixtureDistribution)
        XCTAssertEqual(metadata?.version, "13.7.8")
        XCTAssertEqual(metadata?.build, "22H730")
        XCTAssertEqual(metadata?.title, "macOS Ventura")
        XCTAssertNil(DistributionDocumentParser.parse("<title>Nope</title><script>VERSION 1.2.3</script>"))
    }

    func testOffersVenturaForThe2018MacMiniAndRefusesItForTheM6MacBookPro() throws {
        let packages = venturaAndSequoiaPackages()
        let mini = CompatibilityReport.build(catalog: catalog, query: .identifier("Macmini8,1"))
        let miniOffers = InstallerOffers.make(catalog: catalog, hostReport: mini, packages: packages)
        let ventura = try XCTUnwrap(miniOffers.offers.first { $0.releaseID == "13" })
        XCTAssertEqual(ventura.version, "13.7.8")
        XCTAssertEqual(ventura.build, "22H730")
        XCTAssertEqual(ventura.productKey, "093-22004")
        XCTAssertEqual(ventura.marketingName, "macOS Ventura 13")
        XCTAssertEqual(try XCTUnwrap(miniOffers.offers.first { $0.releaseID == "15" }).version, "15.6.1")
        XCTAssertTrue(miniOffers.refusals.contains { $0.plainLanguage.contains("macOS Sonoma 14") && $0.plainLanguage.contains("live catalog") })

        let m6 = CompatibilityReport.build(catalog: catalog, query: .identifier("Mac18,1"))
        let m6Offers = InstallerOffers.make(catalog: catalog, hostReport: m6, packages: packages)
        XCTAssertFalse(m6Offers.offers.contains { $0.releaseID == "13" })
        let refusal = try XCTUnwrap(m6Offers.refusals.first { $0.id == "13" })
        XCTAssertTrue(refusal.plainLanguage.contains("MacBook Pro (14-inch, M6)"))
        XCTAssertTrue(refusal.plainLanguage.contains("13.7.8"))
        XCTAssertTrue(refusal.plainLanguage.contains("093-22004"))
        XCTAssertTrue(refusal.plainLanguage.contains("cannot be installed on this Mac"))
    }

    func testOfferUsesTheLiveVersionRatherThanAStaleBundledBuild() throws {
        let older = samplePackage(key: "093-11111", version: "13.7.6", build: "22H610", size: 12_000_000_000)
        let newer = samplePackage(key: "093-22004", version: "13.7.10", build: "22H900", size: 12_205_110_942)
        let mini = CompatibilityReport.build(catalog: catalog, query: .identifier("Macmini8,1"))
        let offers = InstallerOffers.make(catalog: catalog, hostReport: mini, packages: [older, newer])
        let ventura = try XCTUnwrap(offers.offers.first { $0.releaseID == "13" })
        XCTAssertEqual(ventura.version, "13.7.10")
        XCTAssertEqual(ventura.productKey, "093-22004")
        XCTAssertNotEqual(ventura.version, catalog.releases.first { $0.id == "13" }?.latestBuild)
    }

    func testUnknownHostIsExplainedAndADifferentLookupIsNamed() {
        let missing = InstallerOffers.hostReport(
            catalog: catalog,
            reading: MachineReading(
                modelIdentifier: nil,
                machine: nil,
                operatingSystemVersion: nil,
                probeMethod: "fixture",
                sandboxStatus: "not verified",
                probeError: "sysctl did not return hw.model."
            )
        )
        let offers = InstallerOffers.make(catalog: catalog, hostReport: missing, packages: venturaAndSequoiaPackages())
        XCTAssertTrue(offers.offers.isEmpty)
        XCTAssertTrue(offers.refusals.first?.plainLanguage.contains("sysctl did not return hw.model") == true)
        XCTAssertTrue(offers.refusals.first?.plainLanguage.contains("No installer was offered") == true)

        let host = CompatibilityReport.build(catalog: catalog, query: .identifier("Macmini8,1"))
        let lookup = CompatibilityReport.build(catalog: catalog, query: .identifier("Mac18,1"))
        let sentence = InstallerOffers.differentMacExplanation(host: host, lookup: lookup)
        XCTAssertEqual(
            sentence,
            "You looked up MacBook Pro (14-inch, M6). Installers on this screen are for this Mac, Mac mini (2018)."
        )
        XCTAssertNil(InstallerOffers.differentMacExplanation(host: host, lookup: host))
        XCTAssertEqual(
            InstallerOffers.bundledVersionIfInstallable(catalog: catalog, hostReport: host, releaseID: "13"),
            "13.7.8"
        )
        XCTAssertNil(InstallerOffers.bundledVersionIfInstallable(catalog: catalog, hostReport: lookup, releaseID: "13"))
    }

    func testSoftwareUpdateSignatureErrorMapsToPlainLanguageAndSelectsTheCatalogPackage() throws {
        let message = "The digital signature on the update is missing or invalid. Error Domain=SUErrorDomain Code=203 UserInfo={SUErrorUpdateProductKey=093-22004, SUErrorUpdateServerName=swscan.apple.com}"
        let spoken = InstallErrorMapping.softwareUpdate(exitCode: 1, message: message, willTryDirectDownload: true)
        XCTAssertTrue(spoken.plainLanguage.localizedCaseInsensitiveContains("signature"))
        XCTAssertTrue(spoken.plainLanguage.contains("093-22004"))
        XCTAssertTrue(spoken.plainLanguage.contains("swscan.apple.com"))
        XCTAssertTrue(spoken.plainLanguage.contains("download Apple's installer package"))
        XCTAssertFalse(spoken.plainLanguage.contains("SUErrorDomain"))
        XCTAssertTrue(spoken.rawDetail.contains("SUErrorDomain"))
        XCTAssertTrue(spoken.rawDetail.contains("Code=203"))
        XCTAssertTrue(spoken.allowsDirectPackageFallback)
        XCTAssertFalse(spoken.allowsSoftwareUpdateFallback)

        let stopped = InstallErrorMapping.softwareUpdate(exitCode: 1, message: message, willTryDirectDownload: false)
        XCTAssertTrue(stopped.plainLanguage.contains("was not installed"))
        XCTAssertFalse(stopped.plainLanguage.contains("SUErrorDomain"))

        let packages = venturaAndSequoiaPackages()
        let error = WorkflowError.commandFailed(exitCode: 1, message: message)
        let fallback = InstallerAttemptOrder.packageAfterSoftwareUpdate(
            requestedVersion: "15.6.1",
            error: error,
            packages: packages
        )
        XCTAssertEqual(fallback?.productKey, "093-22004")
        XCTAssertEqual(fallback?.version, "13.7.8")

        let byVersion = InstallerAttemptOrder.packageAfterSoftwareUpdate(
            requestedVersion: "15.6.1",
            error: WorkflowError.commandFailed(exitCode: 2, message: "Could not download."),
            packages: packages
        )
        XCTAssertEqual(byVersion?.productKey, "140-85388")
        XCTAssertNil(InstallerAttemptOrder.packageAfterSoftwareUpdate(
            requestedVersion: "13.7.8",
            error: WorkflowError.cancelled,
            packages: packages
        ))

        let other = InstallErrorMapping.softwareUpdate(exitCode: 9, message: "Failed to find installer", willTryDirectDownload: true)
        XCTAssertFalse(other.plainLanguage.localizedCaseInsensitiveContains("signature"))
        XCTAssertTrue(other.allowsDirectPackageFallback)
        XCTAssertTrue(other.rawDetail.contains("Failed to find installer"))
    }

    func testAttemptOrderPrefersTheDirectPackageAndStopsAfterABadSignature() throws {
        let package = try XCTUnwrap(venturaAndSequoiaPackages().first { $0.productKey == "093-22004" })
        let attempts = InstallerAttemptOrder.preferred(package: package)
        guard case .direct(let first) = attempts.first else {
            return XCTFail("Expected the catalog package first")
        }
        XCTAssertEqual(first.productKey, "093-22004")
        guard case .softwareUpdate(let version) = attempts.last else {
            return XCTFail("Expected softwareupdate as the fallback")
        }
        XCTAssertEqual(version, "13.7.8")

        let signature = PackageSignatureCheck.evaluate(exitCode: 1, output: "Status: no signature")
        XCTAssertFalse(signature.accepted)
        XCTAssertFalse(InstallerAttemptOrder.mayContinue(after: signature.spoken, to: .softwareUpdate(version: "13.7.8")))

        let transport = SpokenInstallError(
            plainLanguage: "The download stopped.",
            rawDetail: "The network connection failed.",
            allowsSoftwareUpdateFallback: true,
            allowsDirectPackageFallback: false
        )
        XCTAssertTrue(InstallerAttemptOrder.mayContinue(after: transport, to: .softwareUpdate(version: "13.7.8")))
        XCTAssertFalse(InstallerAttemptOrder.mayContinue(after: transport, to: .direct(package)))

        let softwareUpdateFailure = InstallErrorMapping.softwareUpdate(exitCode: 1, message: "Code=203", willTryDirectDownload: true)
        XCTAssertTrue(InstallerAttemptOrder.mayContinue(after: softwareUpdateFailure, to: .direct(package)))
    }

    func testSignatureCheckRequiresAppleSoftwareAndAnAppleRoot() {
        let trusted = PackageSignatureCheck.evaluate(exitCode: 0, output: trustedPkgutil)
        XCTAssertTrue(trusted.accepted)
        XCTAssertTrue(trusted.spoken.plainLanguage.contains("Apple Software"))
        XCTAssertEqual(PackageSignatureCheck.certificateNames(in: trustedPkgutil).count, 3)

        let developer = PackageSignatureCheck.evaluate(exitCode: 0, output: developerPkgutil)
        XCTAssertFalse(developer.accepted)
        XCTAssertTrue(developer.spoken.plainLanguage.contains("Apple Software"))
        XCTAssertTrue(developer.spoken.rawDetail.contains("Developer ID Installer"))

        let unsigned = PackageSignatureCheck.evaluate(exitCode: 1, output: "Package \"InstallAssistant.pkg\":\n   Status: no signature\n")
        XCTAssertFalse(unsigned.accepted)
        XCTAssertTrue(unsigned.spoken.plainLanguage.contains("no") || unsigned.spoken.plainLanguage.contains("did not report"))
        XCTAssertFalse(unsigned.spoken.allowsSoftwareUpdateFallback)
    }

    func testSizeCheckAndProgressText() {
        XCTAssertNil(PackageSizeCheck.evaluate(expected: 12_205_110_942, actual: 12_205_110_942))
        let mismatch = PackageSizeCheck.evaluate(expected: 12_205_110_942, actual: 100)
        XCTAssertTrue(mismatch?.plainLanguage.contains("does not match") == true)
        XCTAssertTrue(mismatch?.rawDetail.contains("12205110942") == true)
        XCTAssertTrue(mismatch?.allowsSoftwareUpdateFallback == true)
        let tiny = PackageSizeCheck.evaluate(expected: 10, actual: 10)
        XCTAssertTrue(tiny?.plainLanguage.contains("too small") == true)
        XCTAssertFalse(tiny?.allowsSoftwareUpdateFallback == true)

        let line = DownloadProgressText.line(bytes: 6_102_555_471, expected: 12_205_110_942)
        XCTAssertTrue(line.contains("50 percent"))
        XCTAssertTrue(line.contains("12.2 GB"))
    }

    func testInstallerCommandsUseSeparateArgumentsAndRequireAnAdministratorForInstall() throws {
        let signature = try InstallerCommands.checkSignature(packagePath: "/tmp/nested/InstallAssistant.pkg").get()
        XCTAssertEqual(signature.executable, "/usr/sbin/pkgutil")
        XCTAssertEqual(signature.arguments, ["--check-signature", "/tmp/nested/InstallAssistant.pkg"])
        XCTAssertFalse(signature.needsAdministratorPrompt)

        let install = try InstallerCommands.install(packagePath: "/tmp/nested/InstallAssistant.pkg").get()
        XCTAssertEqual(install.executable, "/usr/sbin/installer")
        XCTAssertEqual(install.arguments, ["-pkg", "/tmp/nested/InstallAssistant.pkg", "-target", "/"])
        XCTAssertTrue(install.needsAdministratorPrompt)
        XCTAssertNil(install.standardInput)

        XCTAssertThrowsError(try InstallerCommands.install(packagePath: "/tmp/Other.pkg").get())
        XCTAssertThrowsError(try InstallerCommands.install(packagePath: "InstallAssistant.pkg").get())
        let command = try InstallWorkflow.softwareUpdateCommand(version: "13.7.8").get()
        XCTAssertEqual(command.arguments, ["--fetch-full-installer", "--full-installer-version", "13.7.8"])
        XCTAssertThrowsError(try InstallWorkflow.softwareUpdateCommand(version: "13.7.8;rm -rf /").get()) { error in
            XCTAssertEqual(error as? WorkflowError, .versionStringRejected)
        }
    }

    func testPresentedCommandFailureKeepsTheRawTextOutOfTheSummary() {
        let spoken = InstallErrorMapping.present(
            WorkflowError.commandFailed(exitCode: 203, message: "Error Domain=SUErrorDomain Code=203")
        )
        XCTAssertFalse(spoken.plainLanguage.contains("SUErrorDomain"))
        XCTAssertTrue(spoken.rawDetail.contains("SUErrorDomain"))
        XCTAssertTrue(spoken.plainLanguage.contains("203"))
    }

    private func venturaAndSequoiaPackages() -> [CatalogInstallerPackage] {
        [
            samplePackage(key: "093-22004", version: "13.7.8", build: "22H730", size: 12_205_110_942),
            samplePackage(key: "140-85388", version: "15.6.1", build: "24G80", size: 15_000_000_000),
        ]
    }

    private func samplePackage(key: String, version: String, build: String, size: Int64) -> CatalogInstallerPackage {
        CatalogInstallerPackage(
            productKey: key,
            packageURL: URL(string: "https://swcdn.apple.com/content/downloads/\(key)/InstallAssistant.pkg")!,
            expectedSize: size,
            distributionURL: URL(string: "https://swdist.apple.com/content/downloads/\(key)/\(key).English.dist"),
            sharedSupportIdentifier: "com.apple.pkg.InstallAssistant",
            version: version,
            build: build,
            title: "macOS"
        )
    }

    private let fixtureCatalog = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>Products</key>
    <dict>
      <key>093-22004</key>
      <dict>
        <key>ExtendedMetaInfo</key>
        <dict>
          <key>InstallAssistantPackageIdentifiers</key>
          <dict>
            <key>SharedSupport</key>
            <string>com.apple.pkg.InstallAssistant.macOSVentura</string>
            <key>OSInstall</key>
            <string>com.apple.mpkg.OSInstall</string>
          </dict>
        </dict>
        <key>Packages</key>
        <array>
          <dict>
            <key>URL</key>
            <string>https://swcdn.apple.com/content/downloads/09/46/093-22004-A_QNZEDC334I/phigx2zvoggml6sh79my4y51fnvgy8hix4/Info.plist</string>
            <key>Size</key>
            <integer>5450</integer>
          </dict>
          <dict>
            <key>URL</key>
            <string>https://swcdn.apple.com/content/downloads/09/46/093-22004-A_QNZEDC334I/phigx2zvoggml6sh79my4y51fnvgy8hix4/InstallAssistant.pkg</string>
            <key>Size</key>
            <integer>12205110942</integer>
          </dict>
          <dict>
            <key>URL</key>
            <string>https://evil.example/InstallAssistant.pkg</string>
            <key>Size</key>
            <integer>12205110942</integer>
          </dict>
        </array>
        <key>Distributions</key>
        <dict>
          <key>English</key>
          <string>https://swdist.apple.com/content/downloads/09/46/093-22004-A_QNZEDC334I/phigx2zvoggml6sh79my4y51fnvgy8hix4/093-22004.English.dist</string>
        </dict>
      </dict>
      <key>000-99999</key>
      <dict>
        <key>ExtendedMetaInfo</key>
        <dict>
          <key>InstallAssistantPackageIdentifiers</key>
          <dict>
            <key>SharedSupport</key>
            <string>com.apple.pkg.SomethingElse</string>
          </dict>
        </dict>
        <key>Packages</key>
        <array>
          <dict>
            <key>URL</key>
            <string>https://swcdn.apple.com/content/downloads/x/InstallAssistant.pkg</string>
            <key>Size</key>
            <integer>9000000000</integer>
          </dict>
        </array>
      </dict>
      <key>../tmp</key>
      <dict>
        <key>Packages</key>
        <array>
          <dict>
            <key>URL</key>
            <string>https://swcdn.apple.com/content/downloads/x/InstallAssistant.pkg</string>
            <key>Size</key>
            <integer>9000000000</integer>
          </dict>
        </array>
      </dict>
    </dict>
    </dict></plist>
    """

    private let fixtureDistribution = """
    <?xml version="1.0" encoding="utf-8"?>
    <installer-gui-script minSpecVersion="2">
        <title>macOS Ventura</title>
        <script>var decoy = "9.9.9";</script>
        <auxinfo>
            <dict>
                <key>BUILD</key>
                <string>22H730</string>
                <key>VERSION</key>
                <string>13.7.8</string>
            </dict>
        </auxinfo>
        <choice id="InstallAssistantAuto" versStr="9.9.9" title="macOS Ventura"></choice>
    </installer-gui-script>
    """

    private let trustedPkgutil = """
    Package "InstallAssistant.pkg":
       Status: signed by a certificate trusted for this system
       Certificate Chain:
        1. Software Update
           SHA256 Fingerprint: AA
        2. Apple Software Update Certification Authority
           SHA256 Fingerprint: BB
        3. Apple Root CA
           SHA256 Fingerprint: CC
    """

    private let developerPkgutil = """
    Package "InstallAssistant.pkg":
       Status: signed by a developer certificate issued by Apple for distribution
       Certificate Chain:
        1. Developer ID Installer: Example (TEAMID)
        2. Developer ID Certification Authority
        3. Apple Root CA
    """
}
