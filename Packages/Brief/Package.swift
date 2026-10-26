// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Brief",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Brief", targets: ["Brief"])],
    targets: [.target(name: "Brief")],
    swiftLanguageModes: [.v6]
)
