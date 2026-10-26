// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MorningBrief",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MorningBrief", targets: ["MorningBrief"])],
    dependencies: [
        .package(path: "Packages/Auth"),
        .package(path: "Packages/Brief"),
        .package(path: "Packages/UI"),
        .package(path: "Packages/Trigger"),
        .package(path: "Packages/Popup"),
        .package(path: "Packages/Models"),
        .package(path: "Packages/Sync"),
        .package(path: "Packages/Config"),
        .package(path: "Packages/Store")
    ],
    targets: [
        .executableTarget(
            name: "MorningBrief",
            dependencies: ["Config", "Store", "Auth", "Models", "Sync", "Brief", "UI", "Trigger", "Popup"],
            path: "App",
            exclude: ["Info.plist"]
        ),
        .testTarget(name: "SkeletonTests", dependencies: ["Config", "Store", "Auth", "Models", "Sync", "Brief", "UI", "Trigger", "Popup"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v6]
)
