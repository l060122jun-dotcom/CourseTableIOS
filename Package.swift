// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CourseTableCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "CourseTableCore", targets: ["CourseTableCore"])
    ],
    targets: [
        .target(
            name: "CourseTableCore",
            path: "Sources/CourseTableCore"
        ),
        .testTarget(
            name: "CourseTableCoreTests",
            dependencies: ["CourseTableCore"],
            path: "Tests/CourseTableCoreTests"
        )
    ]
)
