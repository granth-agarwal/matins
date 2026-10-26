// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sync",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Sync", targets: ["Sync"])],
    targets: [.target(name: "Sync")],
    swiftLanguageModes: [.v6]
)
