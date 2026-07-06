// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "YashimaBenchmarks",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "YashimaBenchmarks",
            dependencies: [
                .product(name: "Yashima", package: "Yashima"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
