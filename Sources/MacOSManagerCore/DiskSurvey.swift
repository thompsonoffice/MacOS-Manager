import Foundation

/// One mounted or listed volume, read from a `diskutil list -plist` shaped file.
/// Fixtures in tests use this same shape. A missing Internal flag is not treated as external.
public struct VolumeRecord: Equatable, Sendable, Identifiable {
    public var deviceIdentifier: String
    public var wholeDiskIdentifier: String
    public var volumeName: String
    public var mountPoint: String?
    public var sizeBytes: Int64
    public var isInternal: Bool?
    public var isRemovable: Bool?
    public var isWritable: Bool?
    public var filesystem: String?
    public var wholeDiskContainsStartup: Bool

    public var id: String { deviceIdentifier }

    public init(
        deviceIdentifier: String,
        wholeDiskIdentifier: String,
        volumeName: String,
        mountPoint: String?,
        sizeBytes: Int64,
        isInternal: Bool?,
        isRemovable: Bool?,
        isWritable: Bool?,
        filesystem: String?,
        wholeDiskContainsStartup: Bool
    ) {
        self.deviceIdentifier = deviceIdentifier
        self.wholeDiskIdentifier = wholeDiskIdentifier
        self.volumeName = volumeName
        self.mountPoint = mountPoint
        self.sizeBytes = sizeBytes
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isWritable = isWritable
        self.filesystem = filesystem
        self.wholeDiskContainsStartup = wholeDiskContainsStartup
    }
}

public enum VolumeEligibility: Equatable, Sendable {
    case eligible
    case excludedStartup
    case excludedInternal
    case excludedInternalUnknown
    case excludedNotMounted
    case excludedNotWritable
    case excludedSystemPath

    public var spoken: String {
        switch self {
        case .eligible:
            return "Can be chosen."
        case .excludedStartup:
            return "Excluded. This disk holds the running Mac. It cannot be erased by this app."
        case .excludedInternal:
            return "Excluded. Internal disks stay hidden unless you turn on showing internal disks that are not the startup disk."
        case .excludedInternalUnknown:
            return "Excluded. Apple's listing did not say whether this disk is internal, so it stays hidden."
        case .excludedNotMounted:
            return "Excluded. The volume is not mounted at /Volumes, which is what Apple's createinstallmedia command expects."
        case .excludedNotWritable:
            return "Excluded. The volume is not writable."
        case .excludedSystemPath:
            return "Excluded. The mount path is a system path, not an external volume."
        }
    }
}

public enum DiskSurveyParser {
    public static let startupMounts: Set<String> = ["/","/System/Volumes/Data"]
    /// Caution only. Apple's installer article says 16 GB is enough for most earlier installers. This does not block a choice.
    public static let smallVolumeWarningBytes: Int64 = 16_000_000_000

    public static func spokenCapacity(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "size not reported" }
        let tenths = (bytes + 50_000_000) / 100_000_000
        return "\(tenths / 10).\(tenths % 10) GB"
    }

    /// The volume macOS is running from, if the disk list includes it. This is display only.
    public static func startupVolume(in volumes: [VolumeRecord]) -> VolumeRecord? {
        if let root = volumes.first(where: { $0.mountPoint == "/" }) {
            return root
        }
        return volumes.first(where: \.wholeDiskContainsStartup)
    }

    public static func sizeCaution(_ volume: VolumeRecord) -> String? {
        guard volume.sizeBytes > 0, volume.sizeBytes < smallVolumeWarningBytes else { return nil }
        return "This volume is under 16 GB. Apple says 16 GB is enough for most earlier installers, and a larger drive is safer. The choice is still available."
    }

    public static func parse(_ data: Data) throws -> [VolumeRecord] {
        let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = root as? [String: Any] else {
            throw WorkflowError.diskListUnreadable("The disk list was not a property list dictionary.")
        }
        guard let disks = dict["AllDisksAndPartitions"] as? [[String: Any]] else {
            throw WorkflowError.diskListUnreadable("The disk list has no AllDisksAndPartitions array.")
        }
        var records: [VolumeRecord] = []
        for disk in disks {
            let whole = string(disk["DeviceIdentifier"]) ?? ""
            guard !whole.isEmpty else { continue }
            let partitions = disk["Partitions"] as? [[String: Any]] ?? []
            let startup = partitions.contains { mount in
                guard let point = string(mount["MountPoint"]) else { return false }
                return startupMounts.contains(point)
            }
            let diskInternal = bool(disk["Internal"])
            let diskRemovable = bool(disk["Removable"])
            for partition in partitions {
                guard let name = string(partition["VolumeName"]), !name.isEmpty else { continue }
                guard let device = string(partition["DeviceIdentifier"]), !device.isEmpty else { continue }
                let record = VolumeRecord(
                    deviceIdentifier: device,
                    wholeDiskIdentifier: whole,
                    volumeName: name,
                    mountPoint: string(partition["MountPoint"]),
                    sizeBytes: integer(partition["Size"]) ?? 0,
                    isInternal: bool(partition["Internal"]) ?? diskInternal,
                    isRemovable: bool(partition["Removable"]) ?? diskRemovable,
                    isWritable: bool(partition["Writable"]),
                    filesystem: string(partition["FileSystem"]) ?? string(partition["Content"]),
                    wholeDiskContainsStartup: startup
                )
                records.append(record)
            }
        }
        return records
    }

    public static func eligibility(_ volume: VolumeRecord, includeInternalNonStartup: Bool) -> VolumeEligibility {
        if volume.wholeDiskContainsStartup {
            return .excludedStartup
        }
        if let mount = volume.mountPoint {
            if startupMounts.contains(mount) || mount == "/System" || mount.hasPrefix("/System/") {
                return .excludedSystemPath
            }
            if !isExternalMount(mount, volumeName: volume.volumeName) {
                return .excludedNotMounted
            }
        } else {
            return .excludedNotMounted
        }
        if volume.isWritable == false {
            return .excludedNotWritable
        }
        if volume.isInternal == true {
            return includeInternalNonStartup ? .eligible : .excludedInternal
        }
        if volume.isInternal == nil && volume.isRemovable != true {
            return .excludedInternalUnknown
        }
        return .eligible
    }

    public static func isExternalMount(_ mount: String, volumeName: String) -> Bool {
        guard mount.hasPrefix("/Volumes/") else { return false }
        let rest = mount.dropFirst("/Volumes/".count)
        guard rest == volumeName else { return false }
        guard !volumeName.isEmpty,
              volumeName != ".",
              volumeName != "..",
              !volumeName.contains("/"),
              !volumeName.contains("\0"),
              !volumeName.contains("\n") else {
            return false
        }
        return true
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bool(_ value: Any?) -> Bool? {
        value as? Bool
    }

    private static func integer(_ value: Any?) -> Int64? {
        if let number = value as? Int64 { return number }
        if let number = value as? Int { return Int64(number) }
        if let number = value as? NSNumber { return number.int64Value }
        return nil
    }
}
