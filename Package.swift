// swift-tools-version: 5.9
import PackageDescription

// MobileDataCore is the "Shared Core" from the design brief (§4). It holds *all*
// business logic so the main app and the widget extension behave identically:
// counter reading, sampling + reboot handling, persistence, forecasting, the
// cost model and alert evaluation. Both Xcode targets link against this package.
//
// The package is intentionally dependency-free and platform-agnostic where it
// can be: only the raw interface-counter reader touches Darwin APIs (guarded by
// `#if canImport(Darwin)`), so the rest of the logic compiles and unit-tests on
// any Swift toolchain using a mock counter source.
let package = Package(
    name: "MobileDataCore",
    platforms: [
        // iOS is the product target; macOS is declared so the dependency-free
        // logic can be unit-tested with `swift test` directly on a Mac/CI host
        // (no simulator needed). Only InterfaceCounterReader is Darwin-specific
        // and it compiles on both.
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "MobileDataCore", targets: ["MobileDataCore"])
    ],
    targets: [
        .target(
            name: "MobileDataCore",
            path: "Sources/MobileDataCore"
        ),
        .testTarget(
            name: "MobileDataCoreTests",
            dependencies: ["MobileDataCore"],
            path: "Tests/MobileDataCoreTests"
        )
    ]
)
