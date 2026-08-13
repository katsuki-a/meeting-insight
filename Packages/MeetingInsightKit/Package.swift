// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MeetingInsightKit",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "MeetingInsightDomain", targets: ["MeetingInsightDomain"]),
        .library(name: "MeetingInsightRepository", targets: ["MeetingInsightRepository"]),
        .library(name: "MeetingInsightResearch", targets: ["MeetingInsightResearch"]),
        .library(name: "MeetingInsightCapture", targets: ["MeetingInsightCapture"]),
        .library(name: "MeetingInsightTranscription", targets: ["MeetingInsightTranscription"]),
        .library(name: "MeetingInsightOrchestration", targets: ["MeetingInsightOrchestration"]),
        .library(name: "MeetingInsightStorage", targets: ["MeetingInsightStorage"]),
        .executable(name: "meeting-insight", targets: ["MeetingInsightCLI"])
    ],
    targets: [
        .target(
            name: "MeetingInsightDomain",
            resources: [.process("Resources")]
        ),
        .target(
            name: "MeetingInsightRepository",
            dependencies: ["MeetingInsightDomain"]
        ),
        .target(
            name: "MeetingInsightResearch",
            dependencies: ["MeetingInsightDomain", "MeetingInsightRepository"]
        ),
        .target(
            name: "MeetingInsightCapture",
            dependencies: ["MeetingInsightDomain"]
        ),
        .target(
            name: "MeetingInsightTranscription",
            dependencies: ["MeetingInsightDomain"]
        ),
        .target(
            name: "MeetingInsightOrchestration",
            dependencies: [
                "MeetingInsightDomain",
                "MeetingInsightRepository",
                "MeetingInsightResearch",
                "MeetingInsightTranscription"
            ]
        ),
        .target(
            name: "MeetingInsightStorage",
            dependencies: ["MeetingInsightDomain"]
        ),
        .executableTarget(
            name: "MeetingInsightCLI",
            dependencies: ["MeetingInsightOrchestration"]
        ),
        .testTarget(
            name: "DomainTests",
            dependencies: ["MeetingInsightDomain"],
            resources: [.process("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v6]
)
