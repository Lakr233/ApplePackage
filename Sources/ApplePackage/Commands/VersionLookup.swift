//
//  VersionLookup.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AsyncHTTPClient
import Foundation

public enum VersionLookup {
    public static func getVersionMetadata(
        account: inout Account,
        app: Software,
        versionID: String
    ) async throws -> VersionMetadata {
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

        var dict = try await fetchProduct(
            client: client,
            account: &account,
            app: app,
            deviceIdentifier: deviceIdentifier,
            versionID: versionID,
            endpoint: .volumeStore
        )

        if dict["failureType"] as? String == StoreDownloadEndpoint.retryableFailureType {
            APLogger.debug("versionLookup: volumeStore rejected with 5002, retrying via redownload endpoint")
            dict = try await fetchProduct(
                client: client,
                account: &account,
                app: app,
                deviceIdentifier: deviceIdentifier,
                versionID: versionID,
                endpoint: .redownload
            )
        }

        guard let items = dict["songList"] as? [[String: Any]], !items.isEmpty else {
            try ensureFailed(Strings.noItemsInResponse)
        }

        let item = items[0]
        guard let metadata = item["metadata"] as? [String: Any] else {
            try ensureFailed(Strings.missingMetadata)
        }

        guard let bundleShortVersionString = metadata["bundleShortVersionString"] as? String else {
            try ensureFailed(Strings.missingBundleShortVersionString)
        }

        guard let releaseDateString = metadata["releaseDate"] as? String,
              let releaseDate = ISO8601DateFormatter().date(from: releaseDateString)
        else {
            try ensureFailed(Strings.missingOrInvalidReleaseDate)
        }

        return VersionMetadata(displayVersion: bundleShortVersionString, releaseDate: releaseDate)
    }

    /// Runs the product request against the given endpoint, following pod
    /// redirects, and returns the parsed plist response.
    private static func fetchProduct(
        client: HTTPClient,
        account: inout Account,
        app: Software,
        deviceIdentifier: String,
        versionID: String,
        endpoint: StoreDownloadEndpoint
    ) async throws -> [String: Any] {
        var currentURL = try endpoint.url(pod: account.pod, deviceIdentifier: deviceIdentifier)
        var redirectAttempt = 0
        var finalResponse: HTTPClient.Response?
        let maxRedirects = 3

        while redirectAttempt <= maxRedirects {
            let request = try makeRequest(
                account: account,
                app: app,
                url: currentURL,
                guid: deviceIdentifier,
                versionID: versionID,
                endpoint: endpoint
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

        return dict
    }

    private static func makeRequest(
        account: Account,
        app: Software,
        url: URL,
        guid: String,
        versionID: String,
        endpoint: StoreDownloadEndpoint
    ) throws -> HTTPClient.Request {
        var payload: [String: Any] = [
            "creditDisplay": "",
            "guid": guid,
            "salableAdamId": app.id,
        ]
        payload[endpoint.externalVersionIDKey] = versionID

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
