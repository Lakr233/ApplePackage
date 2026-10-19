import AppleSAPKit
import ArgumentParser
import Foundation

@main
struct AppleSAPTool: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Compute SAP signatures locally from an existing handshake session.",
        subcommands: [Sign.self, ExportSession.self],
        defaultSubcommand: Sign.self
    )
}

private enum SignatureFormat: String, ExpressibleByArgument {
    case json, hex, base64
}

private func address(_ text: String) throws -> UInt64 {
    let value = text.hasPrefix("0x") ? UInt64(text.dropFirst(2), radix: 16) : UInt64(text)
    guard let value else { throw ValidationError("Address must be decimal or start with 0x") }
    return value
}

private func unhex(_ value: String) throws -> Data {
    let input = Array(value.utf8)
    guard input.count.isMultiple(of: 2) else { throw ValidationError("Odd hex length") }
    var result = Data()
    func digit(_ byte: UInt8) throws -> UInt8 {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: throw ValidationError("Invalid hex body")
        }
    }
    for at in stride(from: 0, to: input.count, by: 2) {
        result.append(try (digit(input[at]) << 4) | digit(input[at + 1]))
    }
    return result
}

private func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

private struct Sign: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Sign one or more bodies consecutively.")

    @Option(help: "Original complete post_handshake JSON snapshot.")
    var context: String?

    @Option(help: "Logical SAPSession JSON produced by export-session.")
    var session: String?

    @Option(name: .customLong("hex"), help: "Hex body; repeat for consecutive calls (empty string is valid).")
    var hexBodies: [String] = []

    @Option(help: "Binary body path; repeat for consecutive calls after the hex bodies.")
    var bodyFile: [String] = []

    @Option(help: "Original virtual IV destination for --context; logical sessions retain their saved address.")
    var ivAddress: String?

    @Option(help: "Platform encoded in the signing blob.")
    var platform: UInt32 = 1

    @Option(help: "Output format: json, hex, or base64.")
    var format: SignatureFormat = .json

    mutating func validate() throws {
        guard (context == nil) != (session == nil) else {
            throw ValidationError("Supply exactly one of --context and --session")
        }
        guard !hexBodies.isEmpty || !bodyFile.isEmpty else {
            throw ValidationError("Supply --hex or --body-file")
        }
        if let ivAddress {
            guard context != nil else { throw ValidationError("--iv-address requires --context") }
            _ = try address(ivAddress)
        }
        _ = try hexBodies.map(unhex)
    }

    func run() async throws {
        let signer: SAPSigner
        if let context {
            signer = try SAPSigner(snapshot: Data(contentsOf: URL(fileURLWithPath: context)),
                                   ivAddress: address(ivAddress ?? "0x5000007fed90"), platform: platform)
        } else if let session {
            let decoded = try JSONDecoder().decode(SAPSession.self, from: Data(contentsOf: URL(fileURLWithPath: session)))
            signer = try SAPSigner(session: decoded, platform: platform)
        } else {
            throw ValidationError("Missing session input")
        }
        let bodies = try hexBodies.map(unhex) + bodyFile.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
        for (index, body) in bodies.enumerated() {
            let signature = try await signer.sign(body)
            switch format {
            case .base64: print(signature.base64EncodedString())
            case .hex: print(hex(signature))
            case .json:
                let output: [String: Any] = [
                    "call_index": index, "body_length": body.count,
                    "signature_hex": hex(signature),
                    "iv_hex": hex(signature.subdata(in: 1..<17)),
                    "tag_hex": hex(signature.subdata(in: 17..<33)),
                ]
                print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: .sortedKeys), as: UTF8.self))
            }
        }
    }
}

private struct ExportSession: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export-session", abstract: "Extract logical session inputs; no handshake is performed."
    )

    @Option(help: "Original complete post_handshake JSON snapshot.") var context: String
    @Option(help: "Output JSON path. Contains sensitive session signing material.") var output: String
    @Option(help: "Original virtual IV destination.") var ivAddress: String = "0x5000007fed90"

    func run() throws {
        let session = try SAPSession(snapshot: Data(contentsOf: URL(fileURLWithPath: context)),
                                     ivAddress: address(ivAddress))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = URL(fileURLWithPath: output)
        try encoder.encode(session).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
