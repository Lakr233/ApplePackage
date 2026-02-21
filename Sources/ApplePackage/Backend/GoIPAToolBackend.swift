import Foundation

#if canImport(GoIPAToolBindings)
import GoIPAToolBindings
#endif

internal struct GoIPAToolBackend: ApplePackageBackend {
    internal let kind: ApplePackageBackendKind = .goIPATool

    internal var isAvailable: Bool {
        GoIPAToolBridge.isAvailable
    }

    internal func supports(_ operation: ApplePackageOperation) -> Bool {
        GoIPAToolBridge.supportedOperations.contains(operation)
    }

    internal func search(
        term: String,
        countryCode: String,
        limit: Int,
        entityType: EntityType
    ) async throws -> [Software] {
        try GoIPAToolBridge.search(
            term: term,
            countryCode: countryCode,
            limit: limit,
            entityType: entityType
        )
    }

    internal func lookup(
        bundleID: String,
        countryCode: String
    ) async throws -> Software {
        try GoIPAToolBridge.lookup(bundleID: bundleID, countryCode: countryCode)
    }

    internal func fetchBag() async throws -> Bag.BagOutput {
        try GoIPAToolBridge.fetchBag()
    }

    internal func authenticate(
        email: String,
        password: String,
        code: String,
        cookies: [Cookie]
    ) async throws -> Account {
        try GoIPAToolBridge.authenticate(
            email: email,
            password: password,
            code: code,
            cookies: cookies,
            deviceIdentifier: Configuration.deviceIdentifier,
            userAgent: Configuration.userAgent
        )
    }

    internal func rotatePasswordToken(for account: inout Account) async throws {
        account = try GoIPAToolBridge.authenticate(
            email: account.email,
            password: account.password,
            code: "",
            cookies: account.cookie,
            deviceIdentifier: Configuration.deviceIdentifier,
            userAgent: Configuration.userAgent
        )
    }

    internal func purchase(
        account: inout Account,
        app: Software
    ) async throws {
        let output = try GoIPAToolBridge.purchase(
            account: account,
            app: app,
            deviceIdentifier: Configuration.deviceIdentifier,
            userAgent: Configuration.userAgent
        )
        account = output.account
    }

    internal func listVersions(
        account: inout Account,
        bundleIdentifier: String
    ) async throws -> [String] {
        let output = try GoIPAToolBridge.listVersions(
            account: account,
            bundleIdentifier: bundleIdentifier,
            deviceIdentifier: Configuration.deviceIdentifier,
            userAgent: Configuration.userAgent
        )
        account = output.account
        return output.versions
    }

    internal func getVersionMetadata(
        account: inout Account,
        app: Software,
        versionID: String
    ) async throws -> VersionMetadata {
        let output = try GoIPAToolBridge.getVersionMetadata(
            account: account,
            app: app,
            versionID: versionID,
            deviceIdentifier: Configuration.deviceIdentifier,
            userAgent: Configuration.userAgent
        )
        account = output.account
        return output.metadata
    }

    internal func download(
        account: inout Account,
        app: Software,
        externalVersionID: String?
    ) async throws -> DownloadOutput {
        let output = try GoIPAToolBridge.download(
            account: account,
            app: app,
            externalVersionID: externalVersionID,
            deviceIdentifier: Configuration.deviceIdentifier,
            userAgent: Configuration.userAgent
        )
        account = output.account

        let sinfs = try output.sinfs.map { sinf -> Sinf in
            guard let payload = Data(base64Encoded: sinf.sinfBase64) else {
                throw NSError(
                    domain: "GoIPAToolBackend",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "invalid sinf payload in go backend response"]
                )
            }
            return Sinf(id: sinf.id, sinf: payload)
        }

        guard let metadata = Data(base64Encoded: output.iTunesMetadataBase64) else {
            throw NSError(
                domain: "GoIPAToolBackend",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "invalid iTunesMetadata in go backend response"]
            )
        }

        return DownloadOutput(
            downloadURL: output.downloadURL,
            sinfs: sinfs,
            bundleShortVersionString: output.bundleShortVersionString,
            bundleVersion: output.bundleVersion,
            iTunesMetadata: metadata
        )
    }
}

private enum GoIPAToolBridge {
    private struct Envelope<Result: Decodable>: Decodable {
        let ok: Bool
        let result: Result?
        let error: String?
    }

    private struct SearchRequest: Encodable {
        let term: String
        let countryCode: String
        let limit: Int
        let entityType: String
    }

    private struct LookupRequest: Encodable {
        let bundleID: String
        let countryCode: String
    }

    private struct AuthenticateRequest: Encodable {
        let email: String
        let password: String
        let code: String
        let cookies: [Cookie]
        let deviceIdentifier: String
        let userAgent: String
    }

    private struct PurchaseRequest: Encodable {
        let account: Account
        let app: Software
        let deviceIdentifier: String
        let userAgent: String
    }

    private struct VersionListRequest: Encodable {
        let account: Account
        let bundleIdentifier: String
        let deviceIdentifier: String
        let userAgent: String
    }

    private struct VersionMetadataRequest: Encodable {
        let account: Account
        let app: Software
        let versionID: String
        let deviceIdentifier: String
        let userAgent: String
    }

    private struct DownloadRequest: Encodable {
        let account: Account
        let app: Software
        let externalVersionID: String
        let deviceIdentifier: String
        let userAgent: String
    }

    private struct BagRequest: Encodable {
        let deviceIdentifier: String
        let userAgent: String
    }

    struct PurchaseResult: Decodable {
        let account: Account
    }

    struct VersionListResult: Decodable {
        let account: Account
        let versions: [String]
    }

    struct VersionMetadataResult: Decodable {
        let account: Account
        let metadata: VersionMetadata
    }

    struct BagResult: Decodable {
        let authEndpoint: String
    }

    struct DownloadResult: Decodable {
        let account: Account
        let downloadURL: String
        let sinfs: [DownloadSinf]
        let bundleShortVersionString: String
        let bundleVersion: String
        let iTunesMetadataBase64: String
    }

    struct DownloadSinf: Decodable {
        let id: Int64
        let sinfBase64: String
    }

    static var isAvailable: Bool {
        #if canImport(GoIPAToolBindings)
            return true
        #else
            return false
        #endif
    }

    static var supportedOperations: Set<ApplePackageOperation> {
        #if canImport(GoIPAToolBindings)
            return [
                .search,
                .lookup,
                .fetchBag,
                .authenticate,
                .rotatePasswordToken,
                .purchase,
                .listVersions,
                .getVersionMetadata,
                .download,
            ]
        #else
            return []
        #endif
    }

    static func search(
        term: String,
        countryCode: String,
        limit: Int,
        entityType: EntityType
    ) throws -> [Software] {
        #if canImport(GoIPAToolBindings)
            return try invoke(
                operation: .search,
                request: SearchRequest(
                    term: term,
                    countryCode: countryCode,
                    limit: limit,
                    entityType: entityType.rawValue
                ),
                callWithInput: { APGoIPAToolSearch($0) }
            )
        #else
            _ = term
            _ = countryCode
            _ = limit
            _ = entityType
            throw ApplePackageBackendError.unavailable("go backend binary is not linked")
        #endif
    }

    static func lookup(
        bundleID: String,
        countryCode: String
    ) throws -> Software {
        #if canImport(GoIPAToolBindings)
            return try invoke(
                operation: .lookup,
                request: LookupRequest(bundleID: bundleID, countryCode: countryCode),
                callWithInput: { APGoIPAToolLookup($0) }
            )
        #else
            _ = bundleID
            _ = countryCode
            throw ApplePackageBackendError.unavailable("go backend binary is not linked")
        #endif
    }

    static func fetchBag() throws -> Bag.BagOutput {
        #if canImport(GoIPAToolBindings)
            let result: BagResult = try invoke(
                operation: .fetchBag,
                request: BagRequest(
                    deviceIdentifier: Configuration.deviceIdentifier,
                    userAgent: Configuration.userAgent
                ),
                callWithInput: { APGoIPAToolFetchBag($0) }
            )
            guard let endpoint = URL(string: result.authEndpoint) else {
                throw NSError(
                    domain: "GoIPAToolBackend",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "invalid auth endpoint URL"]
                )
            }
            return Bag.BagOutput(authEndpoint: endpoint)
        #else
            throw ApplePackageBackendError.unavailable("go backend binary is not linked")
        #endif
    }

    static func authenticate(
        email: String,
        password: String,
        code: String,
        cookies: [Cookie],
        deviceIdentifier: String,
        userAgent: String
    ) throws -> Account {
        #if canImport(GoIPAToolBindings)
            return try invoke(
                operation: .authenticate,
                request: AuthenticateRequest(
                    email: email,
                    password: password,
                    code: code,
                    cookies: cookies,
                    deviceIdentifier: deviceIdentifier,
                    userAgent: userAgent
                ),
                callWithInput: { APGoIPAToolAuthenticate($0) }
            )
        #else
            _ = email
            _ = password
            _ = code
            _ = cookies
            _ = deviceIdentifier
            _ = userAgent
            throw ApplePackageBackendError.unavailable("go backend binary is not linked")
        #endif
    }

    static func purchase(
        account: Account,
        app: Software,
        deviceIdentifier: String,
        userAgent: String
    ) throws -> PurchaseResult {
        #if canImport(GoIPAToolBindings)
            return try invoke(
                operation: .purchase,
                request: PurchaseRequest(
                    account: account,
                    app: app,
                    deviceIdentifier: deviceIdentifier,
                    userAgent: userAgent
                ),
                callWithInput: { APGoIPAToolPurchase($0) }
            )
        #else
            _ = account
            _ = app
            _ = deviceIdentifier
            _ = userAgent
            throw ApplePackageBackendError.unavailable("go backend binary is not linked")
        #endif
    }

    static func listVersions(
        account: Account,
        bundleIdentifier: String,
        deviceIdentifier: String,
        userAgent: String
    ) throws -> VersionListResult {
        #if canImport(GoIPAToolBindings)
            return try invoke(
                operation: .listVersions,
                request: VersionListRequest(
                    account: account,
                    bundleIdentifier: bundleIdentifier,
                    deviceIdentifier: deviceIdentifier,
                    userAgent: userAgent
                ),
                callWithInput: { APGoIPAToolListVersions($0) }
            )
        #else
            _ = account
            _ = bundleIdentifier
            _ = deviceIdentifier
            _ = userAgent
            throw ApplePackageBackendError.unavailable("go backend binary is not linked")
        #endif
    }

    static func getVersionMetadata(
        account: Account,
        app: Software,
        versionID: String,
        deviceIdentifier: String,
        userAgent: String
    ) throws -> VersionMetadataResult {
        #if canImport(GoIPAToolBindings)
            return try invoke(
                operation: .getVersionMetadata,
                request: VersionMetadataRequest(
                    account: account,
                    app: app,
                    versionID: versionID,
                    deviceIdentifier: deviceIdentifier,
                    userAgent: userAgent
                ),
                callWithInput: { APGoIPAToolGetVersionMetadata($0) }
            )
        #else
            _ = account
            _ = app
            _ = versionID
            _ = deviceIdentifier
            _ = userAgent
            throw ApplePackageBackendError.unavailable("go backend binary is not linked")
        #endif
    }

    static func download(
        account: Account,
        app: Software,
        externalVersionID: String?,
        deviceIdentifier: String,
        userAgent: String
    ) throws -> DownloadResult {
        #if canImport(GoIPAToolBindings)
            return try invoke(
                operation: .download,
                request: DownloadRequest(
                    account: account,
                    app: app,
                    externalVersionID: externalVersionID ?? "",
                    deviceIdentifier: deviceIdentifier,
                    userAgent: userAgent
                ),
                callWithInput: { APGoIPAToolDownload($0) }
            )
        #else
            _ = account
            _ = app
            _ = externalVersionID
            _ = deviceIdentifier
            _ = userAgent
            throw ApplePackageBackendError.unavailable("go backend binary is not linked")
        #endif
    }

    private static func invoke<Request: Encodable, Result: Decodable>(
        operation: ApplePackageOperation,
        request: Request,
        callWithInput: (UnsafeMutablePointer<CChar>) -> UnsafeMutablePointer<CChar>?
    ) throws -> Result {
        #if canImport(GoIPAToolBindings)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let requestData = try encoder.encode(request)
            let requestString = String(decoding: requestData, as: UTF8.self)
            var requestCString = Array(requestString.utf8CString)

            let rawPointer = requestCString.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    return nil as UnsafeMutablePointer<CChar>?
                }
                return callWithInput(baseAddress)
            }

            guard let rawPointer else {
                throw ApplePackageBackendError.unavailable("go backend returned empty response")
            }
            defer { APGoIPAToolFreeString(rawPointer) }

            let responseString = String(cString: rawPointer)
            return try decodeEnvelope(operation: operation, responseString: responseString)
        #else
            _ = operation
            _ = request
            throw ApplePackageBackendError.unavailable("go backend binary is not linked")
        #endif
    }

    private static func decodeEnvelope<Result: Decodable>(
        operation: ApplePackageOperation,
        responseString: String
    ) throws -> Result {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(responseString.utf8)
        let envelope = try decoder.decode(Envelope<Result>.self, from: data)

        guard envelope.ok else {
            let message = envelope.error ?? "go backend operation failed"
            if message.contains("unsupported operation") {
                throw ApplePackageBackendError.unsupportedOperation(operation)
            }
            if message == "License required" {
                throw ApplePackageError.licenseRequired
            }
            throw NSError(
                domain: "GoIPAToolBackend",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        guard let result = envelope.result else {
            throw ApplePackageBackendError.unavailable("go backend returned no result")
        }

        return result
    }
}
