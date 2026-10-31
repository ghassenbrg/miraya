// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Miraya",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Miraya", targets: ["Miraya"]), .library(name: "MirayaCore", targets: ["MirayaCore"])],
    dependencies: [.package(url: "https://github.com/stasel/WebRTC.git", exact: "150.0.0")],
    targets: [
        .target(name: "MirayaCore"),
        .target(name: "MirayaRTCBridge", dependencies: [.product(name: "WebRTC", package: "WebRTC")],
            cSettings: [.unsafeFlags(["-fobjc-arc"])], linkerSettings: [.linkedFramework("AudioToolbox")]),
        .executableTarget(name: "Miraya", dependencies: ["MirayaCore", "MirayaRTCBridge", .product(name: "WebRTC", package: "WebRTC")],
            resources: [.process("Resources")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "MirayaCoreTests", dependencies: ["MirayaCore"])
    ]
)
