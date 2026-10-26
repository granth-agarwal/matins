// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sync",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Sync", targets: ["Sync"])],
    dependencies: [.package(path: "../Store"), .package(path: "../Models")],
    targets: [.target(name: "Sync", dependencies: ["Store", "Models"])],
    swiftLanguageModes: [.v6]
)
