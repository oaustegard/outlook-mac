import Foundation
import OSLog

/// Runs the user's shortcuts through /usr/bin/shortcuts, in the background.
enum ShortcutRunner {
    private static let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")
    private static let log = Logger(subsystem: "com.oaustegard.outlook-mac", category: "automation")

    /// The names `shortcuts list` prints, sorted. Empty when the list cannot be read.
    static func names() async -> [String] {
        await Task.detached {
            let process = Process()
            process.executableURL = ShortcutRunner.executable
            process.arguments = ["list"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return []
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .sorted()
        }.value
    }

    /// Starts the shortcut with `input` as a JSON file, and returns at once. The file is removed when the run ends.
    static func run(_ name: String, input: [String: Any]) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("omac-automation-\(UUID().uuidString).json")
        do {
            let data = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
            try data.write(to: file, options: .atomic)
        } catch {
            log.error("Could not write shortcut input: \(error.localizedDescription, privacy: .public)")
            return
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["run", name, "--input-path", file.path]
        // `shortcuts run` waits on standard input when it is a terminal or a pipe, as it is when
        // the app is started from Xcode or a terminal, and then never ends. An empty input lets it finish.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            try? FileManager.default.removeItem(at: file)
            log.info("Shortcut run ended with status \(finished.terminationStatus, privacy: .public)")
        }
        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: file)
            log.error("Could not start shortcut: \(error.localizedDescription, privacy: .public)")
        }
    }
}
