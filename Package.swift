// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MoshDeckCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "MoshDeckCore", targets: ["MoshDeckCore"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-ssh.git", exact: "0.15.0"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.102.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
    ],
    targets: [
        .target(
            name: "MoshDeckCore",
            dependencies: [
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]),
        .testTarget(
            name: "MoshDeckCoreTests",
            dependencies: [
                "MoshDeckCore", .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
            ]),
    ]
)
