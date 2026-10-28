// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RoomsServer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.10.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.0"),
        .package(url: "https://github.com/vapor/apns.git", from: "4.2.0"),
        .package(url: "https://github.com/swift-server-community/APNSwift.git", from: "5.1.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .executableTarget(
            name: "RoomsServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "VaporAPNS", package: "apns"),
                .product(name: "APNS", package: "APNSwift"),
                .product(name: "APNSCore", package: "APNSwift"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "RoomsServerTests",
            dependencies: [
                .target(name: "RoomsServer"),
                .product(name: "XCTVapor", package: "vapor"),
            ]
        ),
    ]
)
