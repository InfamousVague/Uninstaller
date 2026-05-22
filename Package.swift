// swift-tools-version: 5.9
import PackageDescription

// Uninstaller ships TWO products from one source tree, same shape as
// every other MattsSoftware suite app:
//
//  • `UninstallerPane` — dynamic library exposing the SuiteKit pane
//    (inventory + residue scanner + trasher + UI). The launcher
//    `dlopen`s this out of the installed Uninstaller.app.
//  • `Uninstaller` — thin @main standalone host (NSStatusItem +
//    NSPopover) that hosts the same pane. Defers to the launcher
//    via SuiteGuard when merged so there's no duplicate menu icon.
let package = Package(
    name: "Uninstaller",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Uninstaller", targets: ["Uninstaller"]),
        .library(name: "UninstallerPane", type: .dynamic,
                 targets: ["UninstallerPane"])
    ],
    dependencies: [ .package(path: "../suitekit-swift") ],
    targets: [
        .target(
            name: "UninstallerPane",
            dependencies: [.product(name: "SuiteKit",
                                    package: "suitekit-swift")],
            path: "Sources/UninstallerPane",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Uninstaller",
            dependencies: ["UninstallerPane",
                           .product(name: "SuiteKit",
                                    package: "suitekit-swift")],
            path: "Sources/Uninstaller"
        )
    ]
)
