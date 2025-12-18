// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MultiTerm",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MultiTerm", targets: ["MultiTerm"])
    ],
    dependencies: [
        .package(path: "LocalPackages/SwiftTerm")
    ],
    targets: [
        .executableTarget(
            name: "MultiTerm",
            dependencies: ["SwiftTerm"],
            path: "MultiTerm"
        )
    ]
)
