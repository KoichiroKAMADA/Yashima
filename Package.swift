// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Yashima",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
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
