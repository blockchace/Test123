// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChaceRecordings",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ChaceRecordings", targets: ["ChaceRecordings"])],
    targets: [
        .executableTarget(name: "ChaceRecordings"),
        .testTarget(name: "ChaceRecordingsTests", dependencies: ["ChaceRecordings"], path: "SwiftTests")
    ]
)
