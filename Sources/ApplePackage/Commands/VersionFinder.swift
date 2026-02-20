//
//  VersionFinder.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import AsyncHTTPClient
import Foundation

public enum VersionFinder {
    public nonisolated static func list(
        account: inout Account,
        bundleIdentifier: String
    ) async throws -> [String] {
        guard let countryCode = Configuration.countryCode(for: account.store) else {
            try ensureFailed(Strings.unsupportedStoreIdentifier(account.store))
        }
        let app = try await Lookup.lookup(bundleID: bundleIdentifier, countryCode: countryCode)

        let client = HTTPClient(
            eventLoopGroupProvider: .singleton,
            configuration: .init(
                tlsConfiguration: Configuration.tlsConfiguration,
                redirectConfiguration: .disallow,
                timeout: .init(
                    connect: .seconds(Configuration.timeoutConnect),
                    read: .seconds(Configuration.timeoutRead)
                )
            ).then { $0.httpVersion = .http1Only }
        )
        defer { _ = client.shutdown() }

        let deviceIdentifier = Configuration.deviceIdentifier

        var currentURL = try createInitialRequestEndpoint(deviceIdentifier: deviceIdentifier, pod: account.pod)
        var redirectAttempt = 0
        var finalResponse: HTTPClient.Response?
        let maxRedirects = 3

        while redirectAttempt <= maxRedirects {
            let request = try makeRequest(
                account: account,
                app: app,
                url: currentURL,
                guid: deviceIdentifier
            )
            let response = try await client.execute(request: request).get()
            defer { finalResponse = response }

            APLogger.logResponse(
                status: response.status.code,
                headers: response.headers.map { ($0.name, $0.value) },
                bodySize: response.body?.readableBytes
            )

            account.cookie.mergeCookies(response.cookies)

            if response.status == .found {
                guard let location = response.headers.first(name: "location"),
                      let newURL = URL(string: location)
                else {
                    try ensureFailed(Strings.failedToRetrieveRedirect)
                }
                currentURL = newURL
                redirectAttempt += 1
                continue
            }
            break
        }

        guard let finalResponse else { try ensureFailed(Strings.noResponseReceived) }

        try ensure(finalResponse.status == .ok, Strings.requestFailed(status: finalResponse.status.code))

        guard var body = finalResponse.body,
              let data = body.readData(length: body.readableBytes)
        else {
            try ensureFailed(Strings.responseBodyEmpty)
        }

        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any]
        guard let dict = plist else { try ensureFailed(Strings.invalidResponse) }

        guard let items = dict["songList"] as? [[String: Any]], !items.isEmpty else {
            if let failureType = dict["failureType"] as? String {
                let customerMessage = dict["customerMessage"] as? String
                switch failureType {
                case "2034", "2042":
                    try ensureFailed(Strings.passwordTokenExpired)
                case "9610":
                    throw ApplePackageError.licenseRequired
                default:
                    if customerMessage == Strings.passwordChanged {
                        try ensureFailed(Strings.passwordTokenExpired)
                    }
                    if let customerMessage {
                        try ensureFailed(customerMessage)
                    }
                    try ensureFailed(Strings.noItemsInResponse)
                }
            } else {
                try ensureFailed(Strings.noItemsInResponse)
            }
        }

        let item = items[0]
        guard let metadata = item["metadata"] as? [String: Any],
              let identifiers = metadata["softwareVersionExternalIdentifiers"] as? [Any]
        else {
            try ensureFailed(Strings.missingVersionIdentifiers)
        }

        let result = identifiers.map { "\($0)" }
        try ensure(!result.isEmpty, Strings.noVersionsFound)

        return result
    }

    private nonisolated static func createInitialRequestEndpoint(deviceIdentifier: String, pod: String?) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = Configuration.storeAPIHost(pod: pod)
        comps.path = "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"
        comps.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
        return try comps.url.get()
    }

    private nonisolated static func makeRequest(
        account: Account,
        app: Software,
        url: URL,
        guid: String
    ) throws -> HTTPClient.Request {
        let payload: [String: Any] = [
            "creditDisplay": "",
            "guid": guid,
            "salableAdamId": app.id,
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)

        var headers: [(String, String)] = [
            ("Content-Type", "application/x-apple-plist"),
            ("User-Agent", Configuration.userAgent),
            ("iCloud-DSID", account.directoryServicesIdentifier),
            ("X-Dsid", account.directoryServicesIdentifier),
        ]

        for item in account.cookie.buildCookieHeader(url) {
            headers.append(item)
        }

        APLogger.logRequest(method: "POST", url: url.absoluteString, headers: headers)

        return try .init(
            url: url,
            method: .POST,
            headers: .init(headers),
            body: .data(data)
        )
    }
}
