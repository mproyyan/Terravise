import XCTest
@testable import BearingPresentation

@MainActor final class LifecycleTests: XCTestCase {
  func testNewEvaluationReplacesOldPercentWithOneDecimal() {
    let state = BearingSummaryProbe()
    state.bearingRuleEvaluation = .candidateDetected(ProbeOutput())
    state.qcfsResult = .coreML(ProbeVolume(id: "first", meanRiskPercent: 15, highRiskAreaPercent: 11.3))
    state.updateBearingSummaryMetrics()
    XCTAssertEqual(state.displayedUncertainty, "15.0%")
    XCTAssertEqual(state.highUncertaintyAreaPercentText, "11.3%")
    // Different snapshot outcome, independent of CPT count/history.
    state.qcfsResult = .coreML(ProbeVolume(id: "second", meanRiskPercent: 37.46, highRiskAreaPercent: 21.8))
    state.updateBearingSummaryMetrics()
    XCTAssertEqual(state.displayedUncertainty, "37.5%")
    XCTAssertEqual(state.highUncertaintyAreaPercentText, "21.8%")
    XCTAssertEqual(state.shallowestBearingDepthText, "7.3 m")
    XCTAssertEqual(state.deepestBearingDepthText, "17.5 m")
    XCTAssertEqual(state.variationBearingDepthText, "10.2 m")
    XCTAssertFalse(state.displayedUncertainty?.contains("±") ?? true)
  }
  func testFailureAfterSuccessClearsTheOldValue() {
    let state = BearingSummaryProbe()
    state.bearingRuleEvaluation = .candidateDetected(ProbeOutput())
    state.qcfsResult = .coreML(ProbeVolume(id: "valid", meanRiskPercent: 15, highRiskAreaPercent: 11.3))
    state.updateBearingSummaryMetrics()
    XCTAssertEqual(state.displayedUncertainty, "15.0%")
    state.qcfsResult = .coreML(ProbeVolume(id: "failed", meanRiskPercent: 15, highRiskAreaPercent: 11.3, fails: true))
    state.updateBearingSummaryMetrics()
    XCTAssertNil(state.displayedUncertainty)
    XCTAssertEqual(state.relativeUncertaintyText, "—")
    XCTAssertEqual(state.highUncertaintyAreaPercentText, "—")
    XCTAssertFalse(state.bearingUncertaintyExperimentalInferenceReady)
  }
  func testMissingOutputOrFilterDoesNotExposeStaleCachedText() {
    let state = BearingSummaryProbe()
    state.relativeUncertaintyText = "15.0%"
    state.bearingUncertaintyExperimentalInferenceReady = true
    state.bearingRuleEvaluation = .unavailable
    state.updateBearingSummaryMetrics()
    XCTAssertNil(state.displayedUncertainty)
    state.bearingRuleEvaluation = .candidateDetected(ProbeOutput())
    state.qcfsResult = nil
    state.updateBearingSummaryMetrics()
    XCTAssertNil(state.displayedUncertainty)
    state.qcfsResult = .coreML(ProbeVolume(id: "invalid-filter", meanRiskPercent: 15, highRiskAreaPercent: 11.3))
    state.bearingIcFilterActive = false
    state.updateBearingSummaryMetrics()
    XCTAssertNil(state.displayedUncertainty)
  }
}
