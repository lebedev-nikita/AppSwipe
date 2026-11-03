// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwitchCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SwitchCore", targets: ["SwitchCore"]),
    ],
    targets: [
        .target(name: "SwitchCore"),
        .testTarget(name: "SwitchCoreTests", dependencies: ["SwitchCore"], resources: [.copy("Fixtures")]),
    ]
)
