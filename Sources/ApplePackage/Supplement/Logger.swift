//
//  Logger.swift
//  ApplePackage
//
//  Created on 2026/2/20.
//

import Foundation
import Logging

public enum APLogger {
    public nonisolated(unsafe) static var verbose: Bool = false

    private nonisolated(unsafe) static var _logger: Logger = .init(label: "com.applepackage")

    public static var logger: Logger {
        get { _logger }
        set { _logger = newValue }
    }

    static func info(_ message: String) {
        _logger.info("\(message)")
    }

    static func debug(_ message: String) {
        guard verbose else { return }
        _logger.debug("\(message)")
    }

    static func error(_ message: String) {
        _logger.error("\(message)")
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
