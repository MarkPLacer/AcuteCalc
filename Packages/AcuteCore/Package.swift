// swift-tools-version: 6.2
import PackageDescription

// AcuteCore is the platform-independent math engine of Acute Calc:
// parsing, structured math editing, exact & numeric evaluation, a small CAS,
// solvers, function analysis, statistics, geometry and physics data.
// It has no UI dependencies so it can be unit-tested with `swift test`.
let package = Package(
    name: "AcuteCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "AcuteCore", targets: ["AcuteCore"]),
    ],
    targets: [
        .target(name: "AcuteCore"),
        .testTarget(name: "AcuteCoreTests", dependencies: ["AcuteCore"]),
    ],
    swiftLanguageModes: [.v6]
)
