// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ClaudeNavigator",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(
            name: "ClaudeNavigator",
            targets: ["ClaudeNavigator"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ClaudeNavigator",
            dependencies: [],
            path: "ClaudeNavigator",
            exclude: ["Info.plist"],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)