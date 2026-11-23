import XCTest
import SwiftUI
import UIKit
@testable import Handler

@MainActor final class CharacterizationStorageTests: XCTestCase {
  /// Explicit active-policy unit fixture. Not model/field evidence.
  private func evidence(_ outcome: StratigraphicDecision.Outcome) -> StratigraphicEvidence {
    let sites = [[0,0],[0,3],[3,0],[3,3]]
    var frame = StratigraphicFrame(nx:4,ny:4,nz:4,dx:1,dy:1,dz:1,area:16,
      valid:Array(repeating:true,count:64),classes:Array(repeating:2,count:64),
      measured:Array(repeating:255,count:64),ambiguity:Array(repeating:false,count:64),sites:sites,stateID:"c",count:4)
    for site in sites { for z in 0..<4 { frame.measured[frame.index(site[0],site[1],z)] = 2 } }
    // Exercise active Practical STOP with a genuine +1 prefix, not a V3
    // ambiguity fixture. Numeric values here are unit fixtures, not ML evidence.
    frame.predictedCoverage = outcome == .continue ? 0.79 : 1.0
    let transitions = [StratigraphicTransition(from:"b",to:"c",coherentRevision:false,changedVoxels:0,
      coherentChangedComponents:0,coherentBoundaryComponents:0,majorContinuityChanges:0,boundaryP90M:0,boundaryMaxShiftCells:0)]
    var previous=frame; previous.stateID="b";previous.count=3;previous.sites=Array(sites.dropLast())
    let last=sites.last!
    for z in 0..<4 {previous.measured[previous.index(last[0],last[1],z)]=255}
    let decision:StratigraphicDecision
    if outcome == .undetermined {
      decision=StratigraphicHistory.advance(frame:frame,cptStateID:"c",previousPrefixID:nil,contextID:"unit-grid",implementationID:"unit-test",prior:nil).decision
    } else {
      decision=StratigraphicStop.evaluate(frame,previous:previous,recent:transitions,stateIndex:3)
    }
    XCTAssertEqual(decision.outcome,outcome)
    return .init(implementationID:"unit-test",contextID:"unit-grid",cptStateID:"unit-cpt-state",frame:frame,stateIndex:3,recent:transitions,decision:decision)
  }

  func testThreeStatusesSaveReopenThroughProductionProjectStorage() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("projects.json")
    defer { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) }
    let statuses: [(StratigraphicDecision.Outcome,StratigraphicCharacterization.ObservedStatus)] = [(.stop,.sufficient),(.continue,.insufficient),(.undetermined,.undetermined)]
    for (outcome,status) in statuses {
      let e = evidence(outcome)
      var recommendation = CPTRecommendationResult()
      recommendation.stratigraphicDecision = e.decision
      recommendation.stratigraphicEvidence = e
      recommendation.isSufficient = StratigraphicStop.dispatch(e.decision) { 1 }.stop
      var project = Project(name:"Characterization storage unit fixture",latestRecommendation:recommendation)
      project.stratigraphicEvidence = e
      let before = StratigraphicCharacterization.evaluate(e.decision)
      XCTAssertEqual(before.observedCharacterizationStatus,status)
      LocalProjectStorage(fileURL:url).saveProjects([project])
      let reopened = try XCTUnwrap(LocalProjectStorage(fileURL:url).loadProjects().first)
      let savedResult = try XCTUnwrap(reopened.latestRecommendation)
      XCTAssertEqual(savedResult.stratigraphicDecision,e.decision)
      XCTAssertEqual(savedResult.stratigraphicEvidence,e)
      XCTAssertEqual(StratigraphicCharacterization.evaluate(savedResult.stratigraphicDecision),before)
      XCTAssertEqual(reopened.stratigraphicEvidence,e)
      XCTAssertEqual(savedResult.isSufficient,recommendation.isSufficient)
      XCTAssertEqual(before.unobservedGeologyRisk,.notQuantified)
    }
  }

  func testCoverageAndReasonsInvalidateResultEquality() {
    let original=CPTRecommendationResult(predictedCoverage:0.31,hasRecommendation:false,recommendationSource:"DQN_NO_LEGAL_CANDIDATES",assessmentSource:"CONTINUE: CURRENT")
    var changed=original;changed.predictedCoverage=0.81
    XCTAssertNotEqual(changed,original)
    XCTAssertEqual(Set([original,changed]).count,2)
    changed=original;changed.assessmentSource="CONTINUE: DIFFERENT_CURRENT_REASON"
    XCTAssertNotEqual(changed,original)
    changed=original;changed.recommendationSource="DQN_INFERENCE_UNAVAILABLE"
    XCTAssertNotEqual(changed,original)
  }
  func testDisplayedUncertaintyUsesCurrentCoverageWithoutRiskInterpretation() {
    XCTAssertEqual(CPTRecommendationResult(predictedCoverage:0.31).predictionUncertaintyPercent,69)
    XCTAssertEqual(CPTRecommendationResult(predictedCoverage:0.80).predictionUncertaintyPercent,20)
    XCTAssertEqual(CPTRecommendationResult(predictedCoverage:1.0).predictionUncertaintyPercent,1)
  }
  func testContinueWithoutLegalRecommendationIsNotStop() {
    var r=CPTRecommendationResult(predictedCoverage:0.31,isSufficient:false,hasRecommendation:false,recommendationSource:"DQN_NO_LEGAL_CANDIDATES")
    XCTAssertFalse(r.isSufficient)
    XCTAssertTrue(r.recommendationAvailabilityExplanation.contains("boundary and separation"))
    r.recommendationSource="DQN_INFERENCE_UNAVAILABLE"
    XCTAssertTrue(r.recommendationAvailabilityExplanation.contains("inference is unavailable"))
    XCTAssertFalse(r.recommendationAvailabilityExplanation.contains("boundary and separation"))
  }

  func testCandidateSpacingMetadataPersistsAndInvalidatesEquality() throws {
    let spacing=CPTCandidateSpacing(normalMinimumM:40,physicalMinimumM:10,attemptedMinimumM:[40,32],legalCandidateCounts:[0,3],usedMinimumM:32)
    var result=CPTRecommendationResult();result.candidateSpacing=spacing
    let saved=try JSONDecoder().decode(CPTRecommendationResult.self,from:JSONEncoder().encode(result))
    XCTAssertEqual(saved.candidateSpacing,spacing)
    var changed=result;changed.candidateSpacing?.usedMinimumM=30
    XCTAssertNotEqual(result,changed)
    let evidence=CPTRecommendationEvidence(id:UUID(),stateBefore:"prefix",recommendedLatitude:0,recommendedLongitude:0,model:"DQN V4.6-A Core ML",distancePolicy:"sufficiencyV32SiteDiagonal",candidateSpacing:spacing)
    let reopened=try JSONDecoder().decode(CPTRecommendationEvidence.self,from:JSONEncoder().encode(evidence))
    XCTAssertEqual(evidence,reopened)
    var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(result)) as! [String:Any]
    legacy.removeValue(forKey:"candidateSpacing")
    XCTAssertNil(try JSONDecoder().decode(CPTRecommendationResult.self,from:JSONSerialization.data(withJSONObject:legacy)).candidateSpacing)
  }

  func testPerfectNumericPredictionDoesNotImplyCharacterization() {
    let result = CPTRecommendationResult(rmse:0,confidenceLevel:99,predictedCoverage:1,sufficiencyProbability:1,isSufficient:true)
    XCTAssertEqual(StratigraphicCharacterization.evaluate(result.stratigraphicDecision).observedCharacterizationStatus,.undetermined)
  }

  func testStaleInformationNeverControlsStopOrDQNDispatch() {
    let decision = evidence(.stop).decision
    let informational = StratigraphicCharacterization.evaluate(decision,evaluatedCPTCount:4,currentCPTCount:5)
    XCTAssertEqual(informational.observedCharacterizationStatus,.undetermined)
    var calls = 0
    let stopped = StratigraphicStop.dispatch(decision) { calls += 1; return 1 }
    XCTAssertTrue(stopped.stop); XCTAssertEqual(calls,0)
    let continuing = StratigraphicStop.dispatch(evidence(.continue).decision) { calls += 1; return 1 }
    XCTAssertFalse(continuing.stop); XCTAssertEqual(calls,1)
  }

  func testMissingQualifyingHistoryStaysUndetermined() {
    var decision = evidence(.continue).decision
    decision.reasons.append("TWO_DISTINCT_CONSECUTIVE_GENUINE_STATE_IDENTITIES_NOT_AVAILABLE")
    XCTAssertEqual(StratigraphicCharacterization.evaluate(decision).observedCharacterizationStatus,.undetermined)
  }

  func testInvalidEvidenceCannotDisplaySuccessReason() {
    var decision = evidence(.stop).decision
    decision.evidenceValid = false
    let invalid = StratigraphicCharacterization.evaluate(decision)
    XCTAssertEqual(invalid.observedCharacterizationStatus,.undetermined)
    XCTAssertEqual(invalid.reasonCodes,["CHARACTERIZATION_EVIDENCE_UNAVAILABLE"])
    decision.evidenceValid = true; decision.metrics["invalid"] = .nan
    XCTAssertEqual(StratigraphicCharacterization.evaluate(decision).reasonCodes,["CHARACTERIZATION_EVIDENCE_UNAVAILABLE"])
  }

  func testProductionSwiftUICharacterizationPresentation() throws {
    for outcome in [StratigraphicDecision.Outcome.stop,.continue,.undetermined] {
      let assessment = StratigraphicCharacterization.evaluate(evidence(outcome).decision)
      let content = StratigraphicCharacterizationView(assessment:assessment)
        .padding(20).frame(width:600).background(Color(.systemGroupedBackground))
        .environment(\.colorScheme,.light)
      let renderer = ImageRenderer(content:content); renderer.scale = 2
      let rendered = try XCTUnwrap(renderer.uiImage)
      XCTAssertGreaterThan(rendered.size.height,150)
      let attachment = XCTAttachment(image:rendered)
      attachment.name = "characterization-\(assessment.observedCharacterizationStatus.rawValue)"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }
  func testDecisionAndStateChangesInvalidateRecommendationEquality() {
    var original=CPTRecommendationResult()
    original.stratigraphicDecision=evidence(.stop).decision
    original.stratigraphicEvidence=evidence(.stop)
    var changed=original
    changed.stratigraphicDecision=evidence(.undetermined).decision
    XCTAssertNotEqual(changed,original)
    XCTAssertEqual(Set([original,changed]).count,2)
    changed=original
    changed.stratigraphicEvidence?.frame.count=26
    XCTAssertNotEqual(changed,original)
    changed=original
    changed.stratigraphicEvidence?.implementationID="different-implementation"
    XCTAssertNotEqual(changed,original)
  }

  func testRecorded26CPTStopDispatchHistoryAndViewModelPresentation() throws {
    struct Snapshot: Decodable {
      let evidence:StratigraphicEvidence
      let recommendation:CPTRecommendationResult
      let cptCount:Int
    }
    let url=try XCTUnwrap(Bundle.module.url(forResource:"stop-sync-snapshot",withExtension:"json"))
    let data=try Data(contentsOf:url)
    guard let snapshot=try JSONDecoder().decode(Snapshot?.self,from:data) else {
      throw XCTSkip("Recorded-session regression requires CPT_STOP_SYNC_PROJECTS_FILE; no substitute session is generated")
    }
    let e=snapshot.evidence, saved=snapshot.recommendation
    XCTAssertEqual(snapshot.cptCount,26);XCTAssertEqual(e.frame.count,26)
    XCTAssertEqual(e.decision.contractID,StratigraphicStop.policyID)
    XCTAssertEqual(e.frame.stateID,e.decision.stateID)
    XCTAssertEqual(saved.stratigraphicDecision,e.decision)
    XCTAssertEqual(e.decision.outcome,.stop);XCTAssertTrue(e.decision.evidenceValid)
    XCTAssertTrue(saved.isSufficient);XCTAssertFalse(saved.hasRecommendation)
    XCTAssertTrue(saved.recommendationSource.contains("DQN not requested"))
    XCTAssertEqual(e.decision.reasons,["SHORT_ALTERNATIVE_SEQUENCES_SPATIALLY_WITNESSED"])
    XCTAssertEqual(e.decision.metrics["residual_fraction"]!,564.0/13408,accuracy:1e-12)
    // Replay the existing same-state history path, without inventing a predecessor
    // reconstruction, acquisition, probability, or source-model evidence.
    let repeated=StratigraphicHistory.advance(frame:e.frame,cptStateID:e.cptStateID,previousPrefixID:nil,
      contextID:e.contextID,implementationID:e.implementationID,prior:e)
    XCTAssertEqual(repeated,e)
    var dqnCalls=0
    let dispatch=StratigraphicStop.dispatch(repeated.decision){dqnCalls+=1;return 1}
    XCTAssertTrue(dispatch.stop);XCTAssertNil(dispatch.candidate);XCTAssertEqual(dqnCalls,0)
    let continuing=StratigraphicStop.dispatch(evidence(.continue).decision){dqnCalls+=1;return 1}
    XCTAssertFalse(continuing.stop);XCTAssertEqual(dqnCalls,1)

    // ViewModel presentation shell only: the classification and STOP above come
    // from the recorded project. These dummy entries supply UI count, not ML input.
    let vm=CPTRecommendationViewModel(project:Project(name:"Recorded STOP presentation test"))
    vm.cptPoints=(0..<snapshot.cptCount).map { _ in CPTPointEntry(type:.electrical,
      coordinate:.init(latitude:0,longitude:0),file:.init(name:"presentation-only")) }
    vm.hasUploadedCPTData=true;vm.recommendation=saved
    vm.presentInitialSheet()
    XCTAssertEqual(vm.activeSheet,.recommendedPoint)
    XCTAssertEqual(vm.targetRecommendationSheetDetent,CPTRecommendationViewModel.sufficientSheetDetent)
    XCTAssertNil(vm.recommendedCoordinateOnMap)
    vm.presentUploadSheet();XCTAssertFalse(vm.isUploadSheetPresented)
    vm.submitCPTUpload();XCTAssertEqual(vm.cptPoints.count,26);XCTAssertNotNil(vm.uploadValidationError)
    let assessment=StratigraphicCharacterization.evaluate(saved.stratigraphicDecision,
      evaluatedCPTCount:e.frame.count,currentCPTCount:26)
    XCTAssertEqual(assessment.observedCharacterizationStatus,.sufficient)
    XCTAssertFalse(assessment.explanation.contains("V1"))
    // A cached decision without its evaluated count must not claim current
    // characterization merely because the project still has 26 CPTs.
    XCTAssertEqual(StratigraphicCharacterization.evaluate(saved.stratigraphicDecision,
      evaluatedCPTCount:nil,currentCPTCount:26).observedCharacterizationStatus,.undetermined)
    XCTAssertEqual(StratigraphicCharacterization.evaluate(saved.stratigraphicDecision,
      evaluatedCPTCount:25,currentCPTCount:26).observedCharacterizationStatus,.undetermined)
    let roundTrip=try JSONDecoder().decode(CPTRecommendationResult.self,from:JSONEncoder().encode({
      var r=saved;r.stratigraphicEvidence=e;return r
    }()))
    XCTAssertEqual(roundTrip.stratigraphicEvidence,e)
    XCTAssertTrue(roundTrip.isSufficient);XCTAssertFalse(roundTrip.hasRecommendation)
    // Assertions above exercise the production ViewModel's sheet destination,
    // completed-state detent, map-marker binding and actual upload handlers.
    // No screenshot/gesture validation is claimed by this state regression test.
  }

}
