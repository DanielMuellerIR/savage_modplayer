// swift-tools-version: 6.0
import PackageDescription

// Die SwiftUI-App gibt es nur auf Apple-Plattformen. Package.swift läuft auf dem
// Host, deshalb blendet #if os(macOS) das App-Target unter Linux komplett aus —
// dort bleiben Core, CLI und Tests übrig. Ohne diesen Schalter versuchte
// `swift build` unter Linux SwiftUI zu importieren und scheiterte.
#if os(macOS)
// Updates ersetzen die installierte App; Versionswechsel werden bewusst geprüft.
let appDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
]
let appProducts: [Product] = [
    .executable(name: "SavageModPlayerApp", targets: ["SavageModPlayerApp"])
]
let appTargets: [Target] = [
    .executableTarget(
        name: "SavageModPlayerApp",
        dependencies: ["SavageModPlayerCore", .product(name: "Sparkle", package: "Sparkle")],
        path: "Sources/SavageModPlayerApp",
        linkerSettings: [
            // Die SwiftUI-Videobrücke lädt ihre AVPlayerView-Basisklasse nicht selbst.
            .linkedFramework("AVKit")
        ]
    ),
    .testTarget(
        name: "SavageModPlayerAppTests",
        dependencies: ["SavageModPlayerApp", "SavageModPlayerCore"],
        path: "Tests/SavageModPlayerAppTests"
    )
]
#else
let appDependencies: [Package.Dependency] = []
let appProducts: [Product] = []
let appTargets: [Target] = []
#endif

#if os(Linux)
let linuxTargets: [Target] = [
    .systemLibrary(
        name: "CDBus",
        path: "Sources/CDBus",
        pkgConfig: "dbus-1",
        providers: [.apt(["libdbus-1-dev"])]
    ),
    .target(
        name: "CMPRIS",
        dependencies: ["CDBus"],
        path: "Sources/CMPRIS",
        publicHeadersPath: "include"
    ),
    // ALSA-Systembibliothek (nur Linux; siehe Sources/CALSA/module.modulemap).
    // Braucht auf dem Build-Rechner das Paket libasound2-dev.
    .systemLibrary(
        name: "CALSA",
        path: "Sources/CALSA",
        pkgConfig: "alsa",
        providers: [
            .apt(["libasound2-dev"])
        ]
    ),
    // zlib (nur Linux; siehe Sources/CZlib/module.modulemap). Auf Apple
    // uebernimmt das Framework Compression, dort wird dieses Modul nicht
    // eingebunden. Braucht auf dem Build-Rechner das Paket zlib1g-dev.
    .systemLibrary(
        name: "CZlib",
        path: "Sources/CZlib",
        pkgConfig: "zlib",
        providers: [
            .apt(["zlib1g-dev"])
        ]
    )
]
let cliDependencies: [Target.Dependency] = ["SavageModPlayerCore", "CMPRIS"]
let corePlatformDependencies: [Target.Dependency] = ["CALSA", "CZlib"]
let testPlatformDependencies: [Target.Dependency] = ["CZlib"]
#else
let linuxTargets: [Target] = []
let corePlatformDependencies: [Target.Dependency] = []
let testPlatformDependencies: [Target.Dependency] = []
let cliDependencies: [Target.Dependency] = ["SavageModPlayerCore"]
#endif

let package = Package(
    name: "SavageModPlayerApp",
    platforms: [
        .macOS(.v13),
        // iOS 17 ist das Minimum der iPhone-App unter ios/ — dort werden
        // Observation, .scrollTargetBehavior und die neueren SwiftUI-APIs
        // genutzt. Der Core selbst kaeme mit weniger aus, aber ein einziges
        // Minimum haelt Paket und App-Target deckungsgleich.
        .iOS(.v17)
    ],
    products: appProducts + [
        .executable(name: "savage-cli", targets: ["SavageCLI"]),
        .executable(name: "savage-desktop-engine", targets: ["SavageDesktopEngine"]),
        .library(name: "SavageModPlayerCore", targets: ["SavageModPlayerCore"])
    ],
    dependencies: appDependencies,
    targets: appTargets + linuxTargets + [
        // Kleine C11-Atomik-Bruecke fuer den Echtzeit-Renderzustand. Swifts
        // Synchronization.Atomic ist erst ab macOS 15 verfuegbar; die App
        // unterstuetzt weiterhin macOS 13 und Linux.
        .target(
            name: "CSavageAtomics",
            path: "Sources/CSavageAtomics",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SavageModPlayerCore",
            dependencies: ["CSavageAtomics"] + corePlatformDependencies,
            path: "Sources/SavageModPlayerCore"
        ),
        // Kopfloser CLI-Renderer (headless Tests + Linux-Port-Fundament).
        .executableTarget(
            name: "SavageCLI",
            dependencies: cliDependencies,
            path: "Sources/SavageCLI"
        ),
        .executableTarget(
            name: "SavageDesktopEngine",
            dependencies: ["SavageModPlayerCore"],
            path: "Sources/SavageDesktopEngine"
        ),
        .testTarget(
            name: "SavageModPlayerTests",
            dependencies: ["SavageModPlayerCore"] + testPlatformDependencies,
            path: "Tests/SavageModPlayerTests"
        )
    ]
)
