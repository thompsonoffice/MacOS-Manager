import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// One program and its argument list. Nothing here is joined into a shell command.
public struct ArgumentVector: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    /// When true, a runner may prefix `/usr/bin/sudo --` so macOS can show its own administrator prompt.
    /// The password is never stored in this value.
    public var needsAdministratorPrompt: Bool
    /// Bytes written to the tool's standard input after the prompt decision. For createinstallmedia this is `Y\n` only after the volume name matched.
    public var standardInput: String?

    public init(
        executable: String,
        arguments: [String],
        needsAdministratorPrompt: Bool,
        standardInput: String? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.needsAdministratorPrompt = needsAdministratorPrompt
        self.standardInput = standardInput
    }
}

public struct CommandOutcome: Equatable, Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol CommandRunning: AnyObject {
    func run(
        _ command: ArgumentVector,
        onProgress: @escaping (String) -> Void,
        isCancelled: @escaping () -> Bool
    ) throws -> CommandOutcome
}

public final class WorkflowCancel: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    public init() {}

    public func cancel() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    public func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}

public enum CommandSafety {
    public static func rejection(for command: ArgumentVector) -> WorkflowError? {
        if command.executable.isEmpty || !command.executable.hasPrefix("/") {
            return .commandRejected("The program path must be an absolute path.")
        }
        if command.executable.contains("\n") || command.executable.contains("\0") {
            return .commandRejected("The program path contains a control character.")
        }
        for argument in command.arguments where argument.contains("\0") {
            return .commandRejected("An argument contains a null character.")
        }
        let name = URL(fileURLWithPath: command.executable).lastPathComponent
        if ["sh", "bash", "zsh", "dash", "csh", "ksh"].contains(name) {
            return .shellRejected
        }
        return nil
    }
}

/// Runs a program with an argument vector. It does not invoke a shell.
public final class ProcessCommandRunner: CommandRunning {
    public var sudoPath: String
    public var allowAdministratorCommands: Bool

    public init(sudoPath: String = "/usr/bin/sudo", allowAdministratorCommands: Bool = true) {
        self.sudoPath = sudoPath
        self.allowAdministratorCommands = allowAdministratorCommands
    }

    public func run(
        _ command: ArgumentVector,
        onProgress: @escaping (String) -> Void,
        isCancelled: @escaping () -> Bool
    ) throws -> CommandOutcome {
        if isCancelled() {
            throw WorkflowError.cancelled
        }
        if let rejection = CommandSafety.rejection(for: command) {
            throw rejection
        }
        let launched = try launchVector(command)
        if let rejection = CommandSafety.rejection(for: launched) {
            throw rejection
        }
        onProgress("Starting \(URL(fileURLWithPath: launched.executable).lastPathComponent).")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launched.executable)
        process.arguments = launched.arguments
        let output = Pipe()
        let errors = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = input
        let outputLock = NSLock()
        var outputData = Data()
        var errorData = Data()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outputLock.lock()
            outputData.append(chunk)
            outputLock.unlock()
            if let text = String(data: chunk, encoding: .utf8), !text.isEmpty {
                onProgress(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outputLock.lock()
            errorData.append(chunk)
            outputLock.unlock()
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            throw WorkflowError.commandFailed(exitCode: -1, message: "The program did not start. \(error.localizedDescription)")
        }
        if let text = launched.standardInput {
            if let data = text.data(using: .utf8) {
                input.fileHandleForWriting.write(data)
            }
        }
        input.fileHandleForWriting.closeFile()
        while process.isRunning {
            if isCancelled() {
                stop(process)
                let deadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                throw WorkflowError.cancelled
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        outputLock.lock()
        let stdout = String(data: outputData, encoding: .utf8) ?? ""
        let stderr = String(data: errorData, encoding: .utf8) ?? ""
        outputLock.unlock()
        if isCancelled() {
            throw WorkflowError.cancelled
        }
        let outcome = CommandOutcome(
            exitCode: process.terminationStatus,
            standardOutput: stdout,
            standardError: stderr
        )
        if outcome.exitCode != 0 {
            let detail = stderr.isEmpty ? stdout : stderr
            throw WorkflowError.commandFailed(exitCode: outcome.exitCode, message: detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return outcome
    }

    private func stop(_ process: Process) {
        let pid = process.processIdentifier
        if pid > 0 {
            _ = kill(pid, SIGKILL)
        }
        process.terminate()
    }

    private func launchVector(_ command: ArgumentVector) throws -> ArgumentVector {
        guard command.needsAdministratorPrompt else { return command }
        guard allowAdministratorCommands else {
            throw WorkflowError.administratorRequiredButRefused
        }
        if command.executable == sudoPath {
            return command
        }
        return ArgumentVector(
            executable: sudoPath,
            arguments: ["--", command.executable] + command.arguments,
            needsAdministratorPrompt: false,
            standardInput: command.standardInput
        )
    }
}
