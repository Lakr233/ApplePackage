//
//  Bag.swift
//  ApplePackage
//
//  Created on 2026/2/20.
//

import AsyncHTTPClient
import Foundation

public enum Bag {
    public struct BagOutput {
        public var authEndpoint: URL
    }

    private static let defaultAuthEndpoint = "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate"

    public nonisolated static func fetchBag() async throws -> BagOutput {
        let deviceIdentifier = Configuration.deviceIdentifier

        let client = HTTPClient(
            eventLoopGroupProvider: .singleton,
            configuration: .init(
                tlsConfiguration: Configuration.tlsConfiguration,
                redirectConfiguration: .follow(max: 8, allowCycles: false),
                timeout: .init(
                    connect: .seconds(Configuration.timeoutConnect),
                    read: .seconds(Configuration.timeoutRead)
                )
            ).then { $0.httpVersion = .http1Only }
        )
        defer { _ = client.shutdown() }

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "init.itunes.apple.com"
        comps.path = "/bag.xml"
        comps.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
        guard let url = comps.url else {
            APLogger.debug("bag: failed to construct URL, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        let headers: [(String, String)] = [
            ("User-Agent", Configuration.userAgent),
            ("Accept", "application/xml"),
        ]

        APLogger.logRequest(method: "GET", url: url.absoluteString, headers: headers)

        let request = try HTTPClient.Request(
            url: url.absoluteString,
            method: .GET,
            headers: .init(headers)
        )

        let response = try await client.execute(request: request).get()

        APLogger.logResponse(
            status: response.status.code,
            headers: response.headers.map { ($0.name, $0.value) },
            bodySize: response.body?.readableBytes
        )

        guard var body = response.body,
              let data = body.readData(length: body.readableBytes)
        else {
            APLogger.debug("bag: empty response body, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        let plistData = extractPlistData(from: data)

        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            APLogger.debug("bag: failed to parse plist, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        // authenticateAccount lives inside the nested urlBag dict
        let urlBag = plist["urlBag"] as? [String: Any] ?? plist

        guard let authURLString = urlBag["authenticateAccount"] as? String,
              let authURL = URL(string: authURLString)
        else {
            APLogger.debug("bag: no authenticateAccount in plist, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        APLogger.info("bag: auth endpoint resolved to \(authURL)")
        return BagOutput(authEndpoint: authURL)
    }

    /// The bag XML response wraps the plist inside `<Document><Protocol><plist>...</plist>`.
    /// Extract the `<plist>...</plist>` portion so PropertyListSerialization can parse it.
    /// If the data is already a bare plist, return it as-is.
    private static func extractPlistData(from data: Data) -> Data {
        guard let xmlString = String(data: data, encoding: .utf8),
              let startRange = xmlString.range(of: "<plist"),
              let endRange = xmlString.range(of: "</plist>")
        else {
            return data
        }
        return Data(xmlString[startRange.lowerBound ..< endRange.upperBound].utf8)
    }
}
