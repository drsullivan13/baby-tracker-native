// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BabyTrackerNative",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BabyTrackerDomain", targets: ["BabyTrackerDomain"]),
        .library(name: "BabyTrackerPersistence", targets: ["BabyTrackerPersistence"])
    ],
    targets: [
        .target(name: "BabyTrackerDomain", path: "Sources/BabyTrackerDomain"),
        .target(
            name: "BabyTrackerPersistence",
            dependencies: ["BabyTrackerDomain"],
            path: "Sources/BabyTrackerPersistence"
        ),
        .testTarget(
            name: "BabyTrackerDomainTests",
            dependencies: ["BabyTrackerDomain", "BabyTrackerPersistence"],
            path: "Tests/BabyTrackerDomainTests"
        )
    ]
)
