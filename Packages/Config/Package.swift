// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Config",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Config", targets: ["Config"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")],
    targets: [
        .target(name: "Config", dependencies: ["Yams"], resources: [.copy("DefaultConfig.yaml")])
    ],
    swiftLanguageModes: [.v6]
)
