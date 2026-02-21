import Foundation

public enum Bag {
    public struct BagOutput {
        public var authEndpoint: URL
    }

    public nonisolated static func fetchBag() async throws -> BagOutput {
        try await ApplePackageBackendResolver.perform(operation: .fetchBag) { backend in
            try await backend.fetchBag()
        }
    }
}
