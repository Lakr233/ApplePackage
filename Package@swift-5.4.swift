// swift-tools-version: 5.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ApplePackage",
    platforms: [
        .iOS("15.0"),
        .macOS(.v11),
    ],
    products: [
        .library(name: "ApplePackage", targets: ["ApplePackage"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ApplePackage",
            dependencies: [],
            exclude: [
                "Commands",
                "Configuration",
                "Models/Account.swift",
                "Supplement/Accounts.swift",
                "Supplement/Cookie.swift",
                "Supplement/Ext+Optional.swift",
                "Supplement/Logger.swift",
                "Supplement/SignatureInjector.swift",
                "Supplement/Then.swift",
            ]
        ),
    ]
)
