import Foundation
import CoreLocation
struct Row:Decodable { let depth_m:Double; let qc_mpa:Double; let fs_kpa:Double; let ic:Double }
struct Profile:Decodable { let rows:[Row] }
struct Fixture:Decodable { let profiles:[Profile] }
@main struct Main {
 @MainActor static func main() throws {
  let f=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:Bundle.main.url(forResource:"fixture",withExtension:"json")!))
  let b=[BoundaryPoint(latitude:-6.242,longitude:106.830),BoundaryPoint(latitude:-6.242,longitude:106.832),BoundaryPoint(latitude:-6.240,longitude:106.832),BoundaryPoint(latitude:-6.240,longitude:106.830)]
  let p=Project(name:"SYNTHETIC TEST DATA",boundaryPoints:b,gridPolicy:.qcfsV3Enumerated,cptDistancePolicy:.sufficiencyV32SiteDiagonal)
  let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("projects.json")
  let storage=LocalProjectStorage(fileURL:url), pvm=ProjectViewModel(projects:[p],storage:storage), vm=CPTRecommendationViewModel(project:p); vm.projectViewModel=pvm
  for (i,profile) in f.profiles.enumerated() {
   vm.presentUploadSheet()
   if i==0 {
    let seed=CPTPointEntry(coordinate:CLLocationCoordinate2D(latitude:-6.241,longitude:106.831),file:CPTUploadedFile(name:"synthetic"),rows:profile.rows.map{CPTRowData(depth:$0.depth_m,coneResistance:$0.qc_mpa,localFriction:$0.fs_kpa,explicitIc:$0.ic)})
    let g=CPTGridConfig.build(boundaryCoordinates:vm.coordinates,cptPoints:[seed],policy:p.gridPolicy)
    let c=g.coordinate(ix:(g.nx-1)/2,iy:(g.ny-1)/2)
    vm.uploadCoordinatesText=String(format:"%.12f, %.12f",c.latitude,c.longitude)
   }
   vm.uploadParsedRows=profile.rows.map{CPTRowData(depth:$0.depth_m,coneResistance:$0.qc_mpa,localFriction:$0.fs_kpa,explicitIc:$0.ic)}
   vm.uploadedCPTFile=CPTUploadedFile(name:"synthetic.csv",rowCount:profile.rows.count,matchedColumns:vm.selectedCPTType.requiredColumns)
   vm.submitCPTUpload()
   guard vm.cptPoints.count==i+1 else {print("UPLOAD_FAIL n=\(i+1) reason=\(vm.uploadValidationError ?? "unknown")");exit(1)}
   let grid=CPTGridConfig.build(boundaryCoordinates:vm.coordinates,cptPoints:vm.cptPoints,policy:p.gridPolicy)
   let compat=CPTSufficiencyHistory.validate(project:vm.project,points:vm.cptPoints,grid:grid)
   print("n=\(i+1) probability=\(vm.recommendation.sufficiencyProbability) stop=\(vm.recommendation.isSufficient) dqn=\(vm.recommendation.recommendationSource) grid=\(grid.nx)x\(grid.ny)x\(grid.nz) spacing=\(grid.dxM),\(grid.dyM),\(grid.dzM) failures=\(compat.failures.map(\.rawValue))")
   if i==0 { guard vm.project.cptInitialObservation != nil else {fatalError("initial provenance absent")} }
   else { guard vm.project.cptRecommendationEvidence.contains(where:{$0.acceptedCPTID==vm.cptPoints[i].id && $0.acceptedWithoutManualChange==true}) else {fatalError("acceptance absent")} }
   if vm.recommendation.isSufficient { break }
   guard vm.recommendation.hasRecommendation else { print("NO_DQN_CANDIDATE"); break }
  }
  let reloaded=storage.loadProjects().first; guard reloaded?.cptPoints.count==vm.cptPoints.count else {fatalError("storage mismatch")}
  let legacy=Project(name:"legacy",boundaryPoints:b,gridPolicy:.legacyDynamic,cptDistancePolicy:.legacyCellDiagonal)
  print("new_policy=\(p.cptDistancePolicy.rawValue) legacy_policy=\(legacy.cptDistancePolicy.rawValue) synthetic_profiles=\(vm.cptPoints.count) persisted=true")
 }
}
