// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacIPadDisplay",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "mac-ipad-display", targets: ["MacIPadDisplay"])
    ],
    targets: [
        .executableTarget(
            name: "MacIPadDisplay",
            path: "Sources/MacIPadDisplay",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
