import Foundation

public enum Purchase {
    public nonisolated static func purchase(
        account: inout Account,
        app: Software
    ) async throws {
        try await ApplePackageBackendResolver.perform(operation: .purchase) { backend in
            try await backend.purchase(account: &account, app: app)
        }
    }
}
