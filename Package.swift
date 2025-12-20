// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacViber",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacViber", targets: ["MacViber"])
    ],
    dependencies: [
        .package(path: "LocalPackages/SwiftTerm"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0")
    ],
    targets: [
        .executableTarget(
            name: "MacViber",
            dependencies: [
                "SwiftTerm",
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "MacViber"
        )
    ]
)
