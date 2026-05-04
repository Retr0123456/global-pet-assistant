// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GlobalPetAssistant",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "GlobalPetAssistant",
            targets: ["GlobalPetAssistant"]
        )
    ],
    targets: [
        .executableTarget(
            name: "GlobalPetAssistant",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
