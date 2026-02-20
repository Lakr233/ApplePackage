//
//  Logger.swift
//  ApplePackage
//
//  Created on 2026/2/20.
//

import Foundation
import os

public enum APLogger {
    private static let logger = Logger(subsystem: "com.applepackage", category: "network")

    public nonisolated(unsafe) static var verbose: Bool = false

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func debug(_ message: String) {
        guard verbose else { return }
        logger.debug("\(message, privacy: .public)")
        print("[DEBUG] \(message)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    static func logRequest(method: String, url: String, headers: [(String, String)] = []) {
        guard verbose else { return }
        var msg = ">>> \(method) \(url)"
        for (name, value) in headers {
            let safeValue = name.lowercased().contains("token") || name.lowercased().contains("password")
                ? "<redacted>"
                : value
            msg += "\n    \(name): \(safeValue)"
        }
        debug(msg)
    }

    static func logResponse(status: UInt, headers: [(String, String)] = [], bodySize: Int? = nil) {
        guard verbose else { return }
        var msg = "<<< \(status)"
        if let bodySize {
            msg += " (\(bodySize) bytes)"
        }
        for (name, value) in headers {
            msg += "\n    \(name): \(value)"
        }
        debug(msg)
    }
}
