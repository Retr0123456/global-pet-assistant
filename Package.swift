// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GlobalPetAssistant",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "GlobalPetAssistant",
            targets: ["GlobalPetAssistant"]
        ),
        .executable(
            name: "petctl",
            targets: ["petctl"]
        ),
        .executable(
            name: "pet-webhook-bridge",
            targets: ["petWebhookBridge"]
        ),
        .executable(
            name: "global-pet-agent-bridge",
            targets: ["globalPetAgentBridge"]
        )
    ],
    targets: [
        .target(
            name: "GlobalPetAgentBridgeCore"
        ),
        .target(
            name: "PetWebhookBridgeCore"
        ),
        .executableTarget(
            name: "GlobalPetAssistant",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "petctl"
        ),
        .executableTarget(
            name: "petWebhookBridge",
            dependencies: ["PetWebhookBridgeCore"]
        ),
        .executableTarget(
            name: "globalPetAgentBridge",
            dependencies: ["GlobalPetAgentBridgeCore"]
        ),
        .testTarget(
            name: "GlobalPetAssistantTests",
            dependencies: [
                "GlobalPetAssistant",
                "GlobalPetAgentBridgeCore",
                "PetWebhookBridgeCore"
            ],
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-F",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
