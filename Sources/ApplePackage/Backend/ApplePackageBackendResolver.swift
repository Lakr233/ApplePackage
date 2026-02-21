import Foundation

internal enum ApplePackageBackendResolver {
    nonisolated(unsafe) static var environmentProvider: () -> [String: String] = {
        ProcessInfo.processInfo.environment
    }

    nonisolated(unsafe) static var preferredBackendOverride: ApplePackageBackendKind?
    nonisolated(unsafe) static var goAvailabilityOverride: Bool?

    nonisolated(unsafe) static var goBackend: any ApplePackageBackend = GoIPAToolBackend()

    static func perform<T>(
        operation: ApplePackageOperation,
        _ body: (any ApplePackageBackend) async throws -> T
    ) async throws -> T {
        let backend = backend(for: operation)
        guard canServe(backend, operation: operation) else {
            throw ApplePackageBackendError.unavailable("go backend is unavailable for operation \(operation)")
        }
        return try await body(backend)
    }

    static func backend(for operation: ApplePackageOperation) -> any ApplePackageBackend {
        _ = operation
        return preferredBackend()
    }

    static func preferredBackend() -> any ApplePackageBackend {
        backend(for: preferredBackendKind())
    }

    static func preferredBackendKind() -> ApplePackageBackendKind {
        if let preferredBackendOverride {
            return preferredBackendOverride
        }

        let env = environmentProvider()
        if let backendRaw = env["APPLEPACKAGE_BACKEND"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            switch backendRaw {
            case "go", "ipatool":
                return .goIPATool
            case "native", "swift":
                return .goIPATool
            default:
                break
            }
        }
        return .goIPATool
    }

    static func resetTestingOverrides() {
        environmentProvider = { ProcessInfo.processInfo.environment }
        preferredBackendOverride = nil
        goAvailabilityOverride = nil
        goBackend = GoIPAToolBackend()
    }

    private static func backend(for kind: ApplePackageBackendKind) -> any ApplePackageBackend {
        switch kind {
        case .goIPATool:
            return goBackend
        }
    }

    private static func canServe(
        _ backend: any ApplePackageBackend,
        operation: ApplePackageOperation
    ) -> Bool {
        guard backend.supports(operation), isAvailable(backend) else {
            return false
        }
        return true
    }

    private static func isAvailable(_ backend: any ApplePackageBackend) -> Bool {
        if backend.kind == .goIPATool, let goAvailabilityOverride {
            return goAvailabilityOverride
        }
        return backend.isAvailable
    }
}
