import PackageDescription

let package = Package(
	name: "WarpCore",
	dependencies: [
		.Package(url: "https://github.com/pixelspark/swift-parser-generator", majorVersion: 1)
	]
)