import Foundation

public enum Download {
    public nonisolated static func download(
        account: inout Account,
        app: Software,
        externalVersionID: String? = nil
    ) async throws -> DownloadOutput {
        try await ApplePackageBackendResolver.perform(operation: .download) { backend in
            try await backend.download(
                account: &account,
                app: app,
                externalVersionID: externalVersionID
            )
        }
    }
}
