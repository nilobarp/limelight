// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "limelight",
    platforms: [.macOS(.v14)],
    targets: [
        // Everything lives here so it can be reached by tests; an executable
        // target's symbols cannot be imported.
        .target(name: "LimelightCore", path: "Sources/LimelightCore"),
        .executableTarget(name: "Limelight", dependencies: ["LimelightCore"],
                          path: "Sources/Limelight"),
        .testTarget(name: "LimelightCoreTests", dependencies: ["LimelightCore"],
                    path: "Tests/LimelightCoreTests"),
    ]
)
