import Foundation

public enum Authenticator {
    public nonisolated static func authenticate(
        email: String,
        password: String,
        code: String = "",
        cookies: [Cookie] = []
    ) async throws -> Account {
        try await ApplePackageBackendResolver.perform(operation: .authenticate) { backend in
            try await backend.authenticate(
                email: email,
                password: password,
                code: code,
                cookies: cookies
            )
        }
    }

    public nonisolated static func rotatePasswordToken(for account: inout Account) async throws {
        try await ApplePackageBackendResolver.perform(operation: .rotatePasswordToken) { backend in
            try await backend.rotatePasswordToken(for: &account)
        }
    }
}
