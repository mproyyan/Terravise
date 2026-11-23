import XCTest
import SwiftUI
import UIKit
import Vision
@testable import Handler

@MainActor final class SketchUIRegressionTests: XCTestCase {
  func render(_ result: CPTRecommendationResult, count: Int = 30) throws -> UIImage {
    let renderer = ImageRenderer(content: RecoveredSketchContent(recommendation: result, cptPointsCount: count)
      .frame(width: result.hasRecommendation && result.stratigraphicDecision?.outcome != .stop ? 580 : 445, height: 1800).background(Color(.systemGroupedBackground)).environment(\.colorScheme, .light))
    renderer.scale = 2
    return try XCTUnwrap(renderer.uiImage)
  }
  func text(_ image: UIImage) throws -> String {
    let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
  }
  func decision(_ outcome: StratigraphicDecision.Outcome = .continue, valid: Bool = true, contract: String = StratigraphicStop.policyID) -> StratigraphicDecision {
    .init(outcome: outcome, reasons: [], stateID: "ui-fixture", metrics: [:], evidenceValid: valid, contractID: contract)
  }
  func result(_ outcome: StratigraphicDecision.Outcome = .continue, recommendation: Bool = false) -> CPTRecommendationResult {
    var result = CPTRecommendationResult(isSufficient: outcome == .stop, hasRecommendation: recommendation)
    result.stratigraphicDecision = decision(outcome)
    return result
  }
  func testStopUsesCompactSketchCardAndActualCount() throws {
    let image = try render(result(.stop), count: 31)
    let found = try text(image)
    XCTAssertGreaterThan(found.count, 100)
    for expected in ["Recommended Point", "CPT coverage is sufficient", "Current CPT data meets the assessment requirements.", "Upload CPT Data", "31 entered"] {
      XCTAssertTrue(found.contains(expected), found)
    }
    for old in ["Sufficiency Reached", "No More CPT", "Stopping criterion", "0.95", "Upload Additional", "Why this point", "Current Ground Certainty"] {
      XCTAssertFalse(found.contains(old), found)
    }
    let attachment = XCTAttachment(image: image); attachment.name = "Sketch STOP content — UI fixture"; attachment.lifetime = .keepAlways; add(attachment)
  }
  func testContinueWithRecommendationKeepsRecommendedContent() throws {
    let image = try render(result(.continue, recommendation: true))
    let attachment = XCTAttachment(image: image); attachment.name = "DQN content — UI fixture"; attachment.lifetime = .keepAlways; add(attachment)
    let found = try text(image)
    XCTAssertTrue(found.contains("Recommended Point"), found)
    XCTAssertTrue(found.contains("Run a CPT at this point"), found)
    XCTAssertTrue(found.contains("Current Ground Certainty"), found)
    XCTAssertTrue(found.contains("Why this point?"), found)
    XCTAssertFalse(found.contains("coverage is sufficient"), found)
  }
  func testNoRecommendationNeverShowsFalseCompletionEvenAtHighCount() throws {
    let found = try text(render(result(), count: 999))
    for forbidden in ["sufficient", "Complete", "Covered", "CONTINUE", "Recommended Point"] {
      XCTAssertFalse(found.localizedCaseInsensitiveContains(forbidden), found)
    }
    XCTAssertTrue(found.contains("Upload CPT Data"), found)
    XCTAssertTrue(found.contains("999 entered"), found)
  }
  func testLegacySufficiencyAndInvalidStopEvidenceCannotShowStop() throws {
    var value = CPTRecommendationResult(isSufficient: true, hasRecommendation: false)
    for decision in [nil, self.decision(.continue), self.decision(.stop, valid: false), self.decision(.stop, contract: "legacy")] as [StratigraphicDecision?] {
      value.stratigraphicDecision = decision
      let found = try text(render(value))
      XCTAssertFalse(found.contains("coverage is sufficient"), found)
      XCTAssertFalse(found.contains("Complete"), found)
    }
  }
  func testEngineStopTakesPriorityOverRecommendationFlag() throws {
    let value = result(.stop, recommendation: true)
    let found = try text(render(value, count: 1))
    XCTAssertTrue(found.contains("coverage is sufficient"), found)
    XCTAssertFalse(found.contains("Run a CPT"), found)
    XCTAssertTrue(found.contains("1 entered"), found)
    var calls = 0
    let dispatch = StratigraphicStop.dispatch(try XCTUnwrap(value.stratigraphicDecision)) { calls += 1; return 1 }
    XCTAssertTrue(dispatch.stop); XCTAssertNil(dispatch.candidate); XCTAssertEqual(calls, 0)
  }
  func testStopNativeDetentBindingPreservesUploadAndListRoutes() throws {
    let vm = CPTRecommendationViewModel(project: Project(name: "Native binding", boundaryPoints: CPTRecommendationViewModel.defaultSamplePoints))
    vm.recommendation = result(.stop)
    vm.hasUploadedCPTData = true
    vm.isInitialSetupPresented = false
    vm.selectedSheetDetent = CPTRecommendationViewModel.sufficientSheetDetent
    let probe = RecommendedBindingProbe(viewModel: vm)
    XCTAssertEqual(probe.activeSheetDetentBinding.wrappedValue, CPTRecommendedPointSheetView.stopSheetDetent)
    probe.activeSheetDetentBinding.wrappedValue = .large
    XCTAssertEqual(vm.selectedSheetDetent, .large)
    probe.activeSheetDetentBinding.wrappedValue = CPTRecommendedPointSheetView.stopSheetDetent
    XCTAssertEqual(vm.selectedSheetDetent, CPTRecommendationViewModel.sufficientSheetDetent)
    vm.uploadCPTData()
    XCTAssertEqual(probe.activeSheetDetentBinding.wrappedValue, CPTRecommendationViewModel.uploadSheetDetent)
    vm.dismissUploadSheet()
    XCTAssertEqual(probe.activeSheetDetentBinding.wrappedValue, CPTRecommendedPointSheetView.stopSheetDetent)
    vm.openCPTDataList()
    XCTAssertEqual(probe.activeSheetDetentBinding.wrappedValue, CPTRecommendationViewModel.cptDataListSheetDetent)
    vm.dismissCPTDataList()
    vm.recommendation = result(.continue)
    XCTAssertEqual(probe.activeSheetDetentBinding.wrappedValue, CPTRecommendationViewModel.sufficientSheetDetent)
  }
  func testManualUploadAfterStopActuallyAddsCPT() {
    let vm = CPTRecommendationViewModel(project: Project(name: "Upload after STOP", boundaryPoints: CPTRecommendationViewModel.defaultSamplePoints))
    vm.recommendation = result(.stop)
    vm.hasUploadedCPTData = true
    vm.isInitialSetupPresented = false
    vm.uploadCPTData()
    vm.uploadCoordinatesText = "-6.2418, 106.8315"
    vm.uploadParsedRows = [CPTRowData(depth: 0, coneResistance: 10, localFriction: 100), CPTRowData(depth: 11, coneResistance: 12, localFriction: 110)]
    vm.uploadedCPTFile = CPTUploadedFile(name: "existing-test.csv", rowCount: 2, matchedColumns: vm.selectedCPTType.requiredColumns)
    let before = vm.cptPoints.count
    vm.submitCPTUpload()
    XCTAssertNil(vm.uploadValidationError)
    XCTAssertEqual(vm.cptPoints.count, before + 1)
    XCTAssertFalse(vm.isUploadSheetPresented)
  }
  func testStopUploadAndCPTListNavigation() throws {
    let vm = CPTRecommendationViewModel(project: Project(name: "UI routing", boundaryPoints: CPTRecommendationViewModel.defaultSamplePoints))
    vm.recommendation = result(.stop)
    vm.hasUploadedCPTData = true
    let count = vm.cptPoints.count
    vm.uploadCPTData()
    XCTAssertTrue(vm.isUploadSheetPresented)
    vm.dismissUploadSheet()
    vm.openCPTDataList()
    XCTAssertTrue(vm.isCPTListPresented)
    XCTAssertFalse(vm.isUploadSheetPresented)
    XCTAssertEqual(vm.cptPoints.count, count)
    vm.dismissCPTDataList()
    XCTAssertFalse(vm.isCPTListPresented)
    XCTAssertEqual(vm.selectedSheetDetent, vm.targetRecommendationSheetDetent)
  }
}
