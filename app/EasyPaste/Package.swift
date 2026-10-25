// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "EasyPaste", platforms: [.macOS(.v15)], products: [
    .executable(name: "EasyPaste", targets: ["EasyPaste"])
], targets: [
    .target(name: "CArgon2", exclude: ["LICENSE", "PROVENANCE.json"], sources: ["src"], publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src"), .define("ARGON2_NO_THREADS")]),
    .executableTarget(name: "EasyPaste", dependencies: ["CArgon2"], exclude: ["Resources"], swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "EasyPasteTests", dependencies: ["EasyPaste"], swiftSettings: [.swiftLanguageMode(.v5)])
])
