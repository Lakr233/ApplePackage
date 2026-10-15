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
        public var sap: SAPConfiguration = Bag.defaultSAPConfiguration
    }

    private static let defaultAuthEndpoint = "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/"

    /// Values advertised by init.itunes.apple.com/bag.xml as of 2026-10, used
    /// only when the bag cannot be fetched or parsed.
    static let defaultSAPConfiguration = SAPConfiguration(
        setupURL: URL(string: "https://fpinit.itunes.apple.com/v1/signSapSetup/legacy")!,
        certificateURL: URL(string: "https://s.mzstatic.com/sap/setupCert.plist")!,
        version: SAPConfiguration.supportedVersion
    )

    public static func fetchBag() async throws -> BagOutput {
        let deviceIdentifier = Configuration.deviceIdentifier

        let client = Configuration.makeHTTPClient(redirectConfiguration: .follow(max: 8, allowCycles: false))
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

        // authenticateAccount used to live inside the nested urlBag dict,
        // newer bag responses move it to the plist root
        let urlBag = plist["urlBag"] as? [String: Any] ?? [:]
        let authURLString = (plist["authenticateAccount"] as? String) ?? (urlBag["authenticateAccount"] as? String)

        guard let authURLString,
              let authURL = normalizedAuthEndpoint(from: authURLString)
        else {
            APLogger.debug("bag: no authenticateAccount in plist, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        APLogger.info("bag: auth endpoint resolved to \(authURL)")
        return BagOutput(authEndpoint: authURL, sap: sapConfiguration(from: plist, urlBag: urlBag))
    }

    private static func sapConfiguration(from plist: [String: Any], urlBag: [String: Any]) -> SAPConfiguration {
        func value(_ key: String) -> Any? { urlBag[key] ?? plist[key] }
        guard let setup = (value("sign-sap-setup") as? String).flatMap(URL.init(string:)),
              let certificate = (value("sign-sap-setup-cert") as? String).flatMap(URL.init(string:)),
              setup.scheme == "https", certificate.scheme == "https"
        else {
            APLogger.debug("bag: no SAP configuration in plist, using defaults")
            return defaultSAPConfiguration
        }
        let version = (value("sign-sap-version") as? String).flatMap(UInt32.init)
            ?? (value("sign-sap-version") as? Int).map(UInt32.init)
            ?? SAPConfiguration.supportedVersion
        return SAPConfiguration(setupURL: setup, certificateURL: certificate, version: version)
    }

    /// The bag advertises auth endpoints without the trailing slash the login
    /// flow requires: the bare `authenticate` path can answer 301 without a
    /// Location, and the native endpoint additionally needs the `/fast/` sub-path.
    private static func normalizedAuthEndpoint(from urlString: String) -> URL? {
        guard var comps = URLComponents(string: urlString) else { return nil }
        if comps.path.hasSuffix("/wa/authenticate") {
            comps.path += "/"
        } else if comps.host == "auth.itunes.apple.com" {
            var path = comps.path
            while path.hasSuffix("/") {
                path.removeLast()
            }
            if !path.hasSuffix("/fast") {
                path += "/fast"
            }
            comps.path = path + "/"
        }
        return comps.url
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
