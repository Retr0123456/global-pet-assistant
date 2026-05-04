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
        ),
        .testTarget(
            name: "GlobalPetAssistantTests",
            dependencies: ["GlobalPetAssistant"],
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
