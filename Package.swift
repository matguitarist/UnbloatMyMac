// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UnbloatMyMac",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "UnbloatMyMacKit"),
        .executableTarget(
            name: "UnbloatMyMac",
            dependencies: ["UnbloatMyMacKit", .product(name: "Sparkle", package: "Sparkle")],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // Sparkle.framework sits in Contents/Frameworks (build.sh copies it).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "UnbloatMyMacKitTests", dependencies: ["UnbloatMyMacKit"]),
    ]
)
