//
//  Lookup.swift
//
//
//  Created by qaq on 2025/9/14.
//

import AsyncHTTPClient
import Foundation

public enum Lookup {
    private struct LookupResponse: Codable {
        var resultCount: Int
        var results: [Software]
    }

    public nonisolated static func lookup(
        bundleID: String,
        countryCode: String
    ) async throws -> Software {
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

        let request = try makeRequest(bundleID: bundleID, countryCode: countryCode)
        let response = try await client.execute(request: request).get()

        try ensure(response.status == .ok, "lookup request failed with status \(response.status.code)")

        guard var body = response.body,
              let data = body.readData(length: body.readableBytes)
        else {
            try ensureFailed("response body is empty")
        }

        let decoder = JSONDecoder()
        let lookupResponse = try decoder.decode(LookupResponse.self, from: data)
        try ensure(lookupResponse.resultCount > 0, "no results found for bundle ID \(bundleID)")
        try ensure(lookupResponse.results.count == 1, "unexpected number of results: \(lookupResponse.resultCount)")

        return lookupResponse.results.first!
    }

    private nonisolated static func makeRequest(
        bundleID: String,
        countryCode: String
    ) throws -> HTTPClient.Request {
        let url = try createLookupURL(bundleID: bundleID, countryCode: countryCode)
        return try .init(
            url: url.absoluteString,
            method: .GET,
            headers: .init([("User-Agent", Configuration.userAgent)]),
            body: .none
        )
    }

    private nonisolated static func createLookupURL(
        bundleID: String,
        countryCode: String
    ) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "itunes.apple.com"
        comps.path = "/lookup"
        comps.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: countryCode),
            URLQueryItem(name: "entity", value: "software,iPadSoftware"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "media", value: "software"),
        ]
        return try comps.url.get()
    }
}
