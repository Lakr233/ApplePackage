//
//  DownloadTests.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AppKit
@testable import ApplePackage
import XCTest

final class ApplePackageDownloadTests: XCTestCase {
    override class func setUp() {
        TestConfiguration.bootstrap()
    }

    @MainActor func testDownload() async throws {
        try XCTSkipUnless(TestConfiguration.hasAuthenticatedAccount, "No authenticated account available")

        let testBundleID = "developer.apple.wwdc-Release"
        do {
            try await withAccount(email: testAccountEmail) { account in
                try await Authenticator.rotatePasswordToken(for: &account)
                let countryCode = Configuration.countryCode(for: account.store) ?? "US"
                let app = try await Lookup.lookup(bundleID: testBundleID, countryCode: countryCode)
                let output = try await Download.download(account: &account, app: app)
                print("download test passed: \(output.downloadURL)")
                print("    Bundle Short Version: \(output.bundleShortVersionString)")
                print("    Bundle Version: \(output.bundleVersion)")
                print("    SINFs count: \(output.sinfs.count)")

                XCTAssertFalse(output.downloadURL.isEmpty, "Download URL should not be empty")
                XCTAssertNotNil(output.bundleShortVersionString, "Bundle short version should not be nil")
                XCTAssertGreaterThan(output.sinfs.count, 0, "Should have at least one SINF")
            }
        } catch {
            XCTFail("download test failed: \(error)")
        }
    }
}
