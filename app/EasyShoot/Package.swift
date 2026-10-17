// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "EasyShoot", platforms: [.macOS(.v15)], products: [.executable(name: "EasyShoot", targets: ["EasyShoot"])], targets: [.executableTarget(name: "EasyShoot", swiftSettings: [.swiftLanguageMode(.v5)])])
