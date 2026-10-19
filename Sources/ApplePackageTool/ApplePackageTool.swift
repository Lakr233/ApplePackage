//
//  ApplePackageTool.swift
//  ApplePackageTool
//
//  Created by qaq on 9/15/25.
//

import ApplePackage
import ArgumentParser
import Foundation

enum PlatformArgument: String, ExpressibleByArgument, Sendable {
    case iPhone
    case iPad
    case AppleTV

    var entityType: EntityType {
        switch self {
        case .iPhone:
            return .iPhone
        case .iPad:
            return .iPad
        case .AppleTV:
            return .appleTV
        }
    }
}

struct GlobalOptions: ParsableArguments, Sendable {
    @Option(name: .long, help: "Custom device GUID (default: system MAC address)")
    var guid: String?

    @Flag(name: .shortAndLong, help: "Enable verbose logging of requests and responses")
    var verbose: Bool = false

    func apply() {
        if let guid = guid {
            Configuration.deviceIdentifier = guid
        }
        if verbose {
            APLogger.verbose = true
            APLogger.logger.logLevel = .debug
        }
    }
}

@main
struct ApplePackageTool: AsyncParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        commandName: "applepackage",
        abstract: "A tool for managing Apple apps",
        subcommands: [Login.self, Logout.self, Search.self, Versions.self, Download.self]
    )
}
