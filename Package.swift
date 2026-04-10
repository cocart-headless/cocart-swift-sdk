// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CoCart",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "CoCart", targets: ["CoCart"]),
    ],
    targets: [
        .target(
            name: "CoCart",
            path: "Sources/CoCart"
        ),
        .testTarget(
            name: "CoCartTests",
            dependencies: ["CoCart"],
            path: "Tests/CoCartTests"
        ),
    ]
)
