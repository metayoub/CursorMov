// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CursorMov",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "CursorMovCore"),
        .executableTarget(name: "CursorMov", dependencies: ["CursorMovCore"]),
        .testTarget(name: "CursorMovCoreTests", dependencies: ["CursorMovCore"]),
    ]
)
