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
        .package(path: "LocalPackages/SwiftTerm"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0")
    ],
    targets: [
        .executableTarget(
            name: "MultiTerm",
            dependencies: [
                "SwiftTerm",
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "MultiTerm"
        )
    ]
)
