// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SindriPDF",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SindriPDF", targets: ["SindriPDF"])
    ],
    targets: [
        .executableTarget(
            name: "SindriPDF",
            dependencies: [],
            path: "Sources"
        )
    ]
)
