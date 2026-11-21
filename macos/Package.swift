// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lingolite",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .executableTarget(
            name: "Lingolite",
            path: "Sources/Lingolite",
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
            name: "LingoliteOCR",
            path: "Sources/LingoliteOCR",
            linkerSettings: [
                .linkedFramework("Vision"),
                .linkedFramework("ImageIO"),
            ]
        ),
    ]
)

