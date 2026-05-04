// DeeplinkLogger.swift
// DeeplinkKit
//
// Lightweight, pluggable logger for the deeplink pipeline.
// Replace the handler to integrate with OSLog, CocoaLumberjack, etc.

import Foundation

#if canImport(os)
import os.log
#endif

// MARK: - DeeplinkLogger

/// Lightweight logger for the deeplink pipeline.
/// Swap `handler` to bridge to any logging framework.
public enum DeeplinkLogger {

    // MARK: - Level

    public enum Level: Int, Sendable, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
        case none = 99

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var prefix: String {
            switch self {
            case .debug:   return "🔵 [DeeplinkKit][DEBUG]"
            case .info:    return "🟢 [DeeplinkKit][INFO]"
            case .warning: return "🟡 [DeeplinkKit][WARN]"
            case .error:   return "🔴 [DeeplinkKit][ERROR]"
            case .none:    return ""
            }
        }
    }

    // MARK: - Configuration

    /// Minimum level to output. Set to `.none` to silence all output.
    public static var minimumLevel: Level = {
        #if DEBUG
        return .debug
        #else
        return .warning
        #endif
    }()

    /// Custom log handler. Defaults to os_log / print. Replace to forward to your logger.
    public static var handler: @Sendable (Level, String) -> Void = { level, message in
        guard level >= minimumLevel else { return }
        #if canImport(os)
        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            let logger = os.Logger(subsystem: "DeeplinkKit", category: "Deeplink")
            switch level {
            case .debug:   logger.debug("\(message, privacy: .public)")
            case .info:    logger.info("\(message, privacy: .public)")
            case .warning: logger.warning("\(message, privacy: .public)")
            case .error:   logger.error("\(message, privacy: .public)")
            case .none:    break
            }
        } else {
            print("\(level.prefix) \(message)")
        }
        #else
        print("\(level.prefix) \(message)")
        #endif
    }

    // MARK: - Logging

    static func log(_ level: Level, _ message: @autoclosure () -> String) {
        guard level >= minimumLevel else { return }
        handler(level, message())
    }
}
