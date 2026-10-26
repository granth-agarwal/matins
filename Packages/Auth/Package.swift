// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Auth",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Auth", targets: ["Auth"])],
    dependencies: [.package(url: "https://github.com/openid/AppAuth-iOS.git", exact: "1.7.6")],
    targets: [.target(name: "Auth", dependencies: [.product(name: "AppAuth", package: "AppAuth-iOS")])],
    swiftLanguageModes: [.v6]
)
