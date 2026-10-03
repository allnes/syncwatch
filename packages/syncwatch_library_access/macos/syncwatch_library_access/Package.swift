// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "syncwatch_library_access",
  platforms: [.macOS("10.15")],
  products: [
    .library(name: "syncwatch-library-access", targets: ["syncwatch_library_access"])
  ],
  dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
  targets: [
    .target(
      name: "syncwatch_library_access",
      dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")]
    )
  ]
)
