import Darwin
import Foundation
import MacOSManagerStoreCore

enum SystemProbe {
    static let sandboxStatus =
        "This edition requests the App Sandbox and does not use a privileged helper. It reads hw.model with sysctl and does not run softwareupdate or createinstallmedia."

    static func read() -> (reading: MachineReading, installed: InstalledVersion) {
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
            probeMethod: "sysctlbyname hw.model and hw.machine, plus ProcessInfo for the installed system",
            sandboxStatus: sandboxStatus,
            probeError: error
        )
        return (reading, installed)
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
}
