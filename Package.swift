// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PostHogSupportChat",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        // Full package: SwiftUI chat UI + transport.
        .library(name: "PostHogSupportChat", targets: ["PostHogSupportChat"]),
        // Transport only, for apps that build their own UI.
        .library(name: "PostHogSupportChatClient", targets: ["PostHogSupportChatClient"]),
    ],
    targets: [
        .target(name: "PostHogSupportChatClient"),
        .target(
            name: "PostHogSupportChat",
            dependencies: ["PostHogSupportChatClient"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "PostHogSupportChatClientTests", dependencies: ["PostHogSupportChatClient"]),
    ]
)
