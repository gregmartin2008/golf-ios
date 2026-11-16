// swift-tools-version: 5.9
import PackageDescription

// All of Caddie's logic: course import, lie detection, scoring, statistics, strokes gained,
// handicap, the GHIN client and storage. Foundation only, so the tests run on any machine.
let package = Package(
    name: "CaddieCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CaddieCore", targets: ["CaddieCore"]),
        .executable(name: "caddie-check", targets: ["caddie-check"]),
    ],
    targets: [
        .target(name: "CaddieCore", path: "Sources/CaddieCore"),
        .executableTarget(name: "caddie-check", dependencies: ["CaddieCore"], path: "Sources/caddie-check"),
        .testTarget(
            name: "CaddieCoreTests",
            dependencies: ["CaddieCore"],
            path: "Tests/CaddieCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
