// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceEnter",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "VoiceEnter", targets: ["VoiceEnterApp"]),
        .library(name: "VoiceEnterCore", targets: ["VoiceEnterCore"])
    ],
    targets: [
        // 核心库，包含所有业务逻辑
        .target(
            name: "VoiceEnterCore",
            dependencies: [],
            path: "Sources/VoiceEnterCore"
        ),
        // 可执行应用
        .executableTarget(
            name: "VoiceEnterApp",
            dependencies: ["VoiceEnterCore"],
            path: "Sources/VoiceEnterApp"
        ),
        // 测试
        .testTarget(
            name: "VoiceEnterTests",
            dependencies: ["VoiceEnterCore"],
            path: "Tests/VoiceEnterTests"
        )
    ]
)
