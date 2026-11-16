// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DynamicIsland",
    platforms: [.macOS("14.2")], // 14.2: Core Audio process taps
    targets: [
        .executableTarget(
            name: "DynamicIsland",
            path: "Sources/DynamicIsland",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("EventKit"),
                .linkedFramework("Intents"),
            ]
        )
    ]
)
