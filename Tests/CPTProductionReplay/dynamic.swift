import Foundation
import CoreLocation
struct Fixture:Decodable {let Ic:[Double];let qc_mpa:[Double];let fs_mpa:[Double]}
@main struct Main {
 @MainActor static func main() throws {
  let f=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:Bundle.main.url(forResource:"fixture",withExtension:"json")!))
  let b=[BoundaryPoint(latitude:-6.242,longitude:106.830),BoundaryPoint(latitude:-6.242,longitude:106.832),BoundaryPoint(latitude:-6.240,longitude:106.832),BoundaryPoint(latitude:-6.240,longitude:106.830)]
  let p=Project(name:"synthetic dynamic test",boundaryPoints:b,gridPolicy:.qcfsV3Enumerated,cptDistancePolicy:.sufficiencyV32SiteDiagonal)
  let store=LocalProjectStorage(fileURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("projects.json"));let pvm=ProjectViewModel(projects:[p],storage:store),vm=CPTRecommendationViewModel(project:p);vm.projectViewModel=pvm
  let seed=CPTPointEntry(coordinate:CLLocationCoordinate2D(latitude:-6.241,longitude:106.831),file:CPTUploadedFile(name:"synthetic"),rows:[CPTRowData(depth:0,coneResistance:1,localFriction:1),CPTRowData(depth:11,coneResistance:1,localFriction:1)])
  let g=CPTGridConfig.build(boundaryCoordinates:vm.coordinates,cptPoints:[seed],policy:p.gridPolicy);guard g.nx==32 && g.ny==32 && g.nz==16 else {fatalError("unexpected grid")}
  for i in 0..<32 {
   vm.presentUploadSheet();let c:CLLocationCoordinate2D
   if i==0 {c=g.coordinate(ix:15,iy:15);vm.uploadCoordinatesText=String(format:"%.12f, %.12f",c.latitude,c.longitude)} else {c=vm.recommendation.coordinate}
   let xy=g.gridIndices(for:c)
   vm.uploadParsedRows=(0..<16).map{k in let j=(xy.ix*32+xy.iy)*16+k;return CPTRowData(depth:Double(k)*g.dzM,coneResistance:f.qc_mpa[j],localFriction:f.fs_mpa[j]*1000,explicitIc:f.Ic[j])}
   vm.uploadedCPTFile=CPTUploadedFile(name:"synthetic.csv",rowCount:16,matchedColumns:vm.selectedCPTType.requiredColumns);vm.submitCPTUpload()
   guard vm.cptPoints.count==i+1 else {print("UPLOAD FAILED: \(vm.uploadValidationError ?? "unknown")");exit(1)}
   let compat=CPTSufficiencyHistory.validate(project:vm.project,points:vm.cptPoints,grid:g)
   print("n=\(i+1) p=\(vm.recommendation.sufficiencyProbability) stop=\(vm.recommendation.isSufficient) dqn=\(vm.recommendation.hasRecommendation) failures=\(compat.failures.map(\.rawValue))")
   if vm.recommendation.isSufficient {print("STOP cpt=\(i+1) source=synthetic; not field data");exit(0)}
   guard vm.recommendation.hasRecommendation else {print("DQN unavailable");exit(1)}
  }
  print("NO STOP by 32 CPT")
 }
}
