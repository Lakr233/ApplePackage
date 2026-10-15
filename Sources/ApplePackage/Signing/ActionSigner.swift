//
//  ActionSigner.swift
//  ApplePackage
//
//  Created on 2026/10/15.
//

import AsyncHTTPClient
import Foundation

/// Produces the `X-Apple-ActionSignature` header value for a request body.
///
/// The Store now rejects unsigned `authenticate` requests with HTTP 403.
/// The signature comes from a FairPlay SAP session negotiated with Apple using
/// the endpoints advertised by the bag (`sign-sap-setup-cert`, `sign-sap-setup`).
public protocol ActionSigner: AnyObject {
    func sign(_ data: Data) throws -> Data
}

public enum ActionSignerHeader {
    public static let name = "X-Apple-ActionSignature"
}

public struct SAPConfiguration: Sendable {
    public var setupURL: URL
    public var certificateURL: URL
    public var version: UInt32

    public init(setupURL: URL, certificateURL: URL, version: UInt32) {
        self.setupURL = setupURL
        self.certificateURL = certificateURL
        self.version = version
    }

    static let supportedVersion: UInt32 = 200
}

/// One FairPlay SAP session: the primitives run Apple's implementation, the
/// handshake transport below is plain HTTPS.
protocol SAPPrimitives: ActionSigner {
    /// Feeds one handshake message and returns the reply plus the session state.
    /// State 1 means a reply must be sent to Apple, state 0 means established.
    func exchange(version: UInt32, input: Data) throws -> (output: Data, state: UInt32)
}

extension Configuration {
    /// Creates an established signer for the given bag configuration.
    ///
    /// Defaults to the native implementation on macOS. Other platforms have no
    /// built-in signer; host apps may provide one here.
    public static var actionSignerProvider: ((SAPConfiguration, Data) async throws -> ActionSigner)? = {
        #if os(macOS)
            return { configuration, hardwareID in
                let session = try NativeSAPSession(hardwareID: hardwareID)
                try await SAPHandshake.establish(session, configuration: configuration)
                return session
            }
        #else
            return nil
        #endif
    }()

    static func makeActionSigner(configuration: SAPConfiguration) async throws -> ActionSigner {
        try ensure(configuration.version == SAPConfiguration.supportedVersion, "\(Strings.sapUnsupportedVersion): \(configuration.version)")
        guard let provider = actionSignerProvider else {
            try ensureFailed(Strings.sapUnavailable)
        }
        return try await provider(configuration, try sapHardwareID())
    }

    /// The SAP hardware ID is the raw device identifier (a MAC address in hex).
    static func sapHardwareID() throws -> Data {
        let hex = Array(deviceIdentifier.utf8)
        try ensure(!hex.isEmpty && hex.count % 2 == 0 && hex.count <= 40, Strings.sapInvalidHardwareID)
        var bytes = Data(capacity: hex.count / 2)
        for index in stride(from: 0, to: hex.count, by: 2) {
            guard let byte = UInt8(String(decoding: hex[index ..< index + 2], as: UTF8.self), radix: 16) else {
                try ensureFailed(Strings.sapInvalidHardwareID)
            }
            bytes.append(byte)
        }
        return bytes
    }
}

enum SAPHandshake {
    private static let certificateKey = "sign-sap-setup-cert"
    private static let bufferKey = "sign-sap-setup-buffer"

    static func establish(_ session: SAPPrimitives, configuration: SAPConfiguration) async throws {
        let client = Configuration.makeHTTPClient(redirectConfiguration: .follow(max: 4, allowCycles: false))
        defer { _ = client.shutdown() }

        let certificateRequest = try HTTPClient.Request(
            url: configuration.certificateURL.absoluteString,
            method: .GET,
            headers: .init([("User-Agent", Configuration.userAgent)])
        )
        let certificate = try await send(certificateRequest, client: client, key: certificateKey)

        let (setupMessage, setupState) = try session.exchange(version: configuration.version, input: certificate)
        try ensure(setupState == 1 && !setupMessage.isEmpty, "\(Strings.sapSetupFailed): unexpected state \(setupState)")

        let envelope = try PropertyListSerialization.data(
            fromPropertyList: [bufferKey: setupMessage],
            format: .xml,
            options: 0
        )
        let setupRequest = try HTTPClient.Request(
            url: configuration.setupURL.absoluteString,
            method: .POST,
            headers: .init([
                ("User-Agent", Configuration.userAgent),
                ("Content-Type", "application/x-plist"),
            ]),
            body: .data(envelope)
        )
        let reply = try await send(setupRequest, client: client, key: bufferKey)

        let (_, finalState) = try session.exchange(version: configuration.version, input: reply)
        try ensure(finalState == 0, "\(Strings.sapSetupFailed): unexpected state \(finalState)")
        APLogger.info("sap: session established")
    }

    private static func send(_ request: HTTPClient.Request, client: HTTPClient, key: String) async throws -> Data {
        APLogger.logRequest(method: request.method.rawValue, url: request.url.absoluteString, headers: request.headers.map { ($0.name, $0.value) })
        let response = try await client.execute(request: request).get()
        APLogger.logResponse(
            status: response.status.code,
            headers: response.headers.map { ($0.name, $0.value) },
            bodySize: response.body?.readableBytes
        )
        try ensure(response.status == .ok, "\(Strings.sapSetupFailed): HTTP \(response.status.code)")
        guard var body = response.body,
              let data = body.readData(length: body.readableBytes),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let value = plist[key] as? Data,
              !value.isEmpty
        else {
            try ensureFailed("\(Strings.sapSetupFailed): missing \(key)")
        }
        return value
    }
}
