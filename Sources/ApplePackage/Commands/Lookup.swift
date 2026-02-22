import Foundation

public enum Lookup {
    public nonisolated static func lookup(
        bundleID: String,
        countryCode: String
    ) async throws -> Software {
        try await ApplePackageBackendResolver.perform(operation: .lookup) { backend in
            try await backend.lookup(bundleID: bundleID, countryCode: countryCode)
        }
    }
}
