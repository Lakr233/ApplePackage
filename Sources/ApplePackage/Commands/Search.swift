import Foundation

public enum Searcher {
    public nonisolated static func search(
        term: String,
        countryCode: String,
        limit: Int = 5,
        entityType: EntityType = .iPhone
    ) async throws -> [Software] {
        try await ApplePackageBackendResolver.perform(operation: .search) { backend in
            try await backend.search(
                term: term,
                countryCode: countryCode,
                limit: limit,
                entityType: entityType
            )
        }
    }
}
