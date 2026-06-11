//
//  Download.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AsyncHTTPClient
import Foundation

public enum Download {
    public static func download(
        account: inout Account,
        app: Software,
        externalVersionID: String? = nil
    ) async throws -> DownloadOutput {
        let deviceIdentifier = Configuration.deviceIdentifier

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

        var result = try await requestProduct(
            client: client,
            account: &account,
            app: app,
            guid: deviceIdentifier,
            externalVersionID: externalVersionID ?? "",
            endpoint: .volumeStore
        )

        if result == nil {
            APLogger.debug("download: volumeStore rejected with 5002, retrying via redownload endpoint")
            result = try await requestProduct(
                client: client,
                account: &account,
                app: app,
                guid: deviceIdentifier,
                externalVersionID: externalVersionID ?? "",
                endpoint: .redownload
            )
        }

        guard let dict = result else {
            try ensureFailed("\(Strings.downloadFailed): \(StoreDownloadEndpoint.retryableFailureType)")
        }

        guard let items = dict["songList"] as? [[String: Any]], !items.isEmpty else {
            try ensureFailed(Strings.noItemsInResponse)
        }

        let item = items[0]
        guard let url = item["URL"] as? String else {
            try ensureFailed(Strings.missingDownloadURL)
        }

        guard var metadata = item["metadata"] as? [String: Any] else {
            try ensureFailed(Strings.missingMetadata)
        }

        let version = (metadata["bundleShortVersionString"] as? String)
        let bundleVersion = metadata["bundleVersion"] as? String

        guard let version, let bundleVersion else {
            try ensureFailed(Strings.missingRequiredInfo)
        }

        metadata["apple-id"] = account.email
        metadata["userName"] = account.email

        let iTunesMetadata = try PropertyListSerialization.data(
            fromPropertyList: metadata,
            format: .binary,
            options: 0
        )

        var sinfs: [Sinf] = []
        if let sinfData = item["sinfs"] as? [[String: Any]] {
            for sinfItem in sinfData {
                if let id = sinfItem["id"] as? Int64,
                   let data = sinfItem["sinf"] as? Data
                {
                    sinfs.append(Sinf(id: id, sinf: data))
                } else {
                    try ensureFailed(Strings.invalidSinfItem)
                }
            }
        }
        try ensure(!sinfs.isEmpty, Strings.noSinfFound)

        return DownloadOutput(
            downloadURL: url,
            sinfs: sinfs,
            bundleShortVersionString: version,
            bundleVersion: bundleVersion,
            iTunesMetadata: iTunesMetadata
        )
    }

    /// Executes the download product request and parses the plist response.
    /// Returns `nil` when the endpoint rejects the request with failureType 5002
    /// so the caller can retry with the fallback endpoint.
    private static func requestProduct(
        client: HTTPClient,
        account: inout Account,
        app: Software,
        guid: String,
        externalVersionID: String,
        endpoint: StoreDownloadEndpoint
    ) async throws -> [String: Any]? {
        let request = try makeRequest(
            account: account,
            app: app,
            guid: guid,
            externalVersionID: externalVersionID,
            endpoint: endpoint
        )
        let response = try await client.execute(request: request).get()

        APLogger.logResponse(
            status: response.status.code,
            headers: response.headers.map { ($0.name, $0.value) },
            bodySize: response.body?.readableBytes
        )

        account.cookie.mergeCookies(response.cookies)

        try ensure(response.status == .ok, Strings.requestFailed(status: response.status.code))

        guard var body = response.body,
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

        if let failureType = dict["failureType"] as? String {
            let customerMessage = dict["customerMessage"] as? String
            switch failureType {
            case "2034", "2042":
                try ensureFailed(Strings.passwordTokenExpired)
            case "9610":
                throw ApplePackageError.licenseRequired
            case StoreDownloadEndpoint.retryableFailureType:
                return nil
            default:
                if customerMessage == Strings.passwordChanged {
                    try ensureFailed(Strings.passwordTokenExpired)
                }
                if let customerMessage = customerMessage {
                    try ensureFailed(customerMessage)
                }
                try ensureFailed("\(Strings.downloadFailed): \(failureType)")
            }
        }

        return dict
    }

    private static func makeRequest(
        account: Account,
        app: Software,
        guid: String,
        externalVersionID: String,
        endpoint: StoreDownloadEndpoint
    ) throws -> HTTPClient.Request {
        var payload: [String: Any] = [
            "creditDisplay": "",
            "guid": guid,
            "salableAdamId": app.id,
        ]

        if !externalVersionID.isEmpty {
            payload[endpoint.externalVersionIDKey] = externalVersionID
        }

        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)

        var headers: [(String, String)] = [
            ("Content-Type", "application/x-apple-plist"),
            ("User-Agent", Configuration.userAgent),
            ("iCloud-DSID", account.directoryServicesIdentifier),
            ("X-Dsid", account.directoryServicesIdentifier),
        ]

        let url = try endpoint.url(pod: account.pod, deviceIdentifier: nil)

        for item in account.cookie.buildCookieHeader(url) {
            headers.append(item)
        }

        APLogger.logRequest(method: "POST", url: url.absoluteString, headers: headers)

        return try .init(
            url: url.absoluteString,
            method: .POST,
            headers: .init(headers),
            body: .data(data)
        )
    }
}
