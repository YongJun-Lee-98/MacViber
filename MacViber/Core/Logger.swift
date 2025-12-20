import Foundation

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

final class Logger {
    static let shared = Logger()

    private let logDirectory: URL
    private let logFileURL: URL
    private let maxLogSize: Int = 5 * 1024 * 1024 // 5MB
    private let dateFormatter: DateFormatter
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.macviber.logger", qos: .utility)

    private init() {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        logDirectory = homeDirectory.appendingPathComponent("Library/Logs/MacViber")
        logFileURL = logDirectory.appendingPathComponent("macviber.log")

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        createLogDirectoryIfNeeded()
    }

    private func createLogDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: logDirectory.path) {
            try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        }
    }

    private func rotateLogIfNeeded() {
        guard let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
              let fileSize = attributes[.size] as? Int,
              fileSize > maxLogSize else {
            return
        }

        let backupURL = logDirectory.appendingPathComponent("macviber.log.old")
        try? fileManager.removeItem(at: backupURL)
        try? fileManager.moveItem(at: logFileURL, to: backupURL)
    }

    private func writeToFile(_ message: String) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.rotateLogIfNeeded()

            let logMessage = message + "\n"

            if self.fileManager.fileExists(atPath: self.logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: self.logFileURL) {
                    fileHandle.seekToEndOfFile()
                    if let data = logMessage.data(using: .utf8) {
                        fileHandle.write(data)
                    }
                    try? fileHandle.close()
                }
            } else {
                try? logMessage.write(to: self.logFileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    func log(_ level: LogLevel, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let formattedMessage = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(message)"

        #if DEBUG
        print(formattedMessage)
        #endif

        writeToFile(formattedMessage)
    }

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }

    func error(_ error: Error, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, error.localizedDescription, file: file, function: function, line: line)
    }

    var logFilePath: String {
        return logFileURL.path
    }
}
