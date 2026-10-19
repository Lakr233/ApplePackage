//
//  Login.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import ApplePackage
import AppleSAPKit
import ArgumentParser
import Foundation
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

struct Login: AsyncParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        commandName: "login",
        abstract: "Login to Apple account"
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Argument(help: "Email address")
    var email: String

    @Argument(help: "Password")
    var password: String

    @Option(help: "2FA code")
    var code: String?

    @Option(name: .customLong("sap-context"), help: "Original post_handshake JSON for SAP signing; no handshake is generated")
    var sapContext: String?

    @Option(name: .customLong("sap-iv-address"), help: "Virtual IV address from the saved layout (decimal or 0x hexadecimal)", transform: { text in
        let hexadecimal = text.lowercased().hasPrefix("0x")
        let digits = hexadecimal ? String(text.dropFirst(2)) : text
        guard let value = UInt64(digits, radix: hexadecimal ? 16 : 10) else {
            throw ValidationError("Invalid SAP IV address: expected an unsigned decimal or hexadecimal integer")
        }
        return value
    })
    var sapIVAddress: UInt64 = 0x5000007fed90

    func run() async throws {
        globalOptions.apply()
        let sapSigner: (any SAPRequestSigning)?
        if let path = sapContext {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            sapSigner = try SAPSigner(snapshot: Data(contentsOf: url), ivAddress: sapIVAddress)
        } else {
            sapSigner = nil
        }
        var verificationCode = code ?? ""
        while true {
            do {
                let account = try await Authenticator.authenticate(
                    email: email,
                    password: password,
                    code: verificationCode,
                    sapSigner: sapSigner
                )
                Configuration.saveLoginAccount(account, for: email)
                print("login successful for \(email)")
                return
            } catch AuthenticationError.verificationCodeRequired {
                guard verificationCode.isEmpty, isatty(STDIN_FILENO) != 0 else {
                    throw AuthenticationError.verificationCodeRequired
                }
                print("2FA verification code: ", terminator: "")
                guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
                    throw AuthenticationError.verificationCodeRequired
                }
                verificationCode = input
            }
        }
    }
}
