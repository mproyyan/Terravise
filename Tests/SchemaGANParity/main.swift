import Foundation
import CoreLocation
struct StubPoint { let coordinate: CLLocationCoordinate2D }
enum CPTRecommendationViewModel { static let defaultSamplePoints: [StubPoint] = [] }
struct Row: Decodable { let depth_m: Double; let qc_mpa: Double; let fs_kpa: Double; let ic: Double }
struct Profile: Decodable { let x: Int; let y: Int; let rows: [Row] }
struct Fixture: Decodable { let shape_xyz: [Int]; let spacing_m: [Double]; let valid_xy: [Bool]; let profiles: [Profile] }
let f = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let nx=f.shape_xyz[0], ny=f.shape_xyz[1], nz=f.shape_xyz[2], dx=f.spacing_m[0], dy=f.spacing_m[1], dz=f.spacing_m[2]
let grid = CPTGridConfig(nx:nx, ny:ny, nz:nz, dxM:dx, dyM:dy, dzM:dz, originLatitude:0, originLongitude:0, metersPerDegreeLat:100000, metersPerDegreeLon:100000, siteWidthM:Double(nx)*dx, siteHeightM:Double(ny)*dy, siteDiagonalM:hypot(Double(nx)*dx,Double(ny)*dy), siteAreaM2:Double(nx*ny)*dx*dy, aspectRatio:1, validXYMask:(0..<nx).map { x in (0..<ny).map { y in f.valid_xy[x*ny+y] } })
let points = f.profiles.map { p in CPTPointEntry(coordinate:grid.coordinate(ix:p.x,iy:p.y),file:CPTUploadedFile(name:"fixture"),rows:p.rows.map { r in CPTRowData(depth:r.depth_m,coneResistance:r.qc_mpa,localFriction:r.fs_kpa,explicitIc:r.ic) }) }
let result=SchemaGANService.reconstruct(cptPoints:points,grid:grid)
guard result.inferenceSource == "SchemaGAN V4.2 Flexible Core ML", SchemaGANService.parityInput.count == 7*nx*ny*nz else { fatalError("Core ML inference or input capture failed: \(result.inferenceSource)") }
let output: [String:Any] = ["shape":[1,7,nz,ny,nx],"input":SchemaGANService.parityInput.map(Double.init),"output_xyz":result.reconstructedIc.flatMap{$0.flatMap{$0}},"observed_xyz":result.observedMask.flatMap{$0.flatMap{$0}},"valid_xyz":result.validMask.flatMap{$0.flatMap{$0}},"sites":result.observedSitesXY.map{[$0.ix,$0.iy]},"source":result.inferenceSource]
try JSONSerialization.data(withJSONObject:output).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
