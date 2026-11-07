// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PGYMenu",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "PGYMenu", targets: ["PGYMenu"])
    ],
    targets: [
        .executableTarget(
            name: "PGYMenu",
            path: "Sources/PGYMenu"
        )
    ],
    swiftLanguageModes: [.v5]
)
