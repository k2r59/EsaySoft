// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "EasyShoot", platforms: [.macOS(.v15)], products: [
    .executable(name: "EasyShoot", targets: ["EasyShoot"])
], dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
], targets: [
    .executableTarget(name: "EasyShoot", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
        exclude: ["Resources"], swiftSettings: [.swiftLanguageMode(.v5)],
        linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .testTarget(name: "EasyShootTests", dependencies: ["EasyShoot"], swiftSettings: [.swiftLanguageMode(.v5)])
])
