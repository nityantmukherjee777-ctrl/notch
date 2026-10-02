// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [.macOS("13.0")],
    products: [.executable(name: "Notch", targets: ["Notch"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "NotchCore"),
        .executableTarget(name: "Notch", dependencies: ["NotchCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore", "Notch"])
    ],
    swiftLanguageModes: [.v5]
)
