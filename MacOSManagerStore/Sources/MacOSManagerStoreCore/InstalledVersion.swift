import Foundation

/// The macOS version already running on this Mac, matched to a catalog release when possible.
public struct InstalledVersion: Equatable, Sendable {
    public var rawString: String
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(rawString: String, major: Int, minor: Int, patch: Int) {
        self.rawString = rawString
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init(version: OperatingSystemVersion, rawString: String) {
        self.init(
            rawString: rawString,
            major: version.majorVersion,
            minor: version.minorVersion,
            patch: version.patchVersion
        )
    }

    /// Catalog release identifiers use "27", "15", or "10.15".
    public var catalogReleaseID: String {
        if major >= 11 {
            return String(major)
        }
        return "\(major).\(minor)"
    }

    public func marks(releaseID: String) -> Bool {
        catalogReleaseID == releaseID
    }

    public func action(forReleaseID releaseID: String) -> InstallAction {
        guard let target = Self.sortValue(releaseID), let current = Self.sortValue(catalogReleaseID) else {
            return .unknown
        }
        if target == current { return .currentlyInstalled }
        if target > current { return .upgrade }
        return .downgrade
    }

    private static func sortValue(_ releaseID: String) -> Double? {
        Double(releaseID)
    }

    public var spoken: String {
        "This Mac is currently running \(rawString). In the list below, that version is marked currently installed when it appears."
    }
}


public enum InstallAction: String, Equatable, Sendable {
    case currentlyInstalled
    case upgrade
    case downgrade
    case unknown
}
