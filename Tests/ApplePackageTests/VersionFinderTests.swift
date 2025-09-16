//
//  VersionFinderTests.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import AppKit
@testable import ApplePackage
import XCTest

final class ApplePackageVersionFinderTests: XCTestCase {
    @MainActor func testListVersions() async throws {
        let testItem = "com.tencent.xin"
        do {
            try await withAccount(email: testAccountEmail) { account in
                let versions = try await VersionFinder.list(account: &account, bundleIdentifier: testItem)
                print("versions test passed with \(versions.count) versions: \(versions)")
            }
        } catch {
            XCTFail("list versions test failed: \(error)")
        }
    }

    @MainActor func testListVersionsInvalidBundle() async throws {
        do {
            try await withAccount(email: testAccountEmail) { account in
                _ = try await VersionFinder.list(account: &account, bundleIdentifier: "invalid.bundle.id")
                XCTFail("should fail with invalid bundle identifier")
            }
        } catch {
            // good
        }
    }
}
