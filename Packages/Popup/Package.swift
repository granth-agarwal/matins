// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Popup",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Popup", targets: ["Popup"])],
    dependencies: [.package(path: "../Models"), .package(path: "../Config"), .package(path: "../Store")],
    targets: [.target(name: "Popup", dependencies: ["Models", "Config", "Store"])],
    swiftLanguageModes: [.v6]
)
