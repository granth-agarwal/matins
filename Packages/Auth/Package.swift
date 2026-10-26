// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Auth",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Auth", targets: ["Auth"])],
    targets: [.target(name: "Auth")],
    swiftLanguageModes: [.v6]
)
