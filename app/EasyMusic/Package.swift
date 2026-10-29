// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "EasyMusic", platforms: [.macOS(.v13)], products: [.executable(name: "EasyMusic", targets: ["EasyMusic"])], dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")], targets: [.executableTarget(name: "EasyMusic", dependencies: [.product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]), .testTarget(name: "EasyMusicTests", dependencies: ["EasyMusic"])])
