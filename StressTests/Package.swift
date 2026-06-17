// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "YashimaStressTests",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "YashimaStressRunner",
            targets: ["YashimaStressRunner"]
        ),
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .target(
            name: "YashimaStressSupport",
            dependencies: [
                .product(name: "Yashima", package: "Yashima"),
            ]
        ),
        .executableTarget(
            name: "YashimaStressRunner",
            dependencies: ["YashimaStressSupport"]
        ),
        .testTarget(
            name: "YashimaStressSupportTests",
            dependencies: ["YashimaStressSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
