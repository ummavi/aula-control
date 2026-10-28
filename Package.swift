// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AulaControl",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AulaCore", targets: ["AulaCore"]),
        .executable(name: "AulaControl", targets: ["AulaControl"]),
    ],
    targets: [
        .target(name: "AulaCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "AulaControl", dependencies: ["AulaCore"]),
        .testTarget(name: "AulaCoreTests", dependencies: ["AulaCore"]),
        .testTarget(name: "AulaControlTests", dependencies: ["AulaControl"]),
    ]
)
