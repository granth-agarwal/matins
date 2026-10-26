// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Trigger",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Trigger", targets: ["Trigger"])],
    targets: [.target(name: "Trigger")],
    swiftLanguageModes: [.v6]
)
