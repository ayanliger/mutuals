// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MutualsCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "MutualsCore", targets: ["MutualsCore"]),
    ],
    targets: [
        .target(name: "MutualsCore"),
        .testTarget(name: "MutualsCoreTests", dependencies: ["MutualsCore"]),
    ]
)
