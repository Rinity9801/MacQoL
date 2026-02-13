// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacQoL",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MacQoL",
            targets: ["MacQoL"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacQoL",
            path: "MacQoL",
            exclude: ["Info.plist"],
            resources: [
                .process("Info.plist")
            ],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
