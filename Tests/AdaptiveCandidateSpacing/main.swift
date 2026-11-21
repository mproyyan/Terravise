import Foundation
import CoreLocation
@main struct AdaptiveSpacingChecks {
 @MainActor static func main() throws {
  let sources=try JSONDecoder().decode([Project].self,from:Data(contentsOf:Bundle.main.url(forResource:"private-projects",withExtension:"json")!))
  var rows:[[String:Any]]=[]
  for (index,source) in sources.enumerated() where source.cptPoints.count>=30 {
   let grid=CPTGridConfig.build(boundaryCoordinates:source.boundaryCoordinates,cptPoints:source.cptPoints,policy:source.gridPolicy)
   var prefix=source;prefix.cptPoints=Array(source.cptPoints.dropLast());prefix.stratigraphicEvidence=nil;prefix.latestRecommendation=nil
   var beforeRec:SchemaGANReconstructionOutput?
   let before=CPTPipelineCoordinator.runPipeline(boundaryCoordinates:source.boundaryCoordinates,cptPoints:prefix.cptPoints,
    previousConsecutiveSufficientCount:0,gridPolicy:source.gridPolicy,distancePolicy:source.cptDistancePolicy,assessmentProject:prefix,
    onEvaluation:{r,_,_ in beforeRec=r})
   // Upgrade/reopen must not deadlock while the new build invalidates old
   // qualifying history: internal UNDETERMINED still permits a recommendation.
   let migrated=CPTRecommendationViewModel(project:source)
   precondition(migrated.recommendation.stratigraphicDecision?.outcome == .undetermined)
   precondition(migrated.recommendation.hasRecommendation && migrated.recommendation.candidateSpacing?.relaxed==true)
   // Before the final observed CPT, a normal candidate exists. Identical old DQN
   // argmax and Q score prove that no relaxation/ranking change occurs there.
   let br=beforeRec!,bg=br.grid,normal=source.cptDistancePolicy.minimumMeters(grid:bg)
   var baselineCount=0
   let baseline=DQNFeatureBuilder.recommendNextCandidate(reconstruction:br,grid:bg,
    cptCoordinates:br.observedSitesXY.map{bg.coordinate(ix:$0.ix,iy:$0.iy)},boundaryCoordinates:source.boundaryCoordinates,
    minimumSeparationMeters:normal,legalCandidateCount:{baselineCount=$0})!
   precondition(before.candidateSpacing!.attemptedMinimumM.count==1 && before.candidateSpacing!.legalCandidateCounts[0]==baselineCount)
   precondition(before.coordinate.latitude==bg.coordinate(ix:baseline.ix,iy:baseline.iy).latitude && before.coordinate.longitude==bg.coordinate(ix:baseline.ix,iy:baseline.iy).longitude && before.qValue==baseline.qValue)
   var current=source;current.stratigraphicEvidence=before.stratigraphicEvidence
   var reconstruction:SchemaGANReconstructionOutput?
   let result=CPTPipelineCoordinator.runPipeline(boundaryCoordinates:source.boundaryCoordinates,cptPoints:source.cptPoints,
    previousConsecutiveSufficientCount:0,gridPolicy:source.gridPolicy,distancePolicy:source.cptDistancePolicy,assessmentProject:current,
    onEvaluation:{r,_,_ in reconstruction=r})
   let rec=reconstruction!,trace=result.candidateSpacing!,floor=hypot(grid.dxM,grid.dyM)
   precondition(!result.isSufficient && result.hasRecommendation && result.recommendationSource=="DQN V4.6-A Core ML")
   precondition(result.stratigraphicDecision!.reasons==["PREDICTED_COVERAGE_BELOW_EXISTING_080_TARGET"])
   precondition(result.predictedCoverage==source.latestRecommendation!.predictedCoverage)
   precondition(trace.legalCandidateCounts.first==0 && trace.legalCandidateCounts.last!>0 && trace.relaxed)
   precondition(trace.usedMinimumM>=floor && trace.physicalMinimumM==floor)
   let coordinate=result.coordinate,chosen=grid.gridIndices(for:coordinate)
   precondition(grid.contains(coordinate,in:source.boundaryCoordinates) && grid.validXYMask[chosen.ix][chosen.iy])
   precondition(!rec.observedMask[chosen.ix][chosen.iy].contains(true))
   let physicalNearest=source.cptPoints.map{grid.distanceMeters(from:coordinate,to:$0.coordinate)}.min()!
   precondition(physicalNearest>=floor)
   // The relaxed pool's choice is the original DQN's exact argmax, not a proxy.
   let snapped=rec.observedSitesXY.map{grid.coordinate(ix:$0.ix,iy:$0.iy)}
   let direct=DQNFeatureBuilder.recommendNextCandidate(reconstruction:rec,grid:grid,cptCoordinates:snapped,
    boundaryCoordinates:source.boundaryCoordinates,minimumSeparationMeters:trace.usedMinimumM,
    physicalCPTCoordinates:source.cptPoints.map(\.coordinate),physicalMinimumSeparationMeters:floor)!
   precondition(chosen.ix==direct.ix && chosen.iy==direct.iy && result.qValue==direct.qValue)
   // An explicit mandatory minimum remains hard. Do not force an unsafe point.
   let blocked=CPTPipelineCoordinator.runPipeline(boundaryCoordinates:source.boundaryCoordinates,cptPoints:source.cptPoints,
    previousConsecutiveSufficientCount:0,gridPolicy:source.gridPolicy,distancePolicy:source.cptDistancePolicy,
    minimumSeparationMeters:Double.greatestFiniteMagnitude,assessmentProject:current)
   precondition(!blocked.isSufficient && !blocked.hasRecommendation && blocked.recommendationSource=="DQN_NO_CANDIDATES_WITHIN_PHYSICAL_CONSTRAINTS")
   precondition(blocked.candidateSpacing!.attemptedMinimumM.count==1)
   // Save/reopen through the actual storage and ViewModel recomputation paths.
   current.stratigraphicEvidence=result.stratigraphicEvidence;current.latestRecommendation=result
   let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("projects.json")
   let storage=LocalProjectStorage(fileURL:file);storage.saveProjects([current]);let loaded=storage.loadProjects().first!
   let vm=CPTRecommendationViewModel(project:loaded)
   precondition(vm.recommendation==result && vm.recommendation.candidateSpacing==trace)
   vm.presentUploadSheet()
   let acceptance=vm.project.cptRecommendationEvidence.last!
   precondition(acceptance.candidateSpacing==trace && acceptance.acceptedCPTID==nil)
   var changed=source;changed.cptPoints.removeLast();changed.stratigraphicEvidence=result.stratigraphicEvidence
   let edited=CPTRecommendationViewModel(project:changed)
   precondition(edited.recommendation.stratigraphicDecision?.outcome == .undetermined)
   precondition(edited.recommendation.candidateSpacing?.relaxed==false)
   rows.append(["index":index,"area_m2":grid.siteAreaM2,"CPT":source.cptPoints.count,"coverage":result.predictedCoverage,
    "normal_m":trace.normalMinimumM,"physical_resolution_floor_m":floor,"attempted_minimum_m":trace.attemptedMinimumM,
    "legal_candidate_counts":trace.legalCandidateCounts,"effective_minimum_m":trace.usedMinimumM,
    "selected_actual_nearest_distance_m":physicalNearest,"q_value":result.qValue,"DQN":result.recommendationSource,
    "normal_candidate_count":baselineCount,"migration_allows_adaptive_recommendation":true,"normal_argmax_unchanged":true,"relaxed_argmax_original_DQN":true,"hard_floor_blocks_without_STOP":true,
    "save_reopen_history_acceptance":true,"edit_invalidates_history":true])
   print("ADAPTIVE_ACTUAL index=\(index) spacing=\(trace.attemptedMinimumM) candidates=\(trace.legalCandidateCounts) DQN_Q=\(result.qValue) PASS")
  }
  precondition(rows.count==2)
  try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
  print("ADAPTIVE_SPACING_ACTUAL_CHECKS_PASS")
 }
}
