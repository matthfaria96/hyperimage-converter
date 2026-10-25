// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HyperImage",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "HyperImage", targets: ["HyperImage"]),
    ],
    dependencies: [
        // Atualizações dentro do app (MIT), como nos outros apps do witchmymac.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        // libwebp 1.6.0 (BSD), encoder side only: ImageIO already decodes WebP but cannot write it.
        .target(
            name: "CWebP",
            path: "Sources/CWebP",
            exclude: ["COPYING", "PATENTS"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("libwebp"),
                .define("WEBP_USE_THREAD"),
                .unsafeFlags(["-Wno-shorten-64-to-32", "-Wno-unused-function"]),
                .unsafeFlags(["-O3"], .when(configuration: .release)),
            ]
        ),
        // IJG libjpeg 9f: JPEG options ImageIO does not expose (subsampling, smoothing, Huffman) and lossless crop.
        .target(
            name: "CJPEG",
            path: "Sources/CJPEG",
            exclude: ["README-libjpeg.txt"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("libjpeg"),
                .unsafeFlags(["-Wno-shorten-64-to-32", "-Wno-unused-parameter", "-Wno-deprecated-non-prototype"]),
                .unsafeFlags(["-O3"], .when(configuration: .release)),
            ]
        ),
        .target(
            name: "HyperImageCore",
            dependencies: ["CWebP", "CJPEG"]
        ),
        .executableTarget(
            name: "HyperImage",
            dependencies: ["HyperImageCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        // App-level flows (input list, conversion runner) driven through the app's own models.
        .testTarget(
            name: "HyperImageAppTests",
            dependencies: ["HyperImage", "HyperImageCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "HyperImageCoreTests",
            dependencies: ["HyperImageCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
