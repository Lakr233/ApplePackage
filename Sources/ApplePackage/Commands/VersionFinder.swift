import Foundation

public enum VersionFinder {
    public nonisolated static func list(
        account: inout Account,
        bundleIdentifier: String
    ) async throws -> [String] {
        try await ApplePackageBackendResolver.perform(operation: .listVersions) { backend in
            try await backend.listVersions(account: &account, bundleIdentifier: bundleIdentifier)
        }
    }
}
