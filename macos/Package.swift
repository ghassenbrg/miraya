// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Miraya",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Miraya", targets: ["Miraya"]), .library(name: "MirayaCore", targets: ["MirayaCore"])],
    targets: [
        .target(name: "MirayaCore"),
        .executableTarget(name: "Miraya", dependencies: ["MirayaCore"]),
        .testTarget(name: "MirayaCoreTests", dependencies: ["MirayaCore"])
    ]
)
