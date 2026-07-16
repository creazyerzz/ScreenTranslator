// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenTranslator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ScreenTranslator", targets: ["ScreenTranslator"])
    ],
    targets: [
        .executableTarget(
            name: "ScreenTranslator",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Vision")
            ]
        )
    ]
)
