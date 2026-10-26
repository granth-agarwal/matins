// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MorningBrief",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MorningBrief", targets: ["MorningBrief"])],
    dependencies: [
        .package(path: "Packages/Auth"),
        .package(path: "Packages/Config"),
        .package(path: "Packages/Store")
    ],
    targets: [
        .executableTarget(
            name: "MorningBrief",
            dependencies: ["Config", "Store", "Auth"],
            path: "App",
            exclude: ["Info.plist"]
        ),
        .testTarget(name: "SkeletonTests", dependencies: ["Config", "Store", "Auth"])
    ],
    swiftLanguageModes: [.v6]
)
