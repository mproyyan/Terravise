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

let bundle=Bundle.main
precondition(CPTPipelineParityAttestation.verified(points:points,grid:grid,bundle:bundle),"valid attestation rejected")
let wrongGrid=CPTGridConfig(nx:nx, ny:ny, nz:nz, dxM:dx+1, dyM:dy, dzM:dz, originLatitude:0, originLongitude:0, metersPerDegreeLat:100000, metersPerDegreeLon:100000, siteWidthM:Double(nx)*dx, siteHeightM:Double(ny)*dy, siteDiagonalM:hypot(Double(nx)*dx,Double(ny)*dy), siteAreaM2:Double(nx*ny)*dx*dy, aspectRatio:1, validXYMask:grid.validXYMask)
precondition(CPTPipelineParityAttestation.verified(points:points,grid:wrongGrid,bundle:bundle),"implementation identity must be independent of project grid")
var changed=points; changed[0].rows[0].explicitIc = 3.9
precondition(CPTPipelineParityAttestation.verified(points:changed,grid:grid,bundle:bundle),"implementation identity must be independent of project profile")
let path=bundle.url(forResource:"CPTParityAttestation",withExtension:"json")!;let original=try Data(contentsOf:path)
var envelope=try JSONSerialization.jsonObject(with:original) as! [String:Any]
envelope["valid"]=false
try JSONSerialization.data(withJSONObject:envelope).write(to:path)
precondition(!CPTPipelineParityAttestation.verified(points:points,grid:grid,bundle:bundle),"failed attestation accepted")
envelope["valid"]=true
var fp=envelope["fingerprints"] as! [String:String];fp["swift_schemgan"]="invalid";envelope["fingerprints"]=fp
try JSONSerialization.data(withJSONObject:envelope).write(to:path)
precondition(!CPTPipelineParityAttestation.verified(points:points,grid:grid,bundle:bundle),"fingerprint mismatch accepted")
try Data("bad json".utf8).write(to:path)
precondition(!CPTPipelineParityAttestation.verified(points:points,grid:grid,bundle:bundle),"corrupt attestation accepted")
try FileManager.default.removeItem(at:path)
precondition(!CPTPipelineParityAttestation.verified(points:points,grid:grid,bundle:bundle),"missing attestation accepted")
print("valid, out-of-scope grid, changed profile, failed, altered fingerprint, corrupt and missing evidence: PASS")
