import Foundation

struct ShellOutput {
    let command: String
    let text: String?
    let exitCode: Int32
}

func shell(_ command: String) -> ShellOutput {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.launchPath = "/bin/sh"
    task.standardInput = nil

    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)

    task.waitUntilExit()

    return ShellOutput(command: command, text: output, exitCode: task.terminationStatus)
}
