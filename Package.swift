// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RhythmCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "RhythmCore", targets: ["RhythmCore"])],
    targets: [
        .target(name: "RhythmCore", path: "Shared", exclude: ["ReportContext.swift"]),
        .testTarget(name: "RhythmCoreTests", dependencies: ["RhythmCore"], path: "Tests")
    ]
)
