// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Popup",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Popup", targets: ["Popup"])],
    targets: [.target(name: "Popup")],
    swiftLanguageModes: [.v6]
)
