// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ElectroMagnet",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ElectroMagnet", targets: ["ElectroMagnet"])],
    targets: [
        .target(name: "ElectroMagnetCore"),
        .executableTarget(name: "ElectroMagnet", dependencies: ["ElectroMagnetCore"]),
        .testTarget(name: "ElectroMagnetCoreTests", dependencies: ["ElectroMagnetCore"])
    ]
)
