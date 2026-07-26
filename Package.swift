// swift-tools-version:5.9
import PackageDescription

// BootCaptain is split so the load-bearing logic is portable and testable off
// a Mac:
//
//   BootCaptainCore  - pure models, parsers, classifiers, and safety logic.
//                      Depends only on Foundation and builds/tests on Linux CI.
//   BootCaptainKit   - macOS collectors and system adapters (filesystem,
//                      launchctl/sfltool, code signing, unified log). Its
//                      bodies are `#if os(macOS)`-guarded so the package still
//                      compiles on Linux, where the Mac types compile to empty.
//   bootcaptain      - command-line front end (scan / audit / export).
//
// The SwiftUI app and the privileged helper are built by the Xcode project
// generated from `project.yml`; their sources live under `App/` and `Helper/`
// and link `BootCaptainCore` + `BootCaptainKit`.
let package = Package(
    name: "BootCaptain",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BootCaptainCore", targets: ["BootCaptainCore"]),
        .library(name: "BootCaptainKit", targets: ["BootCaptainKit"]),
        .executable(name: "bootcaptain", targets: ["bootcaptain"]),
    ],
    targets: [
        .target(name: "BootCaptainCore"),
        .target(name: "BootCaptainKit", dependencies: ["BootCaptainCore"]),
        .executableTarget(
            name: "bootcaptain",
            dependencies: ["BootCaptainCore", "BootCaptainKit"]
        ),
        .testTarget(name: "BootCaptainCoreTests", dependencies: ["BootCaptainCore"]),
        .testTarget(
            name: "BootCaptainKitTests",
            dependencies: ["BootCaptainKit", "BootCaptainCore"]
        ),
    ]
)
