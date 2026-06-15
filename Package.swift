// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Yashima",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "Yashima",
            targets: ["Yashima"]
        ),
    ],
    targets: [
        .target(
            name: "Yashima"
        ),
        .testTarget(
            name: "YashimaTests",
            dependencies: ["Yashima"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
