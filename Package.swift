// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

private struct GoBindingsMetadata: Decodable {
    let releaseTag: String
    let assetName: String
    let checksum: String
    let repository: String?
}

private let localGoBindingsPath = "Binaries/GoIPAToolBindings.xcframework"
private let goBindingsMetadataPath = "GoIPAToolWrapper/bindings-metadata.json"
private let executionPackageRootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let manifestPackageRootURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

private func candidatePackageRoots() -> [URL] {
    let roots = [executionPackageRootURL, manifestPackageRootURL]
    var seen = Set<String>()
    return roots.filter { root in
        if seen.contains(root.path) {
            return false
        }
        seen.insert(root.path)
        return true
    }
}

private func loadGoBindingsMetadata() -> GoBindingsMetadata {
    guard
        let metadataURL = candidatePackageRoots()
            .map({ $0.appendingPathComponent(goBindingsMetadataPath) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
    else {
        fatalError("Missing \(goBindingsMetadataPath). Run Scripts/update_ipatool.sh.")
    }

    guard let data = try? Data(contentsOf: metadataURL) else {
        fatalError("Missing \(goBindingsMetadataPath). Run Scripts/update_ipatool.sh.")
    }

    do {
        return try JSONDecoder().decode(GoBindingsMetadata.self, from: data)
    } catch {
        fatalError("Invalid \(goBindingsMetadataPath): \(error)")
    }
}

private func makeGoBindingsTarget() -> Target {
    if shouldUseLocalBindings() {
        return .binaryTarget(
            name: "GoIPAToolBindings",
            path: localGoBindingsPath
        )
    }

    let metadata = loadGoBindingsMetadata()
    let repository = resolveRepositorySlug(fallback: metadata.repository)
    return .binaryTarget(
        name: "GoIPAToolBindings",
        url: "https://github.com/\(repository)/releases/download/\(metadata.releaseTag)/\(metadata.assetName)",
        checksum: metadata.checksum
    )
}

private func shouldUseLocalBindings() -> Bool {
    guard let rawValue = ProcessInfo.processInfo.environment["APPLEPACKAGE_USE_LOCAL_BINDINGS"] else {
        return false
    }
    switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes":
        return true
    default:
        return false
    }
}

private func resolveRepositorySlug(fallback: String?) -> String {
    let environment = ProcessInfo.processInfo.environment
    if let value = environment["APPLEPACKAGE_GITHUB_REPOSITORY"], isValidRepositorySlug(value) {
        return value
    }

    if let slug = loadRepositorySlugFromGitRemotes(["upstream"]) {
        return slug
    }

    if let slug = loadRepositorySlugFromGitRemotes(["origin"]) {
        return slug
    }

    if let fallback, isValidRepositorySlug(fallback) {
        return fallback
    }

    fatalError(
        """
        Unable to resolve GitHub repository slug for GoIPAToolBindings release URL.
        Set APPLEPACKAGE_GITHUB_REPOSITORY=<owner>/<repo> or update \(goBindingsMetadataPath) with a valid repository.
        """
    )
}

private func loadRepositorySlugFromGitRemotes(_ remoteNames: [String]) -> String? {
    for packageRoot in candidatePackageRoots() {
        guard
            let configURL = resolveGitConfigURL(packageRoot: packageRoot),
            let config = try? String(contentsOf: configURL, encoding: .utf8)
        else {
            continue
        }

        for remoteName in remoteNames {
            if let remoteURL = extractRemoteURL(fromGitConfig: config, remoteName: remoteName),
               let slug = extractRepositorySlug(fromRemoteURL: remoteURL) {
                return slug
            }
        }
    }
    return nil
}

private func resolveGitConfigURL(packageRoot: URL) -> URL? {
    let gitPath = packageRoot.appendingPathComponent(".git")
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: gitPath.path, isDirectory: &isDirectory) else {
        return nil
    }

    if isDirectory.boolValue {
        return gitPath.appendingPathComponent("config")
    }

    guard let gitFile = try? String(contentsOf: gitPath, encoding: .utf8) else {
        return nil
    }
    guard let prefixRange = gitFile.range(of: "gitdir:") else {
        return nil
    }

    let rawPath = gitFile[prefixRange.upperBound...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawPath.isEmpty else {
        return nil
    }

    let gitDirectoryURL: URL
    if rawPath.hasPrefix("/") {
        gitDirectoryURL = URL(fileURLWithPath: rawPath)
    } else {
        gitDirectoryURL = packageRoot.appendingPathComponent(rawPath)
    }
    return gitDirectoryURL.appendingPathComponent("config")
}

private func extractRemoteURL(fromGitConfig config: String, remoteName: String) -> String? {
    var inOriginSection = false
    for line in config.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            inOriginSection = trimmed == "[remote \"\(remoteName)\"]"
            continue
        }

        guard inOriginSection else {
            continue
        }

        guard trimmed.hasPrefix("url") else {
            continue
        }

        let parts = trimmed.split(separator: "=", maxSplits: 1).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        if parts.count == 2, !parts[1].isEmpty {
            return parts[1]
        }
    }
    return nil
}

private func extractRepositorySlug(fromRemoteURL remoteURL: String) -> String? {
    let normalized = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefixes = [
        "https://github.com/",
        "http://github.com/",
        "git@github.com:",
        "ssh://git@github.com/",
        "git://github.com/",
    ]

    guard let prefix = prefixes.first(where: { normalized.hasPrefix($0) }) else {
        return nil
    }

    var path = String(normalized.dropFirst(prefix.count))
    if path.hasSuffix(".git") {
        path.removeLast(4)
    }

    let parts = path.split(separator: "/", omittingEmptySubsequences: true)
    guard parts.count >= 2 else {
        return nil
    }

    let slug = "\(parts[0])/\(parts[1])"
    return isValidRepositorySlug(slug) ? slug : nil
}

private func isValidRepositorySlug(_ value: String) -> Bool {
    let parts = value.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2 else {
        return false
    }

    return parts.allSatisfy { part in
        !part.isEmpty && part.allSatisfy { char in
            char.isLetter || char.isNumber || char == "-" || char == "_" || char == "."
        }
    }
}

private let goBindingsTarget = makeGoBindingsTarget()

let package = Package(
    name: "ApplePackage",
    platforms: [
        .iOS(.v15),
        .tvOS(.v17),
        .visionOS(.v1),
        .macCatalyst(.v14),
        .macOS(.v12),
    ],
    products: [
        .library(name: "ApplePackage", targets: ["ApplePackage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0")),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.9.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.2.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        goBindingsTarget,
        .executableTarget(name: "ApplePackageTool", dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .target(name: "ApplePackage"),
        ]),
        .target(name: "ApplePackage", dependencies: [
            .target(name: "GoIPAToolBindings"),
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            .product(name: "AsyncHTTPClient", package: "async-http-client"),
            .product(name: "Collections", package: "swift-collections"),
            .product(name: "Logging", package: "swift-log"),
        ]),
        .testTarget(name: "ApplePackageTests", dependencies: ["ApplePackage"]),
    ]
)
