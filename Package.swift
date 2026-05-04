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
        ),
        .executable(
            name: "petctl",
            targets: ["petctl"]
        )
    ],
    targets: [
        .executableTarget(
            name: "GlobalPetAssistant",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "petctl"
        )
    ]
)
