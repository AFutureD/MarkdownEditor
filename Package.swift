// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MarkdownEditor",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MarkdownEditor",
            targets: ["MarkdownEditor"]
        ),
        .executable(
            name: "Benchmark",
            targets: ["Benchmark"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.3"),
        .package(url: "https://github.com/simonbs/Runestone.git", from: "0.4.1"),
        .package(url: "https://github.com/simonbs/TreeSitterLanguages.git", from: "0.0.3"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MarkdownEditor",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Runestone", package: "Runestone", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterJavaScriptRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterJSONRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterPythonRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
                .product(name: "TreeSitterSwiftRunestone", package: "TreeSitterLanguages", condition: .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(
            name: "MarkdownEditorTests",
            dependencies: ["MarkdownEditor"]
        ),
        .executableTarget(
            name: "Benchmark",
            dependencies: ["MarkdownEditor"],
            path: "Benchmark"
        ),
    ],
    swiftLanguageModes: [.v6]
)
