import Foundation
struct Coord: Codable,Sendable { let latitude:Double; let longitude:Double }
struct Row: Codable,Sendable { let depth:Double }
struct CPTPointEntry: Codable,Sendable { let id:UUID; let coordinate:Coord; let rows:[Row] }
struct BoundaryPoint: Codable,Sendable { let latitude:Double }
enum CPTGridPolicy:String,Codable,Sendable {case legacyDynamic}
enum CPTDistancePolicy:String,Codable,Sendable {case legacyCellDiagonal,sufficiencyV32SiteDiagonal}
struct CPTGridConfig { let nx:Int,ny:Int,nz:Int; let dxM:Double,dyM:Double,dzM:Double; let validXYMask:[[Bool]]; func gridIndices(for c:Coord)->(ix:Int,iy:Int) { (Int(c.longitude.rounded()),Int(c.latitude.rounded())) } }
struct Project { let id:UUID; let gridPolicy:CPTGridPolicy; let cptDistancePolicy:CPTDistancePolicy; let boundaryPoints:[BoundaryPoint]; let cptPoints:[CPTPointEntry]; let cptRecommendationEvidence:[CPTRecommendationEvidence]; let cptInitialObservation:CPTInitialObservationEvidence? }
enum UncertaintySufficiencyService { static let v32FeatureParityVerified = true; static let defaultThreshold = 0.95; static let defaultPersistence = 2 }
@main struct Main {
 static func main() {
  let id=UUID(), boundary=[BoundaryPoint(latitude:1)], gp=CPTGridPolicy.legacyDynamic, dp=CPTDistancePolicy.sufficiencyV32SiteDiagonal
  let coords=[Coord(latitude:11,longitude:11),Coord(latitude:4,longitude:4),Coord(latitude:18,longitude:18),Coord(latitude:4,longitude:18)]
  let points=coords.map { CPTPointEntry(id:UUID(),coordinate:$0,rows:[Row(depth:0),Row(depth:11)]) }
  func state(_ count:Int)->String { CPTSufficiencyHistory.stateID(projectID:id,gridPolicy:gp,distancePolicy:dp,boundary:boundary,points:Array(points.prefix(count)))! }
  let initial=CPTInitialObservationEvidence(stateBefore:state(0),stateAfter:state(1),cptID:points[0].id,latitude:11,longitude:11)
  // Simulated acceptance events; these do not represent a field session.
  let evidence=(1..<4).map { i in CPTRecommendationEvidence(id:UUID(),stateBefore:state(i),recommendedLatitude:coords[i].latitude,recommendedLongitude:coords[i].longitude,model:"DQN V4.6-A Core ML",distancePolicy:dp.rawValue,acceptedCPTID:points[i].id,stateAfter:state(i+1),coordinateMatches:true,acceptedWithoutManualChange:true) }
  let good=Project(id:id,gridPolicy:gp,cptDistancePolicy:dp,boundaryPoints:boundary,cptPoints:points,cptRecommendationEvidence:evidence,cptInitialObservation:initial)
  let missing=Project(id:id,gridPolicy:gp,cptDistancePolicy:dp,boundaryPoints:boundary,cptPoints:points,cptRecommendationEvidence:[],cptInitialObservation:initial)
  let legacy=Project(id:id,gridPolicy:gp,cptDistancePolicy:.legacyCellDiagonal,boundaryPoints:boundary,cptPoints:points,cptRecommendationEvidence:evidence,cptInitialObservation:initial)
  let grid=CPTGridConfig(nx:24,ny:24,nz:12,dxM:5,dyM:5,dzM:1,validXYMask:Array(repeating:Array(repeating:true,count:24),count:24))
  var history:[CPTSufficiencyObservation]=[]
  for i in 1...4 { CPTSufficiencyHistory.record(.init(stateID:state(i),cptCount:i,probability:0.999),in:&history) }
  CPTSufficiencyHistory.record(.init(stateID:state(4),cptCount:4,probability:0.999),in:&history)
  precondition(history.count == 4 && CPTSufficiencyHistory.consecutivePositive(history,threshold:UncertaintySufficiencyService.defaultThreshold)==4)
  var edited=points
  edited[1] = CPTPointEntry(id:points[1].id,coordinate:Coord(latitude:5,longitude:4),rows:points[1].rows)
  let retained=CPTSufficiencyHistory.retainValidPrefixes(history,projectID:id,gridPolicy:gp,distancePolicy:dp,boundary:boundary,points:edited)
  precondition(retained.count == 1 && retained[0].cptCount == 1)
  let alteredBoundary=[BoundaryPoint(latitude:2)]
  precondition(CPTSufficiencyHistory.retainValidPrefixes(history,projectID:id,gridPolicy:gp,distancePolicy:dp,boundary:alteredBoundary,points:points).isEmpty)
  CPTSufficiencyHistory.testOnlyPipelineParityEvidence=true
  var calls=0
  func run(_ project:Project,_ entries:[CPTSufficiencyObservation]) -> (candidate:Int?,stop:Bool,positives:Int,compatible:Bool) {
   CPTSufficiencyDispatch.decide(project:project,points:points,grid:grid,history:entries,modelInputsValid:true) { calls += 1; return 7 }
  }
  let stop=run(good,history); precondition(stop.stop && stop.candidate == nil && calls == 0)
  let onePositive=CPTSufficiencyDispatch.decide(project:good,points:points,grid:grid,history:Array(history.suffix(1)),modelInputsValid:true) { 7 }
  precondition(!onePositive.stop && onePositive.candidate == 7)
  let twoPositive=CPTSufficiencyDispatch.decide(project:good,points:points,grid:grid,history:Array(history.suffix(2)),modelInputsValid:true) { 7 }
  precondition(twoPositive.stop && twoPositive.candidate == nil)
  var low=history; CPTSufficiencyHistory.record(.init(stateID:state(4),cptCount:4,probability:0.949),in:&low)
  let continuing=run(good,low); precondition(!continuing.stop && continuing.candidate == 7 && calls == 1)
  precondition(!run(missing,history).stop && !run(legacy,history).stop)
  var dynamicMask=Array(repeating:Array(repeating:false,count:32),count:32); dynamicMask[11][11]=true
  let dynamicGrid=CPTGridConfig(nx:32,ny:32,nz:16,dxM:7.139612356,dyM:7.134670784,dzM:0.733333333,validXYMask:dynamicMask)
  let beforeDynamicCalls=calls
  let dynamic=CPTSufficiencyDispatch.decide(project:good,points:points,grid:dynamicGrid,history:history,modelInputsValid:true) { calls += 1; return 7 }
  precondition(CPTSufficiencyHistory.validate(project:good,points:points,grid:dynamicGrid).failures.contains(.outsideResearchDomain))
  precondition(dynamic.stop && dynamic.candidate == nil && calls == beforeDynamicCalls)
  let dynamicContinue=CPTSufficiencyDispatch.decide(project:good,points:points,grid:dynamicGrid,history:low,modelInputsValid:true) { calls += 1; return 7 }
  precondition(!dynamicContinue.stop && dynamicContinue.candidate == 7 && calls == beforeDynamicCalls + 1)
  CPTSufficiencyHistory.testOnlyPipelineParityEvidence=false
  precondition(!run(good,history).stop)
  print("STOP, CONTINUE dispatch, provenance, legacy, duplicate state, missing parity: PASS (simulated events)")
 }
}
