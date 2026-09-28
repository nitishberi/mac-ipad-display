import Foundation

enum Log {
    private static let queue = DispatchQueue(label: "mac-ipad-display.log")
    private static var fileHandle: FileHandle?

    private static var logURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacIPadDisplay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mac-ipad-display.log")
    }

    static func setup() {
        queue.sync {
            let url = logURL
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            fileHandle = try? FileHandle(forWritingTo: url)
            try? fileHandle?.seekToEnd()
        }
        info("——— session start \(ISO8601DateFormatter().string(from: Date())) ———")
    }

    static func info(_ message: String) { write("INFO", message) }
    static func warn(_ message: String) { write("WARN", message) }
    static func error(_ message: String) { write("ERROR", message) }

    private static func write(_ level: String, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                fileHandle?.write(data)
                try? fileHandle?.synchronize()
            }
        }
        FileHandle.standardError.write(Data(line.utf8))
    }
}
