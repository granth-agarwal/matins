// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UI",
    platforms: [.macOS(.v14)],
    products: [.library(name: "UI", targets: ["UI"])],
    targets: [.target(name: "UI")],
    swiftLanguageModes: [.v6]
)
