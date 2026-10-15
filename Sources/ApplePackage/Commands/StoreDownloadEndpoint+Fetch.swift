//
//  StoreDownloadEndpoint+Fetch.swift
//  ApplePackage
//
//  Created on 2026/6/12.
//

import AsyncHTTPClient
import Foundation
import NIOHTTP1

extension StoreDownloadEndpoint {
    /// Fetches the product info from the volumeStore endpoint, falling back to
    /// the dispatch endpoints the way ipatool does: redownload when volumeStore
    /// rejects the request (5002), returns no items, or reports the item as no
    /// longer available; then updateProduct for a pinned version redownload
    /// answers with an empty HTTP 500 or the same availability message.
    static func fetchProductWithFallback(
        client: HTTPClient,
        account: inout Account,
        app: Software,
        deviceIdentifier: String,
        externalVersionID: String
    ) async throws -> [String: Any] {
        let dict = try await StoreDownloadEndpoint.volumeStore.fetchProduct(
            client: client,
            account: &account,
            app: app,
            deviceIdentifier: deviceIdentifier,
            externalVersionID: externalVersionID
        )

        let failureType = dict["failureType"] as? String
        guard failureType == retryableFailureType || isEmpty(dict) || isUnavailable(dict) else {
            return dict
        }
        APLogger.info("store: volumeStore answered without items (failureType: \(failureType ?? "-")), trying redownload")

        // An unpinned redownload can fail or return another platform's build,
        // so select the current iOS version first.
        var versionID = externalVersionID
        if versionID.isEmpty {
            guard let resolved = await latestExternalVersionID(account: account, app: app) else {
                return dict
            }
            versionID = resolved
        }

        let redownload = try await StoreDownloadEndpoint.redownload.send(
            client: client,
            account: &account,
            app: app,
            deviceIdentifier: deviceIdentifier,
            externalVersionID: versionID
        )
        let redownloadEmpty500 = redownload.status == .internalServerError && redownload.dict == nil
        if redownloadEmpty500 || redownload.dict.map(isUnavailable) == true {
            APLogger.info("store: redownload cannot serve version \(versionID), trying updateProduct")
            let update = try await StoreDownloadEndpoint.update.send(
                client: client,
                account: &account,
                app: app,
                deviceIdentifier: deviceIdentifier,
                externalVersionID: versionID
            )
            return try update.validated()
        }
        return try redownload.validated()
    }

    /// No failure, no message, no items: volumeStore's silent refusal.
    private static func isEmpty(_ dict: [String: Any]) -> Bool {
        (dict["failureType"] as? String ?? "").isEmpty
            && (dict["customerMessage"] as? String ?? "").isEmpty
            && ((dict["songList"] as? [Any])?.isEmpty ?? true)
    }

    /// The message-only "No Longer Available" answer; other messages keep
    /// their normal error handling.
    private static func isUnavailable(_ dict: [String: Any]) -> Bool {
        let message = (dict["customerMessage"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return (dict["failureType"] as? String ?? "").isEmpty
            && ((dict["songList"] as? [Any])?.isEmpty ?? true)
            && (message == "no longer available" || message.hasSuffix(" no longer available"))
    }

    private static func latestExternalVersionID(account: Account, app: Software) async -> String? {
        guard let countryCode = Configuration.countryCode(for: account.store) else { return nil }
        for entityType in [EntityType.iPhone, .iPad] {
            if let metadata = try? await PlatformVersionLookup.lookup(
                appID: app.id,
                countryCode: countryCode,
                entityType: entityType
            ) {
                return metadata.externalVersionID
            }
        }
        APLogger.info("store: unable to resolve the latest version of \(app.id) for redownload")
        return nil
    }

    private struct ProductResponse {
        var status: HTTPResponseStatus
        var dict: [String: Any]?

        func validated() throws -> [String: Any] {
            try ensure(status == .ok, Strings.requestFailed(status: status.code))
            guard let dict else { try ensureFailed(Strings.invalidResponse) }
            return dict
        }
    }

    /// Runs the product request against this endpoint and requires an HTTP 200 plist.
    func fetchProduct(
        client: HTTPClient,
        account: inout Account,
        app: Software,
        deviceIdentifier: String,
        externalVersionID: String
    ) async throws -> [String: Any] {
        try await send(
            client: client,
            account: &account,
            app: app,
            deviceIdentifier: deviceIdentifier,
            externalVersionID: externalVersionID
        ).validated()
    }

    /// Runs the product request against this endpoint, following pod redirects,
    /// and returns the status with the parsed plist, if any.
    private func send(
        client: HTTPClient,
        account: inout Account,
        app: Software,
        deviceIdentifier: String,
        externalVersionID: String
    ) async throws -> ProductResponse {
        var currentURL = try url(pod: account.pod, deviceIdentifier: deviceIdentifier)
        var redirectAttempt = 0
        var finalResponse: HTTPClient.Response?
        let maxRedirects = 3

        while redirectAttempt <= maxRedirects {
            let request = try makeRequest(
                account: account,
                app: app,
                url: currentURL,
                guid: deviceIdentifier,
                externalVersionID: externalVersionID
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

        guard var body = finalResponse.body,
              let data = body.readData(length: body.readableBytes),
              !data.isEmpty
        else {
            return ProductResponse(status: finalResponse.status, dict: nil)
        }

        let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any]
        return ProductResponse(status: finalResponse.status, dict: plist)
    }

    private func makeRequest(
        account: Account,
        app: Software,
        url: URL,
        guid: String,
        externalVersionID: String
    ) throws -> HTTPClient.Request {
        var payload: [String: Any] = [
            "creditDisplay": "",
            "guid": guid,
            "salableAdamId": app.id,
            "serialNumber": "0",
        ]

        if !externalVersionID.isEmpty {
            payload[externalVersionIDKey] = externalVersionID
        }

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
