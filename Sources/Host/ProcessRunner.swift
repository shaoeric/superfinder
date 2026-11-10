import Foundation

struct ProcessResult {
    let status: Int32
    let standardOutput: String
    let standardError: String

    var combinedOutput: String {
        let parts = [standardOutput, standardError].filter { !$0.isEmpty }
        return parts.joined(separator: "\n")
    }
}

enum ProcessRunnerError: LocalizedError {
    case launchFailed(String, Error)
    case commandFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let path, let error):
            return "无法运行 \(path)：\(error.localizedDescription)"
        case .commandFailed(let path, let status, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(path) 执行失败（退出码 \(status)）" + (trimmed.isEmpty ? "" : "：\(trimmed)")
        }
    }
}

enum ProcessRunner {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(executable, error)
        }

        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            status: process.terminationStatus,
            standardOutput: String(data: outputData, encoding: .utf8) ?? "",
            standardError: String(data: errorData, encoding: .utf8) ?? ""
        )
    }

    static func runCheckingStatus(_ executable: String, _ arguments: [String]) throws -> ProcessResult {
        let result = try run(executable, arguments)
        guard result.status == 0 else {
            throw ProcessRunnerError.commandFailed(executable, result.status, result.combinedOutput)
        }
        return result
    }
}
