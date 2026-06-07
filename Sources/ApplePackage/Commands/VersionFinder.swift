//
//  VersionFinder.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import AsyncHTTPClient
import Foundation

public enum VersionFinder {
    public static func list(
        account: inout Account,
        bundleIdentifier: String,
        entityType: EntityType? = nil,
        externalVersionID: String? = nil
    ) async throws -> [String] {
        guard let countryCode = Configuration.countryCode(for: account.store) else {
            try ensureFailed(Strings.unsupportedStoreIdentifier(account.store))
        }
        let app = try await Lookup.lookup(bundleID: bundleIdentifier, countryCode: countryCode, entityType: entityType)
        let resolvedExternalVersionID: String
        if let externalVersionID {
            resolvedExternalVersionID = externalVersionID
        } else if let entityType {
            let metadata = try await PlatformVersionLookup.lookup(
                appID: app.id,
                countryCode: countryCode,
                entityType: entityType
            )
            resolvedExternalVersionID = metadata.externalVersionID
        } else {
            resolvedExternalVersionID = ""
        }

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

        var volumeStore = true
        var currentURL = try createInitialRequestEndpoint(deviceIdentifier: deviceIdentifier, pod: account.pod, volumeStore: volumeStore)
        let request = try makeRequest(
            account: account,
            app: app,
            url: currentURL,
            guid: deviceIdentifier,
            externalVersionID: resolvedExternalVersionID,
            volumeStore: volumeStore
        )
        let checkResponse = try await client.execute(request: request).get()
        
        guard var body = checkResponse.body,
              let data = body.readData(length: body.readableBytes)
        else {
            try ensureFailed(Strings.responseBodyEmpty)
        }
        
        let checkPlist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any]
        guard let dict = checkPlist else { try ensureFailed(Strings.invalidResponse) }
        
        if (dict.keys.contains("failureType")) {
            if (dict["failureType"] as! String == "5002") {
                volumeStore = false
                currentURL = try createInitialRequestEndpoint(deviceIdentifier: deviceIdentifier, pod: account.pod, volumeStore: volumeStore)
            }
        }
        
        
        var redirectAttempt = 0
        var finalResponse: HTTPClient.Response?
        let maxRedirects = 3

        while redirectAttempt <= maxRedirects {
            let request = try makeRequest(
                account: account,
                app: app,
                url: currentURL,
                guid: deviceIdentifier,
                externalVersionID: resolvedExternalVersionID,
                volumeStore: volumeStore
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
                    if let customerMessage = customerMessage {
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

    private static func createInitialRequestEndpoint(deviceIdentifier: String, pod: String?, volumeStore: Bool) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        if (volumeStore) {
            comps.host = Configuration.storeAPIHost(pod: pod)
            comps.path = "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"
        } else {
            comps.host = "downloaddispatch.itunes.apple.com"
            comps.path = "/r/redownload"
        }
        
        comps.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
        return try comps.url.get()
    }

    public static func makeRequest(
        account: Account,
        app: Software,
        url: URL,
        guid: String,
        externalVersionID: String,
        volumeStore: Bool
    ) throws -> HTTPClient.Request {
        var payload: [String: Any] = [
            "creditDisplay": "",
            "guid": guid,
            "salableAdamId": app.id,
        ]
        
        if (volumeStore) {
            if !externalVersionID.isEmpty {
                payload["externalVersionId"] = externalVersionID
            }
        } else {
            if !externalVersionID.isEmpty {
                payload["appExtVrsId"] = externalVersionID
            }
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
