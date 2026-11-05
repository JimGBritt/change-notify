// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChangeNotifyCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ChangeNotifyCore", targets: ["ChangeNotifyCore"]),
    ],
    targets: [
        .target(name: "ChangeNotifyCore"),
        .testTarget(name: "ChangeNotifyCoreTests", dependencies: ["ChangeNotifyCore"]),
    ],
    swiftLanguageModes: [.v6]
)
