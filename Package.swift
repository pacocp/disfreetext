// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "disfreetext",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "disfreetext", path: "Sources")]
)
