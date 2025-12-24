// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TidalDrift",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TidalDrift", targets: ["TidalDrift"])
    ],
    targets: [
        .executableTarget(
            name: "TidalDrift",
            path: ".",
            exclude: ["TidalDrift.entitlements", "Info.plist", "Package.swift", "build-app.sh", "TidalDrift.app"],
            sources: [
                "App",
                "Views",
                "ViewModels", 
                "Services",
                "Models",
                "Utilities"
            ],
            resources: [
                .copy("Resources/AppIcon.icns"),
                .process("Resources/Assets.xcassets")
            ]
        )
    ]
)
