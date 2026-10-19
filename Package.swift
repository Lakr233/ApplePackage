// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ApplePackage",
    platforms: [
        .iOS(.v18),
        .macCatalyst(.v18),
        .macOS(.v15),
        .tvOS(.v18),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "ApplePackage", targets: ["ApplePackage"]),
        .executable(name: "ApplePackageTool", targets: ["ApplePackageTool"]),
        .library(name: "AppleSAPKit", targets: ["AppleSAPKit"]),
        .executable(name: "AppleSAPTool", targets: ["AppleSAPTool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/openssl-spm.git", from: "4.0.1"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0")),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.9.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.2.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "CSAPRandom", path: "SAP/Sources/CSAPRandom", publicHeadersPath: "include"),
        .target(
            name: "AppleSAPKit",
            dependencies: ["CSAPRandom", .product(name: "OpenSSL", package: "openssl-spm")],
            path: "SAP/Sources/AppleSAPKit",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "AppleSAPTool",
            dependencies: ["AppleSAPKit", .product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "SAP/Sources/AppleSAPTool"
        ),
        .testTarget(name: "AppleSAPKitTests", dependencies: ["AppleSAPKit"], path: "SAP/Tests/AppleSAPKitTests"),
        .executableTarget(name: "ApplePackageTool", dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .target(name: "ApplePackage"),
            .target(name: "AppleSAPKit"),
        ]),
        .target(name: "ApplePackage", dependencies: [
            .target(name: "AppleSAPKit"),
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            .product(name: "AsyncHTTPClient", package: "async-http-client"),
            .product(name: "Collections", package: "swift-collections"),
            .product(name: "Logging", package: "swift-log"),
        ]),
        .testTarget(name: "ApplePackageTests", dependencies: ["ApplePackage"]),
    ],
    swiftLanguageModes: [.v6]
)
