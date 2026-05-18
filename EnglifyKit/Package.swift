// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EnglifyKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "EnglifyKit",
            targets: ["EnglifyKit"]
        )
    ],
    targets: [
        .target(
            name: "EnglifyKit",
            path: "Sources/EnglifyKit"
        ),
        .testTarget(
            name: "EnglifyKitTests",
            dependencies: ["EnglifyKit"],
            path: "Tests/EnglifyKitTests"
        )
    ]
)
