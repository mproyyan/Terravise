import Foundation
import CoreLocation
struct StubPoint { let coordinate: CLLocationCoordinate2D }
enum CPTRecommendationViewModel { static let defaultSamplePoints:[StubPoint] = [] }
struct GridData:Decodable {let nx:Int,ny:Int,nz:Int;let dx_m:Double,dy_m:Double,dz_m:Double}
struct Obs:Decodable {let n:Int;let probability:Double}
struct Expected:Decodable {let volume:String;let stop_cpt:Int;let observations:[Obs]}
struct Fixture:Decodable {let grid:GridData;let truth:[Double];let expected:Expected}
let f=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
let n=f.grid.nx,m=f.grid.ny,z=f.grid.nz,dx=f.grid.dx_m,dy=f.grid.dy_m,dz=f.grid.dz_m,originLat = -6.24,originLon=106.83,meters=100000.0
let grid=CPTGridConfig(nx:n,ny:m,nz:z,dxM:dx,dyM:dy,dzM:dz,originLatitude:originLat,originLongitude:originLon,metersPerDegreeLat:meters,metersPerDegreeLon:meters,siteWidthM:Double(n)*dx,siteHeightM:Double(m)*dy,siteDiagonalM:hypot(Double(n)*dx,Double(m)*dy),siteAreaM2:Double(n*m)*dx*dy,aspectRatio:1,validXYMask:Array(repeating:Array(repeating:true,count:m),count:n))
CPTPipelineCoordinator.researchTestGrid=grid
CPTSufficiencyHistory.syntheticReplayEnabled=true
let west=originLon-1/meters,south=originLat-1/meters,east=originLon+(Double(n-1)*dx+1)/meters,north=originLat+(Double(m-1)*dy+1)/meters
let b=[BoundaryPoint(latitude:south,longitude:west),BoundaryPoint(latitude:south,longitude:east),BoundaryPoint(latitude:north,longitude:east),BoundaryPoint(latitude:north,longitude:west)]
var project=Project(name:"TEST-ONLY synthetic Ic replay",boundaryPoints:b,gridPolicy:.qcfsV3Enumerated,cptDistancePolicy:.sufficiencyV32SiteDiagonal)
var x=(n-1)/2,y=(m-1)/2, probabilities:[Double]=[]
for i in 0..<32 {
 let coord=grid.coordinate(ix:x,iy:y); let before=CPTSufficiencyHistory.stateID(projectID:project.id,gridPolicy:project.gridPolicy,distancePolicy:project.cptDistancePolicy,boundary:b,points:project.cptPoints)!
 // Ic-only test input. Sentinel qc/fs are never consumed; QC-FS is outside this replay.
 let rows=(0..<z).map{ k in CPTRowData(depth:Double(k)*dz,coneResistance:0,localFriction:0,explicitIc:f.truth[(x*m+y)*z+k]) }
 let entry=CPTPointEntry(coordinate:coord,file:CPTUploadedFile(name:"TEST-ONLY synthetic Ic"),rows:rows);project.cptPoints.append(entry)
 let after=CPTSufficiencyHistory.stateID(projectID:project.id,gridPolicy:project.gridPolicy,distancePolicy:project.cptDistancePolicy,boundary:b,points:project.cptPoints)!
 if i==0 { project.cptInitialObservation = .init(stateBefore:before,stateAfter:after,cptID:entry.id,latitude:coord.latitude,longitude:coord.longitude) }
 else { project.cptRecommendationEvidence.append(.init(id:UUID(),stateBefore:before,recommendedLatitude:coord.latitude,recommendedLongitude:coord.longitude,model:"DQN V4.6-A Core ML",distancePolicy:project.cptDistancePolicy.rawValue,acceptedCPTID:entry.id,stateAfter:after,coordinateMatches:true,acceptedWithoutManualChange:true)) }
 let compatibility=CPTSufficiencyHistory.validate(project:project,points:project.cptPoints,grid:grid)
 guard compatibility.isCompatible else { print("VALIDATOR FAIL n=\(i+1) \(compatibility.failures.map(\.rawValue))");exit(1) }
 let result=CPTPipelineCoordinator.runPipeline(boundaryCoordinates:project.boundaryCoordinates,cptPoints:project.cptPoints,previousConsecutiveSufficientCount:0,gridPolicy:project.gridPolicy,distancePolicy:project.cptDistancePolicy,assessmentProject:project)
 probabilities.append(result.sufficiencyProbability);let reference=f.expected.observations[i].probability
 print("n=\(i+1) p=\(result.sufficiencyProbability) reference=\(reference) delta=\(result.sufficiencyProbability-reference) stop=\(result.isSufficient) dqn=\(result.hasRecommendation)")
 guard result.assessmentSource == "Sufficiency V3.2 experimental; STOP unavailable: DQN trajectory not verified" else {print("INFERENCE UNAVAILABLE");exit(1)}
 CPTSufficiencyHistory.record(.init(stateID:after,cptCount:i+1,probability:result.sufficiencyProbability),in:&project.sufficiencyObservations)
 if result.isSufficient { guard !result.hasRecommendation,probabilities.count>=4,probabilities.suffix(4).allSatisfy({$0>=UncertaintySufficiencyService.defaultThreshold}) else {fatalError("invalid STOP")};let repeated=CPTPipelineCoordinator.runPipeline(boundaryCoordinates:project.boundaryCoordinates,cptPoints:project.cptPoints,previousConsecutiveSufficientCount:0,gridPolicy:project.gridPolicy,distancePolicy:project.cptDistancePolicy,assessmentProject:project)
 guard repeated.isSufficient && !repeated.hasRecommendation else {fatalError("repeated state released STOP")}
 print("STOP_TEST_ONLY cpt=\(i+1) saved=\(32-i-1) four=\(Array(probabilities.suffix(4))) referenceStop=\(f.expected.stop_cpt) volume=\(f.expected.volume)");exit(0) }
 guard result.hasRecommendation, result.recommendationSource=="DQN V4.6-A Core ML" else {print("DQN UNAVAILABLE");exit(1)}
 let next=grid.gridIndices(for:result.coordinate);x=next.ix;y=next.iy
}
print("NO STOP");exit(1)
