// swift-tools-version: 6.0
import PackageDescription
let package = Package(name:"EasyPaste",platforms:[.macOS(.v15)],products:[.executable(name:"EasyPaste",targets:["EasyPaste"])],targets:[.executableTarget(name:"EasyPaste",exclude:["Resources"],swiftSettings:[.swiftLanguageMode(.v5)]),.testTarget(name:"EasyPasteTests",dependencies:["EasyPaste"],swiftSettings:[.swiftLanguageMode(.v5)])])
