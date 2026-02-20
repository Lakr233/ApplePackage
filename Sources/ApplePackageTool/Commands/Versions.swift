//
//  Versions.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import ApplePackage
import ArgumentParser
import Foundation

struct Versions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "versions",
        abstract: "List versions of an app"
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Argument(help: "Email address")
    var email: String

    @Argument(help: "Bundle ID")
    var bundleID: String

    func run() async throws {
        globalOptions.apply()
        try await Configuration.withAccount(email: email) { account in
            let versions = try await VersionFinder.list(account: &account, bundleIdentifier: bundleID)
            for version in versions {
                print(version)
            }
        }
    }
}
