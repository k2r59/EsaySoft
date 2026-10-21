// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "EasyTile", platforms: [.macOS(.v15)],
    products: [.executable(name: "EasyTile", targets: ["EasyTile"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .executableTarget(name: "EasyTile", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "EasyTileTests", dependencies: ["EasyTile"], swiftSettings: [.swiftLanguageMode(.v5)])
    ])
