import Foundation

struct ShellOutput {
    let command: String
    let data: Data
    let exitCode: Int32
}

extension ShellOutput {
    var textOutput: String? {
        return String(data: data, encoding: .utf8)
    }
}

struct ShellExecutionError: Error {
    let output: ShellOutput
}

extension ShellExecutionError: CustomStringConvertible {
    var description: String {
        var result = "invocation of command=\(output.command) failed with code=\(output.exitCode)"
        if let textOutput = output.textOutput {
            result += " and output=\(textOutput)"
        }
        return result
    }
}

@discardableResult
func shell(_ command: String, output: URL? = nil) throws -> ShellOutput {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = try output.map { try FileHandle(forWritingTo: $0) } ?? pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.launchPath = "/bin/sh"
    task.standardInput = nil

    task.launch()

    task.waitUntilExit()
 
    let data: Data
    if let output {
        data = try FileHandle(forReadingFrom: output).readDataToEndOfFile()
    }
    else {
        data = pipe.fileHandleForReading.readDataToEndOfFile()
    }

    let output = ShellOutput(command: command, data: data, exitCode: task.terminationStatus)
    guard output.exitCode == 0 else {
        throw ShellExecutionError(output: output)
    }

    return output
}
