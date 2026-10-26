// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Trigger",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Trigger", targets: ["Trigger"])],
    dependencies: [.package(path: "../Config"), .package(path: "../Store"), .package(path: "../Models")],
    targets: [.target(name: "Trigger", dependencies: ["Config", "Store", "Models"])],
    swiftLanguageModes: [.v6]
)
