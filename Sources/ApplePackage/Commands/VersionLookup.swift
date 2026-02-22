import Foundation

public enum VersionLookup {
    public nonisolated static func getVersionMetadata(
        account: inout Account,
        app: Software,
        versionID: String
    ) async throws -> VersionMetadata {
        try await ApplePackageBackendResolver.perform(operation: .getVersionMetadata) { backend in
            try await backend.getVersionMetadata(
                account: &account,
                app: app,
                versionID: versionID
            )
        }
    }
}
