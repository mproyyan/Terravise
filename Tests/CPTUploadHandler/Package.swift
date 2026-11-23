// swift-tools-version: 6.0
import PackageDescription
let package = Package(name:"CPTUploadHandler", platforms:[.iOS("27.0")], products:[.library(name:"Handler",targets:["Handler"])], targets:[.target(name:"Handler"),.testTarget(name:"HandlerTests",dependencies:["Handler"],resources:[.copy("stop-sync-snapshot.json")])], swiftLanguageModes:[.v5])
