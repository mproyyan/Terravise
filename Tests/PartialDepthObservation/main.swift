import CoreLocation
import Foundation

/// Adapter/history unit fixtures, not model accuracy or field-sufficiency evidence.
@main struct PartialDepthObservationChecks {
  @MainActor static func main() throws {
    let grid = CPTGridConfig(nx:4,ny:4,nz:4,dxM:10,dyM:10,dzM:1,
      originLatitude:0,originLongitude:0,metersPerDegreeLat:100000,metersPerDegreeLon:100000,
      siteWidthM:30,siteHeightM:30,siteDiagonalM:hypot(30,30),siteAreaM2:900,aspectRatio:1,
      validXYMask:Array(repeating:Array(repeating:true,count:4),count:4))
    let cells=[(0,0),(0,3),(3,0),(3,3)]
    let boundary=[(0,0),(3,0),(3,3),(0,3)].map { BoundaryPoint(coordinate:grid.coordinate(ix:$0.0,iy:$0.1)) }
    func project(_ ends:[Double]) -> Project {
      var p=Project(name:"Partial-depth adapter UNIT fixture",boundaryPoints:boundary)
      p.cptPoints=ends.enumerated().map { i,end in
        CPTPointEntry(coordinate:grid.coordinate(ix:cells[i].0,iy:cells[i].1),
          file:CPTUploadedFile(name:"unit.csv",rowCount:2),rows:[
            CPTRowData(depth:0,coneResistance:5,localFriction:50,explicitIc:2.3),
            CPTRowData(depth:end,coneResistance:5,localFriction:50,explicitIc:2.3)])
      }
      return p
    }
    func state(_ p:Project) -> String {
      CPTSufficiencyHistory.stateID(projectID:p.id,gridPolicy:p.gridPolicy,distancePolicy:p.cptDistancePolicy,
        boundary:p.boundaryPoints,points:p.cptPoints)!
    }
    func assess(_ p:Project) -> (StratigraphicDecision,StratigraphicEvidence?) {
      let values=Array(repeating:Array(repeating:Array(repeating:2.3,count:4),count:4),count:4)
      let valid=Array(repeating:Array(repeating:Array(repeating:true,count:4),count:4),count:4)
      var observed=Array(repeating:Array(repeating:Array(repeating:false,count:4),count:4),count:4)
      for (i,point) in p.cptPoints.enumerated() {
        // Exercise the unchanged ML half-cell endpoint mapping: STOP must not
        // mistake a rounded bin outside the uploaded interval for measured data.
        let end=point.rows.map(\.depth).max()!
        for z in 0..<4 {observed[cells[i].0][cells[i].1][z]=Double(z)<=end+0.5}
      }
      let rec=SchemaGANReconstructionOutput(grid:grid,inferenceSource:"SchemaGAN V4.2 Flexible Core ML",
        reconstructedIc:values,observedIc:values,observedMask:observed,validMask:valid,
        observedSitesXY:Array(cells.prefix(p.cptPoints.count)).map{(ix:$0.0,iy:$0.1)})
      let uncertainty=UncertaintySufficiencyEvaluation(inferenceSource:"UNIT fixture",estimatedRMSE:0.1,
        predictedCoverage:1,sufficiencyProbability:0,confidenceLevelPercent:99,consecutiveSufficientCount:0,
        isSufficient:false,assessmentStatus:.reviewRequired,
        spatialBounds:Array(repeating:Array(repeating:Array(repeating:0.1,count:4),count:4),count:4),spatialEvidenceValid:true)
      return StratigraphicService.assess(project:p,points:p.cptPoints,grid:grid,reconstruction:rec,uncertainty:uncertainty)
    }
    func confirmed(_ ends:[Double]) -> (Project,StratigraphicDecision,StratigraphicEvidence) {
      var current=project(ends),prefix=current
      prefix.cptPoints.removeLast()
      let baseline=assess(prefix)
      precondition(baseline.0.reasons==["GENUINE_PREDECESSOR_UNAVAILABLE"] && baseline.1 != nil)
      current.stratigraphicEvidence=baseline.1
      // Explicit unit acquisition fixture only. Actual project tests below
      // never append or reconstruct acquisition history.
      current.stratigraphicAcquisitions=[.init(cptID:current.cptPoints.last!.id,before:state(prefix),after:state(current))]
      let result=assess(current)
      return (current,result.0,result.1!)
    }

    let full=confirmed([3,3,3,3])
    precondition(full.1.outcome == .stop && full.1.reasons==["AREA_SPREAD_STABILITY_AND_COVERAGE_ACCEPTABLE"])
    let partial=confirmed([1.5,3,3,3])
    precondition(partial.1.outcome == .stop && partial.1.reasons==full.1.reasons)
    precondition(partial.2.frame.measured[partial.2.frame.index(0,0,1)] != 255)
    precondition(partial.2.frame.measured[partial.2.frame.index(0,0,2)] == 255)
    precondition(partial.2.frame.measured[partial.2.frame.index(0,0,3)] == 255)
    let latestPartial=confirmed([3,3,3,1.5])
    precondition(latestPartial.1.outcome == .stop)
    precondition(latestPartial.2.frame.measured[latestPartial.2.frame.index(3,3,2)] == 255)
    let roundoff=confirmed([3,3,3,3-0.5e-6])
    precondition(roundoff.1.outcome == .stop && roundoff.2.frame.measured[roundoff.2.frame.index(3,3,3)] != 255)
    for ends in [[1.5,1.5,1.5,1.5],[2.6,2.6,2.6,2.6]] {
      let missing=assess(project(ends))
      precondition(missing.0.outcome == .undetermined && missing.0.reasons==["DEPTH_OBSERVATION_SUPPORT_UNAVAILABLE"] && missing.1==nil)
    }
    let imported=project([1.5,3,3,3]),initial=assess(imported)
    precondition(initial.0.outcome == .undetermined && initial.1 != nil)
    var reopened=imported;reopened.stratigraphicEvidence=initial.1
    precondition(assess(reopened).1==initial.1,"reopening must not create a confirming transition")
    var unverified=partial.0;unverified.stratigraphicAcquisitions=[]
    precondition(assess(unverified).0.outcome == .undetermined)
    var edited=partial.0;edited.cptPoints[0].rows[0].coneResistance=99
    precondition(assess(edited).0.outcome == .undetermined)
    var stopped=partial.0;stopped.stratigraphicEvidence=partial.2
    let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("projects.json")
    defer {try? FileManager.default.removeItem(at:file.deletingLastPathComponent())}
    let storage=LocalProjectStorage(fileURL:file);storage.saveProjects([stopped])
    precondition(assess(storage.loadProjects().first!).1==partial.2)
    var calls=0
    let stopDispatch=CPTSufficiencyDispatch.stratigraphic(partial.1){calls+=1;return 42}
    precondition(stopDispatch.stop && stopDispatch.candidate==nil && calls==0)
    for d in [initial.0,StratigraphicDecision(outcome:.continue,reasons:[],stateID:"unit",metrics:[:],evidenceValid:true)] {
      let next=CPTSufficiencyDispatch.stratigraphic(d){calls+=1;return 42}
      precondition(!next.stop && next.candidate==42)
    }
    precondition(calls==2)
    print("PARTIAL_DEPTH_UNIT_PASS: full, partial, latest-partial, missing-depth, rounded-endpoint, genuine-history, save/reopen, edit, dispatch")

    var report:[String:Any]=["unit_checks":"PASS"]
    let sources=try JSONDecoder().decode([Project].self,from:Data(contentsOf:Bundle.main.url(forResource:"private-projects",withExtension:"json")!))
    if let source=sources.first(where:{$0.id.uuidString=="6BF66ED7-8EB6-41A9-9E11-31B43D813638" && $0.cptPoints.count==127}) {
      var reconstruction:SchemaGANReconstructionOutput?
      let result=CPTPipelineCoordinator.runPipeline(boundaryCoordinates:source.boundaryCoordinates,cptPoints:source.cptPoints,
        previousConsecutiveSufficientCount:0,gridPolicy:source.gridPolicy,distancePolicy:source.cptDistancePolicy,
        assessmentProject:source,onEvaluation:{r,_,_ in reconstruction=r})
      let e=result.stratigraphicEvidence!,f=e.frame,rec=reconstruction!,old=source.latestRecommendation!
      precondition(source.stratigraphicEvidence==nil && e.stateIndex==0 && e.recent.isEmpty)
      precondition(result.stratigraphicDecision!.reasons==["GENUINE_PREDECESSOR_UNAVAILABLE"] && !result.isSufficient)
      precondition(result.hasRecommendation && result.predictedCoverage==old.predictedCoverage)
      precondition(result.coordinate.latitude==old.coordinate.latitude && result.coordinate.longitude==old.coordinate.longitude && result.qValue==old.qValue)
      let site=f.sites[6]
      for z in 0..<f.nz where Double(z)*f.dz>15 {precondition(f.measured[f.index(site[0],site[1],z)]==255)}
      var depthCounts:[Int]=[]
      for z in 0..<f.nz {depthCounts.append(f.sites.filter{f.measured[f.index($0[0],$0[1],z)] != 255}.count)}
      precondition(depthCounts.allSatisfy{$0>0} && depthCounts.last==126)
      var baseline=source;baseline.stratigraphicEvidence=e;baseline.latestRecommendation=result
      storage.saveProjects([baseline])
      let loaded=storage.loadProjects().first!,vm=CPTRecommendationViewModel(project:loaded)
      precondition(vm.recommendation.stratigraphicEvidence==e)
      precondition(vm.recommendation.stratigraphicDecision!.outcome == .undetermined && vm.recommendation.hasRecommendation)
      let standalone=StratigraphicStop.evaluate(f,previous:nil,recent:[],stateIndex:0)
      precondition(standalone.metrics["spatial_support_p95_ratio"]!<=1 && standalone.metrics["spatial_support_max_ratio"]!<=1.75)
      report["actual127"]=["project_id":source.id.uuidString,"cpt_state_id":e.cptStateID,"coverage":result.predictedCoverage,
        "spatial_metrics":standalone.metrics,"depth_observed_CPT_counts":depthCounts,"decision":result.stratigraphicDecision!.outcome.rawValue,
        "reasons":result.stratigraphicDecision!.reasons,"predecessor_available":false,"baseline_saved":true,
        "state_index":e.stateIndex,"transition_count":e.recent.count,"CPT7_not_extended":true,
        "DQN":result.recommendationSource,"recommendation":result.spotName,"q_value":result.qValue,
        "deepest_grid_center_m":Double(rec.grid.nz-1)*rec.grid.dzM,"save_reopen_did_not_confirm":true,
        "recommendation_matches_saved_coordinate_and_q":true]
      print("PARTIAL_DEPTH_ACTUAL_127_PASS: depths supported, CPT7 not extended, baseline127 saved; genuine predecessor unavailable; Spot128 retained")
    }
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
  }
}
