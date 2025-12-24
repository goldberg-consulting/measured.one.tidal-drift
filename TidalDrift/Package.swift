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
            exclude: ["Resources", "TidalDrift.entitlements", "Info.plist", "Package.swift"],
            sources: [
                "App",
                "Views",
                "ViewModels", 
                "Services",
                "Models",
                "Utilities"
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
