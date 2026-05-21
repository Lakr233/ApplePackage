//
//  CookieTests.swift
//  ApplePackage
//
//  Created on 2026/5/21.
//

@testable import ApplePackage
import AsyncHTTPClient
import XCTest

final class ApplePackageCookieTests: XCTestCase {
    func testBuildCookieHeaderMatchesLeadingDotDomain() throws {
        let endpoint = try XCTUnwrap(URL(string: "https://p45-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"))
        let cookies = [
            Cookie(
                name: "mz_at0",
                value: "session",
                path: "/",
                domain: ".itunes.apple.com",
                expiresAt: Date().addingTimeInterval(60).timeIntervalSince1970,
                httpOnly: true,
                secure: true
            ),
        ]

        let headers = cookies.buildCookieHeader(endpoint)
        XCTAssertEqual(headers.count, 1)
        XCTAssertEqual(headers.first?.0, "Cookie")
        XCTAssertEqual(headers.first?.1, "mz_at0=session")
    }

    func testMergeCookiesKeepsSameNameAcrossDomainsAndPaths() throws {
        var cookies: [Cookie] = []
        cookies.mergeCookies([
            try XCTUnwrap(HTTPClient.Cookie(header: "X-Dsid=apple; Domain=.apple.com; Path=/", defaultDomain: "buy.itunes.apple.com")),
            try XCTUnwrap(HTTPClient.Cookie(header: "X-Dsid=volume; Domain=.volume.itunes.apple.com; Path=/", defaultDomain: "buy.itunes.apple.com")),
            try XCTUnwrap(HTTPClient.Cookie(header: "X-Dsid=webobjects; Domain=.apple.com; Path=/WebObjects", defaultDomain: "buy.itunes.apple.com")),
        ])

        XCTAssertEqual(cookies.count, 3)

        let values = Set(cookies.map(\.value))
        XCTAssertEqual(values, ["apple", "volume", "webobjects"])
    }
}
