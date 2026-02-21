import Foundation

internal enum ApplePackageOperation: Hashable {
    case search
    case lookup
    case fetchBag
    case authenticate
    case rotatePasswordToken
    case purchase
    case listVersions
    case getVersionMetadata
    case download
}

internal enum ApplePackageBackendKind: String, Hashable {
    case goIPATool = "go"
}

internal enum ApplePackageBackendError: Error {
    case unavailable(String)
    case unsupportedOperation(ApplePackageOperation)
}

internal protocol ApplePackageBackend {
    var kind: ApplePackageBackendKind { get }
    var isAvailable: Bool { get }

    func supports(_ operation: ApplePackageOperation) -> Bool

    func search(
        term: String,
        countryCode: String,
        limit: Int,
        entityType: EntityType
    ) async throws -> [Software]

    func lookup(
        bundleID: String,
        countryCode: String
    ) async throws -> Software

    func fetchBag() async throws -> Bag.BagOutput

    func authenticate(
        email: String,
        password: String,
        code: String,
        cookies: [Cookie]
    ) async throws -> Account

    func rotatePasswordToken(for account: inout Account) async throws

    func purchase(
        account: inout Account,
        app: Software
    ) async throws

    func listVersions(
        account: inout Account,
        bundleIdentifier: String
    ) async throws -> [String]

    func getVersionMetadata(
        account: inout Account,
        app: Software,
        versionID: String
    ) async throws -> VersionMetadata

    func download(
        account: inout Account,
        app: Software,
        externalVersionID: String?
    ) async throws -> DownloadOutput
}

internal extension ApplePackageBackend {
    func supports(_ operation: ApplePackageOperation) -> Bool {
        _ = operation
        return true
    }

    func rotatePasswordToken(for account: inout Account) async throws {
        account = try await authenticate(
            email: account.email,
            password: account.password,
            code: "",
            cookies: account.cookie
        )
    }
}
