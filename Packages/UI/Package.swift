// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UI",
    platforms: [.macOS(.v14)],
    products: [.library(name: "UI", targets: ["UI"])],
    dependencies: [.package(path: "../Brief"), .package(path: "../Models"), .package(path: "../Config"), .package(path: "../Store")],
    targets: [.target(name: "UI", dependencies: ["Brief", "Models", "Config", "Store"], resources: [.copy("Resources")])],
    swiftLanguageModes: [.v6]
)
