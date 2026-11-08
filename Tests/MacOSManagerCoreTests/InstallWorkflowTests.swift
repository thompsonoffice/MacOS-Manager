import XCTest
@testable import MacOSManagerCore

final class InstallWorkflowTests: XCTestCase {
    private var catalog: Catalog!
    private var root: URL!

    override func setUpWithError() throws {
        catalog = try Catalog.loadBundled()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("macos-manager-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testPreferredReleaseStaysOnlyWhenStillOffered() {
        let silicon = CompatibilityReport.build(catalog: catalog, query: .identifier("Mac18,1"))
        XCTAssertEqual(InstallWorkflow.preferredReleaseID("27", in: silicon), "27")
        XCTAssertEqual(InstallWorkflow.preferredReleaseID("26", in: silicon), "27")
        let intel = CompatibilityReport.build(catalog: catalog, query: .identifier("MacBookPro16,1"))
        XCTAssertEqual(InstallWorkflow.preferredReleaseID("27", in: intel), "26")
        XCTAssertEqual(InstallWorkflow.preferredReleaseID("26", in: intel), "26")
    }

    func testSelectableVersionsFollowTheReport() {
        let report = CompatibilityReport.build(catalog: catalog, query: .identifier("Mac18,1"))
        let offered = InstallWorkflow.selectableVersions(report).map(\.releaseID)
        XCTAssertTrue(offered.contains("27"))
        XCTAssertFalse(offered.contains("26"))
        let mini = CompatibilityReport.build(catalog: catalog, query: .identifier("Mac18,5"))
        XCTAssertTrue(InstallWorkflow.selectableVersions(mini).contains { $0.releaseID == "27" && $0.claim == .coveredByAppleSiliconStatement })
    }

    func testSoftwareUpdateReceivesOnlyTheCatalogBuild() throws {
        let report = CompatibilityReport.build(catalog: catalog, query: .identifier("Mac18,1"))
        let golden = try XCTUnwrap(report.versions.first { $0.releaseID == "27" })
        let command = try InstallWorkflow.fetchFullInstaller(assessment: golden, catalog: catalog).get()
        XCTAssertEqual(command.executable, "/usr/sbin/softwareupdate")
        XCTAssertEqual(command.arguments, ["--fetch-full-installer", "--full-installer-version", "27.2"])
        XCTAssertFalse(command.needsAdministratorPrompt)
        XCTAssertNil(command.standardInput)

        var hostile = golden
        hostile.latestBuild = "27.2;touch /tmp/pwned"
        XCTAssertThrowsError(try InstallWorkflow.fetchFullInstaller(assessment: hostile, catalog: catalog).get()) { error in
            XCTAssertEqual(error as? WorkflowError, .versionStringRejected)
        }
        let unlisted = try XCTUnwrap(report.versions.first { $0.releaseID == "26" })
        XCTAssertThrowsError(try InstallWorkflow.fetchFullInstaller(assessment: unlisted, catalog: catalog).get()) { error in
            XCTAssertEqual(error as? WorkflowError, .versionNotOffered)
        }
    }

    func testFullInstallerMustKeepCreateInstallMediaInsideTheApp() throws {
        let app = try makeInstaller(name: "Install macOS Tahoe")
        let checked = try InstallWorkflow.checkInstaller(at: app).get()
        XCTAssertEqual(checked.displayName, "Install macOS Tahoe")
        XCTAssertTrue(checked.createInstallMediaPath.hasSuffix("/Contents/Resources/createinstallmedia"))

        let outside = root.appendingPathComponent("outside-tool")
        try "#!/bin/sh\nexit 0\n".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outside.path)
        let linked = app.appendingPathComponent("Contents/Resources/createinstallmedia")
        try FileManager.default.removeItem(at: linked)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        XCTAssertThrowsError(try InstallWorkflow.checkInstaller(at: app).get()) { error in
            XCTAssertEqual(error as? WorkflowError, .installerToolEscapesBundle)
        }
    }

    func testLocalInstallAndUSBAreDifferentCommands() throws {
        let installer = try InstallWorkflow.checkInstaller(at: try makeInstaller(name: "Install macOS Tahoe")).get()
        let startup = volume(id: "disk0s2", whole: "disk0", name: "Macintosh HD", mount: "/", internalDisk: true, removable: false, startup: true)
        let usb = volume(id: "disk4s1", whole: "disk4", name: "Target", mount: "/Volumes/Target", internalDisk: false, removable: true, startup: false)
        XCTAssertEqual(DiskSurveyParser.startupVolume(in: [usb, startup])?.deviceIdentifier, "disk0s2")
        XCTAssertEqual(DiskSurveyParser.spokenCapacity(32_000_000_000), "32.0 GB")
        XCTAssertEqual(DiskSurveyParser.spokenCapacity(0), "size not reported")

        let local = InstallWorkflow.prepareOpen(installer)
        XCTAssertEqual(local.executable, "/usr/bin/open")
        XCTAssertEqual(local.arguments, [installer.appPath])
        XCTAssertFalse(local.arguments.contains("--volume"))
        XCTAssertFalse(local.executable.contains("createinstallmedia"))

        let media = try InstallWorkflow.prepareUSB(
            installer: installer,
            volume: usb,
            typedName: "Target",
            includeInternalNonStartup: false
        ).get()
        XCTAssertTrue(media.executable.hasSuffix("createinstallmedia"))
        XCTAssertEqual(media.arguments, ["--volume", "/Volumes/Target"])
        XCTAssertNotEqual(local.executable, media.executable)
        let warning = InstallWarnings.usbConfirmation(volumeName: "Target", capacity: "32.0 GB")
        XCTAssertTrue(warning.hasPrefix(InstallWarnings.usbDataLoss))
        XCTAssertTrue(warning.contains("Target"))
        XCTAssertTrue(warning.contains("32.0 GB"))
        XCTAssertTrue(warning.contains("installer"))
    }

    func testOpenInstallerHasNoEraseArguments() throws {
        let checked = try InstallWorkflow.checkInstaller(at: try makeInstaller(name: "Install macOS Sequoia")).get()
        let command = InstallWorkflow.prepareOpen(checked)
        XCTAssertEqual(command.arguments, [checked.appPath])
        XCTAssertFalse(command.needsAdministratorPrompt)
        XCTAssertNil(command.standardInput)
        let joined = command.arguments.joined(separator: " ")
        XCTAssertFalse(joined.contains("eraseinstall"))
        XCTAssertFalse(joined.contains("startosinstall"))
        XCTAssertFalse(joined.contains("--volume"))
    }

    func testUSBPlanRejectsStartupAndInternalDisksUntilTheNameMatches() throws {
        let installer = try InstallWorkflow.checkInstaller(at: try makeInstaller(name: "Install macOS Tahoe")).get()
        let external = volume(id: "disk4s1", whole: "disk4", name: "Target", mount: "/Volumes/Target", internalDisk: false, removable: true, startup: false)
        XCTAssertThrowsError(try InstallWorkflow.prepareUSB(installer: installer, volume: external, typedName: "target", includeInternalNonStartup: false).get()) { error in
            XCTAssertEqual(error as? WorkflowError, .confirmationMismatch)
        }

        let startup = volume(id: "disk0s2", whole: "disk0", name: "Macintosh HD", mount: "/", internalDisk: true, removable: false, startup: true)
        XCTAssertThrowsError(try InstallWorkflow.prepareUSB(installer: installer, volume: startup, typedName: "Macintosh HD", includeInternalNonStartup: true).get()) { error in
            XCTAssertEqual(error as? WorkflowError, .startupDiskBlocked)
        }
        let internalDisk = volume(id: "disk3s1", whole: "disk3", name: "Spare", mount: "/Volumes/Spare", internalDisk: true, removable: false, startup: false)
        XCTAssertThrowsError(try InstallWorkflow.prepareUSB(installer: installer, volume: internalDisk, typedName: "Spare", includeInternalNonStartup: false).get()) { error in
            XCTAssertEqual(error as? WorkflowError, .internalDiskHidden)
        }
        let allowedInternal = try InstallWorkflow.prepareUSB(installer: installer, volume: internalDisk, typedName: "Spare", includeInternalNonStartup: true).get()
        XCTAssertEqual(allowedInternal.arguments, ["--volume", "/Volumes/Spare"])

        let unknown = volume(id: "disk8s1", whole: "disk8", name: "Mystery", mount: "/Volumes/Mystery", internalDisk: nil, removable: nil, startup: false)
        XCTAssertEqual(DiskSurveyParser.eligibility(unknown, includeInternalNonStartup: true), .excludedInternalUnknown)
        let slash = volume(id: "disk9s1", whole: "disk9", name: "A/B", mount: "/Volumes/A/B", internalDisk: false, removable: true, startup: false)
        XCTAssertThrowsError(try InstallWorkflow.prepareUSB(installer: installer, volume: slash, typedName: "A/B", includeInternalNonStartup: false).get()) { error in
            XCTAssertEqual(error as? WorkflowError, .diskNotMounted)
        }
    }

    func testHostileVolumeNameStaysOneArgument() throws {
        let installer = try InstallWorkflow.checkInstaller(at: try makeInstaller(name: "Install macOS Tahoe")).get()
        let nasty = "Target; echo pwned"
        let volume = volume(id: "disk5s1", whole: "disk5", name: nasty, mount: "/Volumes/\(nasty)", internalDisk: false, removable: true, startup: false)
        let plan = try InstallWorkflow.prepareUSB(installer: installer, volume: volume, typedName: nasty, includeInternalNonStartup: false).get()
        XCTAssertEqual(plan.arguments.count, 2)
        XCTAssertEqual(plan.arguments[0], "--volume")
        XCTAssertEqual(plan.arguments[1], "/Volumes/\(nasty)")
        XCTAssertEqual(plan.standardInput, "Y\n")
        XCTAssertTrue(plan.needsAdministratorPrompt)

        let record = root.appendingPathComponent("sudo-args.txt")
        let fakeSudo = root.appendingPathComponent("fake-sudo")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > \(record.path)
        exit 0
        """
        try script.write(to: fakeSudo, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSudo.path)
        let runner = ProcessCommandRunner(sudoPath: fakeSudo.path, allowAdministratorCommands: true)
        let outcome = try runner.run(plan, onProgress: { _ in }, isCancelled: { false })
        XCTAssertEqual(outcome.exitCode, 0)
        let lines = try String(contentsOf: record, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(lines, ["--", installer.createInstallMediaPath, "--volume", "/Volumes/\(nasty)"])
    }

    func testChangedDiskDoesNotRunTheTool() throws {
        let installer = try InstallWorkflow.checkInstaller(at: try makeInstaller(name: "Install macOS Tahoe")).get()
        let chosen = volume(id: "disk4s1", whole: "disk4", name: "Target", mount: "/Volumes/Target", internalDisk: false, removable: true, startup: false)
        let spy = SpyRunner()
        let moved = volume(id: "disk4s1", whole: "disk4", name: "Other", mount: "/Volumes/Other", internalDisk: false, removable: true, startup: false)
        XCTAssertThrowsError(try InstallWorkflow.executeUSB(
            installer: installer,
            volume: chosen,
            typedName: "Target",
            includeInternalNonStartup: false,
            currentVolumes: [moved],
            runner: spy,
            cancel: WorkflowCancel(),
            onProgress: { _ in }
        )) { error in
            XCTAssertEqual(error as? WorkflowError, .diskDisappeared)
        }
        XCTAssertTrue(spy.commands.isEmpty)
    }

    func testDiskListParserHidesStartupAndUnknownDisks() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>AllDisksAndPartitions</key>
        <array>
          <dict>
            <key>DeviceIdentifier</key><string>disk0</string>
            <key>Internal</key><true/>
            <key>Partitions</key>
            <array>
              <dict>
                <key>DeviceIdentifier</key><string>disk0s2</string>
                <key>VolumeName</key><string>Macintosh HD</string>
                <key>MountPoint</key><string>/</string>
                <key>Size</key><integer>500000000000</integer>
              </dict>
            </array>
          </dict>
          <dict>
            <key>DeviceIdentifier</key><string>disk4</string>
            <key>Internal</key><false/>
            <key>Removable</key><true/>
            <key>Partitions</key>
            <array>
              <dict>
                <key>DeviceIdentifier</key><string>disk4s1</string>
                <key>VolumeName</key><string>Target</string>
                <key>MountPoint</key><string>/Volumes/Target</string>
                <key>Size</key><integer>8000000000</integer>
                <key>Writable</key><true/>
                <key>FileSystem</key><string>Journaled HFS+</string>
              </dict>
            </array>
          </dict>
        </array>
        </dict></plist>
        """
        let records = try DiskSurveyParser.parse(Data(plist.utf8))
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(DiskSurveyParser.eligibility(records[0], includeInternalNonStartup: true), .excludedStartup)
        XCTAssertEqual(DiskSurveyParser.eligibility(records[1], includeInternalNonStartup: false), .eligible)
        XCTAssertNotNil(DiskSurveyParser.sizeCaution(records[1]))
        XCTAssertEqual(
            InstallWorkflow.diskutilList().arguments,
            ["list", "-plist"]
        )
        XCTAssertFalse(InstallWorkflow.diskutilList().needsAdministratorPrompt)
    }

    func testRunnerRefusesAShellAndCanBeCancelled() throws {
        let runner = ProcessCommandRunner(allowAdministratorCommands: false)
        XCTAssertThrowsError(try runner.run(
            ArgumentVector(executable: "/bin/sh", arguments: ["-c", "echo should-not-run"], needsAdministratorPrompt: false),
            onProgress: { _ in },
            isCancelled: { false }
        )) { error in
            XCTAssertEqual(error as? WorkflowError, .shellRejected)
        }
        let marker = root.appendingPathComponent("ran.txt")
        let sleeper = root.appendingPathComponent("sleeper")
        try "#!/bin/sh\nsleep 30\ntouch \(marker.path)\n".write(to: sleeper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sleeper.path)
        let cancel = WorkflowCancel()
        let started = Date()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            cancel.cancel()
        }
        XCTAssertThrowsError(try runner.run(
            ArgumentVector(executable: sleeper.path, arguments: [], needsAdministratorPrompt: false),
            onProgress: { _ in },
            isCancelled: { cancel.isCancelled() }
        )) { error in
            XCTAssertEqual(error as? WorkflowError, .cancelled)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testAdministratorCommandsCanBeRefusedBeforeAnyProcess() throws {
        let installer = try InstallWorkflow.checkInstaller(at: try makeInstaller(name: "Install macOS Tahoe")).get()
        let chosen = volume(id: "disk4s1", whole: "disk4", name: "Target", mount: "/Volumes/Target", internalDisk: false, removable: true, startup: false)
        let plan = try InstallWorkflow.prepareUSB(installer: installer, volume: chosen, typedName: "Target", includeInternalNonStartup: false).get()
        let runner = ProcessCommandRunner(allowAdministratorCommands: false)
        XCTAssertThrowsError(try runner.run(plan, onProgress: { _ in }, isCancelled: { false })) { error in
            XCTAssertEqual(error as? WorkflowError, .administratorRequiredButRefused)
        }
    }

    private func makeInstaller(name: String) throws -> URL {
        let app = root.appendingPathComponent("\(name).app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleDisplayName</key><string>\(name)</string>
        <key>CFBundleIdentifier</key><string>com.example.fixture.installer</string>
        <key>CFBundleShortVersionString</key><string>26.7.2</string>
        </dict></plist>
        """
        try info.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        let tool = resources.appendingPathComponent("createinstallmedia")
        try "#!/bin/sh\nexit 0\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return app
    }

    private func volume(
        id: String,
        whole: String,
        name: String,
        mount: String?,
        internalDisk: Bool?,
        removable: Bool?,
        startup: Bool
    ) -> VolumeRecord {
        VolumeRecord(
            deviceIdentifier: id,
            wholeDiskIdentifier: whole,
            volumeName: name,
            mountPoint: mount,
            sizeBytes: 32_000_000_000,
            isInternal: internalDisk,
            isRemovable: removable,
            isWritable: true,
            filesystem: "Journaled HFS+",
            wholeDiskContainsStartup: startup
        )
    }
}

private final class SpyRunner: CommandRunning {
    var commands: [ArgumentVector] = []

    func run(
        _ command: ArgumentVector,
        onProgress: @escaping (String) -> Void,
        isCancelled: @escaping () -> Bool
    ) throws -> CommandOutcome {
        if isCancelled() { throw WorkflowError.cancelled }
        commands.append(command)
        onProgress("spy")
        return CommandOutcome(exitCode: 0, standardOutput: "", standardError: "")
    }
}
