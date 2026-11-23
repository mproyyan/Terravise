import XCTest
import CoreLocation
@testable import Handler
@MainActor final class HandlerTests:XCTestCase {
 func make(_ policy:CPTDistancePolicy = .sufficiencyV32SiteDiagonal) -> (CPTRecommendationViewModel,ProjectViewModel,URL) {
  let p=Project(name:"fixture",boundaryPoints:CPTRecommendationViewModel.defaultSamplePoints,cptDistancePolicy:policy)
  let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("projects.json")
  let store=LocalProjectStorage(fileURL:url); let projects=ProjectViewModel(projects:[p],storage:store); let vm=CPTRecommendationViewModel(project:p); vm.projectViewModel=projects
  return (vm,projects,url)
 }
 func input(_ vm:CPTRecommendationViewModel) {
  vm.uploadParsedRows=[CPTRowData(depth:0,coneResistance:10,localFriction:100),CPTRowData(depth:11,coneResistance:12,localFriction:110)]
  vm.uploadedCPTFile=CPTUploadedFile(name:"test.csv",rowCount:2,matchedColumns:vm.selectedCPTType.requiredColumns)
 }
 func first(_ vm:CPTRecommendationViewModel) {
  vm.presentUploadSheet(); vm.uploadCoordinatesText="-6.2418, 106.8315"; input(vm); vm.submitCPTUpload()
  XCTAssertEqual(vm.cptPoints.count,1); XCTAssertNil(vm.uploadValidationError)
  vm.finalizeInitialCPTSetup()
 }
 func testInitialAndAcceptedAndStorage() throws {
  let (vm,projects,url)=make(); first(vm); let initial=try XCTUnwrap(vm.project.cptInitialObservation); XCTAssertEqual(initial.cptID,vm.cptPoints[0].id); XCTAssertEqual(initial.stateAfter,CPTSufficiencyHistory.stateID(projectID:vm.project.id,gridPolicy:vm.project.gridPolicy,distancePolicy:vm.project.cptDistancePolicy,boundary:vm.project.boundaryPoints,points:vm.cptPoints))
  vm.presentUploadSheet(); input(vm); vm.submitCPTUpload(); XCTAssertEqual(vm.cptPoints.count,2)
  let accepted=try XCTUnwrap(vm.project.cptRecommendationEvidence.first(where:{$0.acceptedCPTID == vm.cptPoints[1].id})); XCTAssertEqual(accepted.acceptedWithoutManualChange,true); XCTAssertEqual(accepted.coordinateMatches,true)
  let saved=try XCTUnwrap(LocalProjectStorage(fileURL:url).loadProjects().first); XCTAssertEqual(saved.cptPoints.count,2); XCTAssertEqual(saved.cptRecommendationEvidence.first(where:{$0.id==accepted.id})?.acceptedCPTID,accepted.acceptedCPTID); XCTAssertEqual(projects.projects.first?.cptPoints.count,2)
 }
 func testManualAndCoordinateEdit() {
  let (vm,_,_)=make(); first(vm); vm.presentUploadSheet(); vm.uploadCoordinatesText="-6.2419, 106.8316"; input(vm); vm.submitCPTUpload()
  XCTAssertEqual(vm.cptPoints.count,2); XCTAssertFalse(vm.project.cptRecommendationEvidence.contains(where:{$0.acceptedCPTID==vm.cptPoints[1].id && $0.acceptedWithoutManualChange==true}))
 }
 func testMapTapCancelsAcceptance() {
  let (vm,_,_)=make(); first(vm); vm.presentUploadSheet(); vm.handleMapTap(at:CLLocationCoordinate2D(latitude:-6.2419,longitude:106.8316)); input(vm); vm.submitCPTUpload()
  XCTAssertEqual(vm.cptPoints.count,2); XCTAssertFalse(vm.project.cptRecommendationEvidence.contains(where:{$0.acceptedCPTID==vm.cptPoints[1].id && $0.acceptedWithoutManualChange==true}))
 }
 func testDuplicatePresentAndLegacy() {
  let (vm,_,_)=make(); first(vm); vm.presentUploadSheet(); let count=vm.project.cptRecommendationEvidence.count; vm.dismissUploadSheet(); vm.presentUploadSheet(); XCTAssertEqual(vm.project.cptRecommendationEvidence.count,count)
  let (legacy,_,_)=make(.legacyCellDiagonal); first(legacy); legacy.presentUploadSheet(); input(legacy); legacy.submitCPTUpload(); XCTAssertNil(legacy.project.cptInitialObservation); XCTAssertTrue(legacy.project.cptRecommendationEvidence.isEmpty)
 }
 func testChangedProfileInvalidatesSavedHistory() {
  let (vm,_,_)=make(); first(vm); vm.presentUploadSheet(); input(vm); vm.submitCPTUpload()
  XCTAssertEqual(vm.project.sufficiencyObservations.count,2)
  let oldStates=Set(vm.project.sufficiencyObservations.map(\.stateID))
  vm.cptPoints[0].rows[0].coneResistance=99
  vm.deleteCPTPoint(id:vm.cptPoints[1].id)
  XCTAssertTrue(vm.project.sufficiencyObservations.allSatisfy { !oldStates.contains($0.stateID) })
 }
 func testDeletionInvalidatesHistory() {
  let (vm,_,_)=make(); first(vm); vm.presentUploadSheet(); input(vm); vm.submitCPTUpload(); XCTAssertEqual(vm.cptPoints.count,2)
  let last=vm.cptPoints[1].id; vm.deleteCPTPoint(id:last); XCTAssertEqual(vm.cptPoints.count,1); XCTAssertTrue(vm.project.sufficiencyObservations.allSatisfy{$0.cptCount<=1})
 }
}
