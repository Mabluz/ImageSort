// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImageSort",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ImageSort",
            path: "Sources/ImageSort",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ImageSortTests",
            dependencies: ["ImageSort"],
            path: "Tests/ImageSortTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
