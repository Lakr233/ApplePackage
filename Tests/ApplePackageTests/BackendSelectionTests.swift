@testable import ApplePackage
import XCTest

final class ApplePackageBackendSelectionTests: XCTestCase {
    private struct StubBackend: ApplePackageBackend {
        let kind: ApplePackageBackendKind
        let isAvailable: Bool
        let supported: Set<ApplePackageOperation>

        func supports(_ operation: ApplePackageOperation) -> Bool {
            supported.contains(operation)
        }

        func search(
            term: String,
            countryCode: String,
            limit: Int,
            entityType: EntityType
        ) async throws -> [Software] {
            _ = term
            _ = countryCode
            _ = limit
            _ = entityType
            return []
        }

        func lookup(
            bundleID: String,
            countryCode: String
        ) async throws -> Software {
            _ = bundleID
            _ = countryCode
            return Software(
                id: 1,
                bundleID: "com.example.app",
                name: "Example",
                version: "1.0.0",
                artistName: "Example",
                sellerName: "Example",
                description: "Example",
                averageUserRating: 0,
                userRatingCount: 0,
                artworkUrl: "",
                screenshotUrls: [],
                minimumOsVersion: "15.0",
                releaseDate: "2026-01-01T00:00:00Z",
                primaryGenreName: "Utilities"
            )
        }

        func fetchBag() async throws -> Bag.BagOutput {
            Bag.BagOutput(authEndpoint: URL(string: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate")!)
        }

        func authenticate(
            email: String,
            password: String,
            code: String,
            cookies: [Cookie]
        ) async throws -> Account {
            _ = code
            return Account(
                email: email,
                password: password,
                appleId: email,
                store: "143441",
                firstName: "Test",
                lastName: "User",
                passwordToken: "token",
                directoryServicesIdentifier: "1",
                cookie: cookies
            )
        }

        func rotatePasswordToken(for account: inout Account) async throws {
            _ = account
        }

        func purchase(account: inout Account, app: Software) async throws {
            _ = account
            _ = app
        }

        func listVersions(
            account: inout Account,
            bundleIdentifier: String
        ) async throws -> [String] {
            _ = account
            _ = bundleIdentifier
            return []
        }

        func getVersionMetadata(
            account: inout Account,
            app: Software,
            versionID: String
        ) async throws -> VersionMetadata {
            _ = account
            _ = app
            _ = versionID
            return VersionMetadata(displayVersion: "1.0.0", releaseDate: Date(timeIntervalSince1970: 0))
        }

        func download(
            account: inout Account,
            app: Software,
            externalVersionID: String?
        ) async throws -> DownloadOutput {
            _ = account
            _ = app
            _ = externalVersionID
            return DownloadOutput(
                downloadURL: "",
                sinfs: [],
                bundleShortVersionString: "1.0.0",
                bundleVersion: "1",
                iTunesMetadata: Data()
            )
        }
    }

    override func tearDown() {
        ApplePackageBackendResolver.resetTestingOverrides()
        super.tearDown()
    }

    func testPrefersGoBackendWhenAvailable() {
        ApplePackageBackendResolver.resetTestingOverrides()
        ApplePackageBackendResolver.preferredBackendOverride = .goIPATool
        ApplePackageBackendResolver.goAvailabilityOverride = true
        ApplePackageBackendResolver.goBackend = StubBackend(
            kind: .goIPATool,
            isAvailable: true,
            supported: [.authenticate, .search]
        )

        let backend = ApplePackageBackendResolver.backend(for: .authenticate)
        XCTAssertEqual(backend.kind, .goIPATool)
    }

    func testPerformThrowsWhenGoBackendUnavailable() async {
        ApplePackageBackendResolver.resetTestingOverrides()
        ApplePackageBackendResolver.preferredBackendOverride = .goIPATool
        ApplePackageBackendResolver.goAvailabilityOverride = false
        ApplePackageBackendResolver.goBackend = StubBackend(
            kind: .goIPATool,
            isAvailable: false,
            supported: [.authenticate]
        )

        do {
            _ = try await ApplePackageBackendResolver.perform(operation: .authenticate) { _ in
                true
            }
            XCTFail("expected perform to fail when go backend is unavailable")
        } catch let error as ApplePackageBackendError {
            switch error {
            case .unavailable:
                break
            default:
                XCTFail("unexpected backend error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testEnvironmentNativeAliasResolvesToGoBackend() {
        ApplePackageBackendResolver.resetTestingOverrides()
        ApplePackageBackendResolver.environmentProvider = {
            ["APPLEPACKAGE_BACKEND": "native"]
        }
        ApplePackageBackendResolver.goAvailabilityOverride = true

        let backend = ApplePackageBackendResolver.backend(for: .search)
        XCTAssertEqual(backend.kind, .goIPATool)
    }

    func testUnsupportedGoOperationThrows() async {
        ApplePackageBackendResolver.resetTestingOverrides()
        ApplePackageBackendResolver.preferredBackendOverride = .goIPATool
        ApplePackageBackendResolver.goAvailabilityOverride = true
        ApplePackageBackendResolver.goBackend = StubBackend(
            kind: .goIPATool,
            isAvailable: true,
            supported: [.authenticate]
        )

        do {
            _ = try await ApplePackageBackendResolver.perform(operation: .download) { _ in
                true
            }
            XCTFail("expected unsupported operation to fail")
        } catch let error as ApplePackageBackendError {
            switch error {
            case .unavailable:
                break
            default:
                XCTFail("unexpected backend error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
