// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AireAudio",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AireAudio", targets: ["AireAudio"])],
    targets: [
        .executableTarget(name: "AireAudio"),
        .testTarget(name: "AireAudioTests", dependencies: ["AireAudio"], path: "SwiftTests")
    ]
)
