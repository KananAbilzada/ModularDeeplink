// swift-tools-version: 5.9
// Created by Kanan Abilzada.

import PackageDescription

let package = Package(
    name: "DeeplinkKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "DeeplinkKit",
            targets: ["DeeplinkKit"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DeeplinkKit",
            dependencies: [],
            path: "Sources/DeeplinkKit",
            exclude: [
                "Extensions/AppDelegate+Example.swift.txt",
                "Extensions/ExampleModule.swift.txt"
            ]
        ),
        .testTarget(
            name: "DeeplinkKitTests",
            dependencies: ["DeeplinkKit"],
            path: "Tests/DeeplinkKitTests"
        )
    ]
)
