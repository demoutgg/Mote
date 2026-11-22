// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mote",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .executableTarget(
            name: "Mote",
            path: "Sources/Mote",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Security"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .executableTarget(
            name: "MoteOCR",
            path: "Sources/MoteOCR",
            linkerSettings: [
                .linkedFramework("Vision"),
                .linkedFramework("ImageIO"),
            ]
        ),
    ]
)

