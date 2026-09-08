// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "limelight",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Limelight", path: "Sources/Limelight"),
    ]
)
