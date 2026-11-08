import Darwin
import Foundation
import MacOSManagerCore

enum SystemProbe {
    static let sandboxStatus = "Sandbox check: not done. The project requests the App Sandbox, this copy is not signed, and sysctl inside a signed sandbox has not been tried on a Mac."

    static func read() -> MachineReading {
        let model = sysctlString("hw.model")
        let machine = sysctlString("hw.machine")
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        let error: String?
        if model == nil {
            error = "sysctl did not return hw.model. Type the model identifier from System Information."
        } else {
            error = nil
        }
        return MachineReading(
            modelIdentifier: model,
            machine: machine,
            operatingSystemVersion: version,
            probeMethod: "sysctlbyname hw.model and hw.machine",
            sandboxStatus: sandboxStatus,
            probeError: error
        )
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
