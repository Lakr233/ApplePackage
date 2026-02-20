//
//  Login.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import ApplePackage
import ArgumentParser
import Foundation

struct Login: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "login",
        abstract: "Login to Apple account",
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Argument(help: "Email address")
    var email: String

    @Argument(help: "Password")
    var password: String

    @Option(help: "2FA code")
    var code: String?

    func run() async throws {
        globalOptions.apply()
        do {
            let account = try await Authenticator.authenticate(email: email, password: password, code: code ?? "")
            Configuration.saveLoginAccount(account, for: email)
            print("login successful for \(email)")
        } catch {
            if code == nil {
                print("login failed: \(error), provide 2FA code with --code option and try again")
            } else {
                throw error
            }
        }
    }
}
