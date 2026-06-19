import Foundation
import Observation
import OSLog

enum LogLevel: String, CaseIterable {
    case debug = "Debug"
    case info = "Info"
    case warning = "Warning"
    case error = "Error"
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
}

@Observable
final class AppLogger {
    static let shared = AppLogger()

    private let osLogger = Logger(subsystem: "com.yourname.GSMMac", category: "general")

    private(set) var entries: [LogEntry] = []

    private init() {}

    func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)

        DispatchQueue.main.async {
            self.entries.append(entry)
        }

        switch level {
        case .debug:   osLogger.debug("\(message)")
        case .info:    osLogger.info("\(message)")
        case .warning: osLogger.warning("\(message)")
        case .error:   osLogger.error("\(message)")
        }
    }

    func clear() {
        entries.removeAll()
    }
}
