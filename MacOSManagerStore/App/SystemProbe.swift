import Darwin
import Foundation
import IOKit.ps
import MacOSManagerStoreCore

struct HostFacts {
    var reading: MachineReading
    var installed: InstalledVersion
    var freeSpace: FreeSpaceMeasurement
    var memoryBytes: UInt64
    var powerSources: [PowerSourceSnapshot]?
}

enum SystemProbe {
    static let sandboxStatus =
        "This edition requests the App Sandbox and does not use a privileged helper. It reads hw.model with sysctl, free space with a volume resource value, memory with ProcessInfo, and power with IOKit power sources. It does not run softwareupdate or createinstallmedia, and it does not read raw disks."

    static func read() -> HostFacts {
        let model = sysctlString("hw.model")
        let machine = sysctlString("hw.machine")
        let raw = ProcessInfo.processInfo.operatingSystemVersionString
        let installed = InstalledVersion(
            version: ProcessInfo.processInfo.operatingSystemVersion,
            rawString: raw
        )
        let error: String?
        if model == nil {
            error = "sysctl did not return hw.model. You can type the model identifier from System Information."
        } else {
            error = nil
        }
        let reading = MachineReading(
            modelIdentifier: model,
            machine: machine,
            operatingSystemVersion: raw,
            probeMethod: "sysctlbyname hw.model and hw.machine, ProcessInfo for the installed system and memory, URL resource values for startup-volume space, and IOPSCopyPowerSourcesInfo for power",
            sandboxStatus: sandboxStatus,
            probeError: error
        )
        return HostFacts(
            reading: reading,
            installed: installed,
            freeSpace: startupVolumeSpace(),
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            powerSources: powerSources()
        )
    }

    /// Available capacity of the startup volume. This is a URL resource value, not raw disk access.
    static func startupVolumeSpace() -> FreeSpaceMeasurement {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return .unreadable
        }
        if let important = values.volumeAvailableCapacityForImportantUsage {
            return .importantUsage(important)
        }
        if let free = values.volumeAvailableCapacity {
            return .freeOnly(Int64(free))
        }
        return .unreadable
    }

    /// `nil` means IOKit did not return a power-source list. An empty array means no sources were listed.
    static func powerSources() -> [PowerSourceSnapshot]? {
        guard let blobUnmanaged = IOPSCopyPowerSourcesInfo() else {
            return nil
        }
        let blob = blobUnmanaged.takeRetainedValue()
        guard let listUnmanaged = IOPSCopyPowerSourcesList(blob) else {
            return nil
        }
        let list = listUnmanaged.takeRetainedValue() as NSArray
        var snapshots: [PowerSourceSnapshot] = []
        for item in list {
            guard let source = item as? CFTypeRef else { continue }
            guard let descriptionUnmanaged = IOPSGetPowerSourceDescription(blob, source) else {
                continue
            }
            let info = descriptionUnmanaged.takeUnretainedValue() as NSDictionary
            let type = info[kIOPSTypeKey] as? String ?? ""
            let state = info[kIOPSPowerSourceStateKey] as? String ?? ""
            let presentNumber = info[kIOPSIsPresentKey] as? NSNumber
            let present = presentNumber?.boolValue ?? (info[kIOPSIsPresentKey] as? Bool) ?? true
            snapshots.append(PowerSourceSnapshot(
                type: type,
                state: state,
                currentCapacity: intValue(info[kIOPSCurrentCapacityKey]),
                maxCapacity: intValue(info[kIOPSMaxCapacityKey]),
                isPresent: present
            ))
        }
        return snapshots
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        let value = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}
