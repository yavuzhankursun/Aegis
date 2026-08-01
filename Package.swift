// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Aegis",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Aegis",
            path: "Sources/Aegis",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
            ]
        )
    ]
)
