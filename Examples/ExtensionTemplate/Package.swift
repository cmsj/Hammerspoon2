// swift-tools-version: 6.2
//
// A Hammerspoon 2 extension, built as a dynamic library that build.sh wraps in a .hsmodule
// bundle. Rename the target and product, and the extension's name in build.sh and
// Bundle/Info.plist, to make it your own.

import Foundation
import PackageDescription

// Builds against a local copy of the HammerspoonSDK package if HAMMERSPOON_SDK_PACKAGE is set
// to its directory, for example to try an SDK that hasn't been released yet
let sdkPath = Context.environment["HAMMERSPOON_SDK_PACKAGE"]
let sdk: Package.Dependency = if let sdkPath {
    .package(path: sdkPath)
} else {
    .package(url: "https://github.com/cmsj/HammerspoonSDK", from: "1.0.0")
}
// A local package is known by its directory's name
let sdkPackage = sdkPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "HammerspoonSDK"

let package = Package(
    name: "ExampleExtension",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "ExampleExtension", type: .dynamic, targets: ["ExampleExtension"]),
    ],
    dependencies: [sdk],
    targets: [
        .target(
            name: "ExampleExtension",
            dependencies: [.product(name: "HammerspoonSDK", package: sdkPackage)],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
