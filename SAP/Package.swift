// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AppleSAP",
    platforms: [.macOS(.v15), .iOS(.v18), .macCatalyst(.v18), .tvOS(.v18), .visionOS(.v2)],
    products: [
        .library(name: "AppleSAPKit", targets: ["AppleSAPKit"]),
        .executable(name: "AppleSAPTool", targets: ["AppleSAPTool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/openssl-spm.git", from: "4.0.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "CSAPRandom", publicHeadersPath: "include"),
        .target(name: "AppleSAPKit", dependencies: [
            "CSAPRandom", .product(name: "OpenSSL", package: "openssl-spm"),
        ], resources: [.process("Resources")]),
        .executableTarget(name: "AppleSAPTool", dependencies: [
            "AppleSAPKit", .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(name: "AppleSAPKitTests", dependencies: ["AppleSAPKit"]),
    ],
    swiftLanguageModes: [.v6]
)
