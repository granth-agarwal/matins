// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Store",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Store", targets: ["Store"])],
    dependencies: [.package(path: "../Models"), .package(path: "../Brief"), .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")],
    targets: [.target(name: "Store", dependencies: ["Models", "Brief", .product(name: "GRDB", package: "GRDB.swift")])],
    swiftLanguageModes: [.v6]
)
