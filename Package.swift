// swift-tools-version: 6.0
import PackageDescription

// Die SwiftUI-App gibt es nur auf Apple-Plattformen. Package.swift läuft auf dem
// Host, deshalb blendet #if os(macOS) das App-Target unter Linux komplett aus —
// dort bleiben Core, CLI und Tests übrig. Ohne diesen Schalter versuchte
// `swift build` unter Linux SwiftUI zu importieren und scheiterte.
#if os(macOS)
let appProducts: [Product] = [
    .executable(name: "SavageModPlayerApp", targets: ["SavageModPlayerApp"])
]
let appTargets: [Target] = [
    .executableTarget(
        name: "SavageModPlayerApp",
        dependencies: ["SavageModPlayerCore"],
        path: "Sources/SavageModPlayerApp"
    )
]
#else
let appProducts: [Product] = []
let appTargets: [Target] = []
#endif

#if os(Linux)
let mediaTargets: [Target] = [
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
    )
]
let cliDependencies: [Target.Dependency] = ["SavageModPlayerCore", "CMPRIS"]
#else
let mediaTargets: [Target] = []
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
        .library(name: "SavageModPlayerCore", targets: ["SavageModPlayerCore"])
    ],
    targets: appTargets + mediaTargets + [
        // Kleine C11-Atomik-Bruecke fuer den Echtzeit-Renderzustand. Swifts
        // Synchronization.Atomic ist erst ab macOS 15 verfuegbar; die App
        // unterstuetzt weiterhin macOS 13 und Linux.
        .target(
            name: "CSavageAtomics",
            path: "Sources/CSavageAtomics",
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
        ),
        .target(
            name: "SavageModPlayerCore",
            dependencies: [
                "CSavageAtomics",
                // Nur der Linux-Build zieht ALSA herein — auf macOS laeuft die
                // Ausgabe ueber AVAudioEngine und CALSA wird nie angefasst.
                .target(name: "CALSA", condition: .when(platforms: [.linux])),
                // Dasselbe fuer zlib: Der ZIP-Leser nutzt auf Apple das
                // Framework Compression und nur unter Linux die Systembibliothek.
                .target(name: "CZlib", condition: .when(platforms: [.linux]))
            ],
            path: "Sources/SavageModPlayerCore"
        ),
        // Kopfloser CLI-Renderer (headless Tests + Linux-Port-Fundament).
        .executableTarget(
            name: "SavageCLI",
            dependencies: cliDependencies,
            path: "Sources/SavageCLI"
        ),
        .testTarget(
            name: "SavageModPlayerTests",
            dependencies: [
                "SavageModPlayerCore",
                // Die ZIP-Tests erzeugen ihre Archive selbst und brauchen dafuer
                // einen Raw-Deflate-Encoder: auf Apple das Framework
                // Compression, unter Linux die zlib.
                .target(name: "CZlib", condition: .when(platforms: [.linux]))
            ],
            path: "Tests/SavageModPlayerTests"
        )
    ]
)
