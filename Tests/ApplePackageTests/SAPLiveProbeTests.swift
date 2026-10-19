import AppleSAPKit
import AsyncHTTPClient
@testable import ApplePackage
import Foundation
import NIOSSL
import XCTest

/// Explicitly opt-in transport observations, not a signature-acceptance test.
final class SAPLiveProbeTests: XCTestCase {
    private enum ProbeError: Error {
        case unapprovedEndpoint
        case redirectLimit
        case missingRedirect
        case malformedSignature
    }

    private struct Summary: Codable, Equatable {
        let variant: String
        let endpoint: String
        let status: UInt
        let redirects: Int
        let locationPresent: Bool
        let responseKind: String
        let failureType: String?
        let customerMessage: String?
        let explanation: String?
    }

    private func approved(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "apple.com" || host.hasSuffix(".apple.com"),
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443
        else { throw ProbeError.unapprovedEndpoint }
        return url
    }

    private func endpointDescription(_ url: URL) -> String {
        "https://\(url.host ?? "")\(url.path)"
    }

    private func sanitized(_ text: Any?, secrets: [String]) -> String? {
        guard var text = (text as? String) ?? (text as? NSNumber)?.stringValue else { return nil }
        for secret in secrets where !secret.isEmpty {
            text = text.replacingOccurrences(of: secret, with: "<redacted>")
        }
        text = text.replacingOccurrences(
            of: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
            with: "<email>", options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "[A-Za-z0-9+/=_-]{48,}", with: "<opaque>", options: .regularExpression)
        text = text.components(separatedBy: .newlines).joined(separator: " ")
        return String(text.prefix(240))
    }

    func testControlledSAPProbe() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["APPLEPACKAGE_SAP_PROBE_CONTEXT"], !path.isEmpty else {
            throw XCTSkip("Set APPLEPACKAGE_SAP_PROBE_CONTEXT to opt in with a private post-handshake context")
        }
        let snapshot = try Data(contentsOf: URL(fileURLWithPath: path))
        let signer = try SAPSigner(snapshot: snapshot)
        let identifier = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))
        Configuration.deviceIdentifier = identifier
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.certificateVerification = .fullVerification
        Configuration.tlsConfiguration = tls
        let previousLogger = APLogger.logger
        let previousVerbose = APLogger.verbose
        var quietLogger = previousLogger
        quietLogger.logLevel = .critical
        APLogger.logger = quietLogger
        APLogger.verbose = false
        defer {
            APLogger.logger = previousLogger
            APLogger.verbose = previousVerbose
        }

        // Bag redirects are disabled; authenticated redirects are bounded and
        // revalidated before any body/signature can be sent to another URL.
        let bag = try await Bag.fetchBag(redirectConfiguration: .disallow)
        var components = try XCTUnwrap(URLComponents(url: approved(bag.authEndpoint), resolvingAgainstBaseURL: true))
        components.queryItems = [URLQueryItem(name: "guid", value: identifier)]
        let initial = try approved(XCTUnwrap(components.url))
        let email = "\(UUID().uuidString)@example.invalid"
        let password = UUID().uuidString
        let variants = environment["APPLEPACKAGE_SAP_PROBE_CONTROLS"] == "1"
            ? ["signed", "unsigned", "corrupted"] : ["signed"]
        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }
        var totalRedirects = 0
        var summaries: [Summary] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase

        for variant in variants {
            var endpoint = initial
            var cookies: [Cookie] = []
            var redirects = 0
            while true {
                var request = try await Authenticator.makeRequest(
                    endpoint: approved(endpoint), email: email, password: password,
                    code: "", cookies: cookies, deviceIdentifier: identifier,
                    sapSigner: variant == "unsigned" ? nil : signer
                )
                if variant == "corrupted" {
                    guard let header = request.headers.first(name: "X-Apple-ActionSignature"),
                          var bytes = Data(base64Encoded: header), bytes.count > 17
                    else { throw ProbeError.malformedSignature }
                    bytes[17] ^= 1
                    request.headers.replaceOrAdd(name: "X-Apple-ActionSignature", value: bytes.base64EncodedString())
                }
                let signature = request.headers.first(name: "X-Apple-ActionSignature") ?? ""
                let response = try await client.execute(request: request).get()
                cookies.mergeCookies(response.cookies)
                if [301, 302, 303, 307, 308].contains(response.status.code),
                   let location = response.headers.first(name: "location"), !location.isEmpty {
                    guard totalRedirects < 3 else { throw ProbeError.redirectLimit }
                    guard let next = URL(string: location, relativeTo: endpoint)?.absoluteURL
                    else { throw ProbeError.missingRedirect }
                    endpoint = try approved(next)
                    redirects += 1
                    totalRedirects += 1
                    continue
                }
                let data = response.body.map { Data($0.readableBytesView) } ?? Data()
                let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let fields = plist ?? json ?? [:]
                let secrets = [email, password, signature]
                let summary = Summary(
                    variant: variant, endpoint: endpointDescription(endpoint), status: response.status.code,
                    redirects: redirects, locationPresent: response.headers.first(name: "location") != nil,
                    responseKind: plist != nil ? "plist" : json != nil ? "json" : "other",
                    failureType: sanitized(fields["failureType"], secrets: secrets),
                    customerMessage: sanitized(fields["customerMessage"], secrets: secrets),
                    explanation: sanitized((fields["dialog"] as? [String: Any])?["explanation"], secrets: secrets)
                )
                summaries.append(summary)
                print("SAP_PROBE_SUMMARY \(String(decoding: try encoder.encode(summary), as: UTF8.self))")
                break
            }
        }
        let fingerprints = summaries.map { "\($0.status)|\($0.failureType ?? "")|\($0.customerMessage ?? "")|\($0.explanation ?? "")" }
        let observation = summaries.count == 3 && Set(fingerprints).count == 1
            ? "signed, unsigned and corrupted responses are indistinguishable"
            : "transport observations only; inspect explicit server fields"
        let conclusion = ["observation": observation, "signature_acceptance": "not independently established by this probe"]
        print("SAP_PROBE_CONCLUSION \(String(decoding: try encoder.encode(conclusion), as: UTF8.self))")
    }
}
