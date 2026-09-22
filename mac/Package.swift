// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DeskReminder",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: frame decoding, sit/stand tracking, reminder rules. No AppKit,
        // no serial port, no files - so it can all be tested.
        .target(name: "DeskCore"),
        .executableTarget(name: "Intermission", dependencies: ["DeskCore"]),
        .testTarget(name: "DeskCoreTests", dependencies: ["DeskCore"]),
    ]
)
