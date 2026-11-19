// swift-tools-version: 6.0
import PackageDescription
let package = Package(name:"CPTUploadHandler", platforms:[.iOS(.v17)], products:[.library(name:"Handler",targets:["Handler"])], targets:[.target(name:"Handler"),.testTarget(name:"HandlerTests",dependencies:["Handler"])], swiftLanguageModes:[.v5])
