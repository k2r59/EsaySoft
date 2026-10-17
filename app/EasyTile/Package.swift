// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "EasyTile", platforms: [.macOS(.v15)], products: [.executable(name: "EasyTile", targets: ["EasyTile"])], targets: [.executableTarget(name: "EasyTile", swiftSettings: [.swiftLanguageMode(.v5)]), .testTarget(name: "EasyTileTests", dependencies: ["EasyTile"], swiftSettings: [.swiftLanguageMode(.v5)])])
