// swift-tools-version:5.9
import PackageDescription

// Resources live in app/Resources and are copied by scripts/bundle.sh.
// They are deliberately NOT SwiftPM resources: Bundle.module breaks inside a hand-built .app.
let package = Package(
    name: "Hangabouts",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Hangabouts",
            path: "Sources/Hangabouts"
        )
    ]
)
