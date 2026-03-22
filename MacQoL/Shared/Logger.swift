import Foundation
import os.log

/// Lightweight logging wrapper around os_log.
/// Usage: Log.error("thing failed", error) or Log.info("loaded 5 items")
enum Log {
    private static let subsystem = "com.macqol.app"

    private static let logger = os.Logger(subsystem: subsystem, category: "general")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String, _ error: Error? = nil) {
        if let error {
            logger.error("\(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
        } else {
            logger.error("\(message, privacy: .public)")
        }
    }

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}
