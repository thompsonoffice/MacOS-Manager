import Foundation

public enum WorkflowError: Error, Equatable, LocalizedError {
    case versionNotOffered
    case versionStringRejected
    case installerMissing
    case installerNotFull
    case installerToolEscapesBundle
    case startupDiskBlocked
    case internalDiskHidden
    case internalDiskUnknown
    case diskNotMounted
    case diskNotWritable
    case systemPathBlocked
    case confirmationMismatch
    case diskDisappeared
    case diskListUnreadable(String)
    case cancelled
    case shellRejected
    case commandRejected(String)
    case administratorRequiredButRefused
    case commandFailed(exitCode: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .versionNotOffered:
            return "That macOS version is not offered for this Mac from the pages in this catalog. Nothing was downloaded."
        case .versionStringRejected:
            return "The version number was rejected. Only the exact build from Apple's catalog is sent to softwareupdate."
        case .installerMissing:
            return "No installer app was found at that path."
        case .installerNotFull:
            return "That app is not a full macOS installer. Apple's full installer contains createinstallmedia inside the app."
        case .installerToolEscapesBundle:
            return "createinstallmedia does not stay inside the installer app. The app was not used."
        case .startupDiskBlocked:
            return "The startup disk is blocked. This app will not erase the Mac it is running on."
        case .internalDiskHidden:
            return "Internal disks are hidden. Turn on internal disks only if you mean a disk that is not the startup disk."
        case .internalDiskUnknown:
            return "This disk was hidden because the listing did not say it was external."
        case .diskNotMounted:
            return "The volume is not mounted under /Volumes, so createinstallmedia cannot target it."
        case .diskNotWritable:
            return "That volume is not writable."
        case .systemPathBlocked:
            return "That path is a system path, not an external volume."
        case .confirmationMismatch:
            return "The typed name does not match the chosen volume. Nothing was erased."
        case .diskDisappeared:
            return "The chosen volume is no longer the same disk. Nothing was erased."
        case .diskListUnreadable(let detail):
            return "The disk list could not be read. \(detail)"
        case .cancelled:
            return "Cancelled. No further step was started."
        case .shellRejected:
            return "A shell was refused. Commands are passed as separate arguments."
        case .commandRejected(let detail):
            return detail
        case .administratorRequiredButRefused:
            return "Creating the installer needs an administrator prompt, and that prompt is turned off."
        case .commandFailed(let exitCode, let message):
            let detail = message.isEmpty ? "The program stopped." : message
            return "The program stopped with code \(exitCode). \(detail)"
        }
    }
}

public struct CheckedInstaller: Equatable, Sendable {
    public var appPath: String
    public var displayName: String
    public var createInstallMediaPath: String
    public var shortVersion: String?

    public init(appPath: String, displayName: String, createInstallMediaPath: String, shortVersion: String?) {
        self.appPath = appPath
        self.displayName = displayName
        self.createInstallMediaPath = createInstallMediaPath
        self.shortVersion = shortVersion
    }
}

public struct ToolPaths: Equatable, Sendable {
    public var softwareupdate: String
    public var openTool: String
    public var sudo: String
    public var diskutil: String

    public init(
        softwareupdate: String = "/usr/sbin/softwareupdate",
        openTool: String = "/usr/bin/open",
        sudo: String = "/usr/bin/sudo",
        diskutil: String = "/usr/sbin/diskutil"
    ) {
        self.softwareupdate = softwareupdate
        self.openTool = openTool
        self.sudo = sudo
        self.diskutil = diskutil
    }
}

public enum InstallWarnings {
    public static let usbDataLoss = "ALL DATA ON THE SELECTED USB WILL BE ERASED."

    public static func usbConfirmation(volumeName: String, capacity: String) -> String {
        "\(usbDataLoss) The selected USB is \(volumeName), \(capacity). Type that name to confirm. This writes an installer onto that USB."
    }
}

public enum InstallWorkflow {
    public static func selectableVersions(_ report: CompatibilityReport) -> [VersionAssessment] {
        report.versions.filter { assessment in
            assessment.claim == .listedOnApplePage || assessment.claim == .coveredByAppleSiliconStatement
        }
    }

    /// Keeps the current choice when it is still offered. Otherwise uses the newest offered id.
    public static func preferredReleaseID(_ current: String, in report: CompatibilityReport) -> String {
        let offered = selectableVersions(report).map(\.releaseID)
        if offered.contains(current) {
            return current
        }
        return offered.first ?? current
    }

    public static func isOfficialVersionToken(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count) else { return false }
        return parts.allSatisfy { part in
            (1...4).contains(part.count) && part.allSatisfy(\.isNumber)
        }
    }

    public static func fetchFullInstaller(
        assessment: VersionAssessment,
        catalog: Catalog,
        tools: ToolPaths = ToolPaths()
    ) -> Result<ArgumentVector, WorkflowError> {
        guard assessment.claim == .listedOnApplePage || assessment.claim == .coveredByAppleSiliconStatement else {
            return .failure(.versionNotOffered)
        }
        guard let release = catalog.releases.first(where: { $0.id == assessment.releaseID }),
              release.latestBuild == assessment.latestBuild,
              isOfficialVersionToken(assessment.latestBuild) else {
            return .failure(.versionStringRejected)
        }
        return .success(ArgumentVector(
            executable: tools.softwareupdate,
            arguments: ["--fetch-full-installer", "--full-installer-version", assessment.latestBuild],
            needsAdministratorPrompt: false
        ))
    }

    public static func diskutilList(tools: ToolPaths = ToolPaths()) -> ArgumentVector {
        ArgumentVector(
            executable: tools.diskutil,
            arguments: ["list", "-plist"],
            needsAdministratorPrompt: false
        )
    }

    public static func checkInstaller(at appURL: URL) -> Result<CheckedInstaller, WorkflowError> {
        let app = appURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: app.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(.installerMissing)
        }
        guard app.pathExtension == "app" else {
            return .failure(.installerNotFull)
        }
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        guard let infoData = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any] else {
            return .failure(.installerNotFull)
        }
        let display = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? app.deletingPathExtension().lastPathComponent
        guard display.hasPrefix("Install ") else {
            return .failure(.installerNotFull)
        }
        let tool = app.appendingPathComponent("Contents/Resources/createinstallmedia")
        guard FileManager.default.fileExists(atPath: tool.path) else {
            return .failure(.installerNotFull)
        }
        let resolvedTool = tool.resolvingSymlinksInPath().standardizedFileURL
        let contents = app.appendingPathComponent("Contents").resolvingSymlinksInPath().standardizedFileURL
        let contentsPath = contents.path.hasSuffix("/") ? contents.path : contents.path + "/"
        guard resolvedTool.path.hasPrefix(contentsPath) else {
            return .failure(.installerToolEscapesBundle)
        }
        var toolDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedTool.path, isDirectory: &toolDirectory),
              !toolDirectory.boolValue else {
            return .failure(.installerNotFull)
        }
        return .success(CheckedInstaller(
            appPath: app.path,
            displayName: display,
            createInstallMediaPath: resolvedTool.path,
            shortVersion: info["CFBundleShortVersionString"] as? String
        ))
    }

    public static func findInstallers(in directory: URL) -> [Result<CheckedInstaller, WorkflowError>] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { checkInstaller(at: $0) }
    }

    public static func prepareOpen(_ installer: CheckedInstaller, tools: ToolPaths = ToolPaths()) -> ArgumentVector {
        ArgumentVector(
            executable: tools.openTool,
            arguments: [installer.appPath],
            needsAdministratorPrompt: false
        )
    }

    public static func prepareUSB(
        installer: CheckedInstaller,
        volume: VolumeRecord,
        typedName: String,
        includeInternalNonStartup: Bool
    ) -> Result<ArgumentVector, WorkflowError> {
        switch DiskSurveyParser.eligibility(volume, includeInternalNonStartup: includeInternalNonStartup) {
        case .eligible:
            break
        case .excludedStartup, .excludedSystemPath:
            return .failure(volume.wholeDiskContainsStartup ? .startupDiskBlocked : .systemPathBlocked)
        case .excludedInternal:
            return .failure(.internalDiskHidden)
        case .excludedInternalUnknown:
            return .failure(.internalDiskUnknown)
        case .excludedNotMounted:
            return .failure(.diskNotMounted)
        case .excludedNotWritable:
            return .failure(.diskNotWritable)
        }
        guard typedName == volume.volumeName else {
            return .failure(.confirmationMismatch)
        }
        guard let mount = volume.mountPoint,
              DiskSurveyParser.isExternalMount(mount, volumeName: volume.volumeName) else {
            return .failure(.diskNotMounted)
        }
        return .success(ArgumentVector(
            executable: installer.createInstallMediaPath,
            arguments: ["--volume", mount],
            needsAdministratorPrompt: true,
            standardInput: "Y\n"
        ))
    }

    /// Reads the disk list again and runs the tool only if the same device is still eligible and the typed name still matches.
    public static func executeUSB(
        installer: CheckedInstaller,
        volume: VolumeRecord,
        typedName: String,
        includeInternalNonStartup: Bool,
        currentVolumes: [VolumeRecord],
        runner: CommandRunning,
        cancel: WorkflowCancel,
        onProgress: @escaping (String) -> Void
    ) throws -> CommandOutcome {
        if cancel.isCancelled() {
            throw WorkflowError.cancelled
        }
        guard let fresh = currentVolumes.first(where: { $0.deviceIdentifier == volume.deviceIdentifier }) else {
            throw WorkflowError.diskDisappeared
        }
        guard fresh.volumeName == volume.volumeName,
              fresh.mountPoint == volume.mountPoint,
              fresh.wholeDiskIdentifier == volume.wholeDiskIdentifier,
              fresh.wholeDiskContainsStartup == volume.wholeDiskContainsStartup else {
            throw WorkflowError.diskDisappeared
        }
        let plan = try prepareUSB(
            installer: installer,
            volume: fresh,
            typedName: typedName,
            includeInternalNonStartup: includeInternalNonStartup
        ).get()
        onProgress("Erase confirmation matches \(fresh.volumeName).")
        return try runner.run(plan, onProgress: onProgress, isCancelled: cancel.isCancelled)
    }

    public static func execute(
        _ command: ArgumentVector,
        runner: CommandRunning,
        cancel: WorkflowCancel,
        onProgress: @escaping (String) -> Void
    ) throws -> CommandOutcome {
        if cancel.isCancelled() {
            throw WorkflowError.cancelled
        }
        return try runner.run(command, onProgress: onProgress, isCancelled: cancel.isCancelled)
    }
}
