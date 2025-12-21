//
//  Purchase.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AsyncHTTPClient
import Foundation

public enum Purchase {
    public nonisolated static func purchase(
        account: inout Account,
        app: Software
    ) async throws {
        let deviceIdentifier = Configuration.deviceIdentifier

        if (app.price ?? 0) > 0 {
            try ensureFailed("purchasing paid apps is not supported")
        }

        do {
            try await purchaseWithParams(account: &account, app: app, guid: deviceIdentifier, pricingParameters: "STDQ")
        } catch let error as NSError {
            if error.localizedDescription.contains("item is temporarily unavailable") {
                try await purchaseWithParams(account: &account, app: app, guid: deviceIdentifier, pricingParameters: "GAME")
            } else {
                throw error
            }
        }
    }

    private nonisolated static func purchaseWithParams(
        account: inout Account,
        app: Software,
        guid: String,
        pricingParameters: String
    ) async throws {
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

        let request = try makeRequest(
            account: account,
            app: app,
            guid: guid,
            pricingParameters: pricingParameters
        )
        let response = try await client.execute(request: request).get()

        account.cookie.mergeCookies(response.cookies)

        try ensure(response.status == .ok, "purchase request failed with status \(response.status.code)")

        guard var body = response.body,
              let bytes = body.readBytes(length: body.readableBytes)
        else {
            try ensureFailed("response body is empty")
        }
        let data = Data(bytes)

        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any]
        guard let dict = plist else { try ensureFailed("invalid response") }

        if let failureType = dict["failureType"] as? String {
            switch failureType {
            case "2059":
                try ensureFailed("item is temporarily unavailable")
            case "2034":
                try ensureFailed("password token is expired")
            default:
                if let customerMessage = dict["customerMessage"] as? String {
                    if customerMessage == "Subscription Required" {
                        try ensureFailed("subscription required")
                    }
                    try ensureFailed(customerMessage)
                }
                try ensureFailed("purchase failed: \(failureType)")
            }
        }

        if let jingleDocType = dict["jingleDocType"] as? String,
           let status = dict["status"] as? Int
        {
            try ensure(jingleDocType == "purchaseSuccess" && status == 0, "failed to purchase app")
        } else {
            try ensureFailed("invalid purchase response")
        }
    }

    private nonisolated static func makeRequest(
        account: Account,
        app: Software,
        guid: String,
        pricingParameters: String
    ) throws -> HTTPClient.Request {
        let payload: [String: Any] = [
            "appExtVrsId": "0",
            "hasAskedToFulfillPreorder": "true",
            "buyWithoutAuthorization": "true",
            "hasDoneAgeCheck": "true",
            "guid": guid,
            "needDiv": "0",
            "origPage": "Software-\(app.id)",
            "origPageLocation": "Buy",
            "price": "0",
            "pricingParameters": pricingParameters,
            "productType": "C",
            "salableAdamId": app.id,
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)

        var headers: [(String, String)] = [
            ("Content-Type", "application/x-apple-plist"),
            ("User-Agent", Configuration.userAgent),
            ("iCloud-DSID", account.directoryServicesIdentifier),
            ("X-Dsid", account.directoryServicesIdentifier),
            ("X-Apple-Store-Front", "\(account.store)-1"),
            ("X-Token", account.passwordToken),
        ]

        for item in account.cookie.buildCookieHeader(URL(string: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/buyProduct")!) {
            headers.append(item)
        }

        return try .init(
            url: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/buyProduct",
            method: .POST,
            headers: .init(headers),
            body: .data(data)
        )
    }
}
