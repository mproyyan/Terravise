import CoreGraphics
import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

enum ActiveCPTSheet: Identifiable, Equatable {
  case emptyState
  case uploadData
  case recommendedPoint
  case cptDataList

  var id: String {
    switch self {
    case .emptyState:
      "emptyState"
    case .uploadData:
      "uploadData"
    case .recommendedPoint:
      "recommendedPoint"
    case .cptDataList:
      "cptDataList"
    }
  }
}

@MainActor
@Observable
final class CPTRecommendationViewModel {
  static let defaultSamplePoints: [BoundaryPoint] = [
    BoundaryPoint(latitude: -6.2405, longitude: 106.8295),
    BoundaryPoint(latitude: -6.2402, longitude: 106.8336),
    BoundaryPoint(latitude: -6.2435, longitude: 106.8338),
    BoundaryPoint(latitude: -6.2430, longitude: 106.8292)
  ]

  static let collapsedSheetDetent: PresentationDetent = .height(68)
  static let defaultSheetDetent: PresentationDetent = .height(260)
  static let sufficientSheetDetent: PresentationDetent = .height(310)
  static let populatedSheetDetent: PresentationDetent = .height(420)
  static let cptDataListSheetDetent: PresentationDetent = .height(560)
  static let recommendationSheetDetent: PresentationDetent = .height(620)
  static let uploadSheetDetent: PresentationDetent = .height(640)

  var targetRecommendationSheetDetent: PresentationDetent {
    recommendation.isSufficient ? Self.sufficientSheetDetent : Self.recommendationSheetDetent
  }

  var project: Project
  var cameraPosition: MapCameraPosition
  var isSatelliteStyle: Bool
  var isSheetPresented: Bool
  var isUploadSheetPresented: Bool
  var isCPTListPresented: Bool
  var selectedSheetDetent: PresentationDetent

  // Recommendation & Uploaded Points State
  var hasUploadedCPTData: Bool = false
  var cptPoints: [CPTPointEntry] = []
  var recommendation: CPTRecommendationResult = .init()
  weak var projectViewModel: ProjectViewModel?

  // Upload Sheet State
  var selectedCPTType: CPTType = .electrical
  var uploadCoordinatesText: String = "" {
    didSet { if oldValue != uploadCoordinatesText { activeRecommendationAcceptance = nil } }
  }
  private var activeRecommendationAcceptance: UUID?
  var uploadValidationError: String?
  var uploadedCPTFile: CPTUploadedFile?
  var uploadParsedRows: [CPTRowData] = []

  init(
    project: Project? = nil,
    cameraPosition: MapCameraPosition? = nil,
    isSatelliteStyle: Bool = false
  ) {
    let resolvedProject = project ?? Project(
      name: "Project name",
      lastEdited: Date(),
      boundaryPoints: Self.defaultSamplePoints
    )
    self.project = resolvedProject
    self.cameraPosition = cameraPosition ?? .region(resolvedProject.boundaryRegion)
    self.isSatelliteStyle = isSatelliteStyle
    isSheetPresented = false
    isUploadSheetPresented = false
    isCPTListPresented = false
    selectedSheetDetent = Self.defaultSheetDetent
    syncStateFromProject(resolvedProject)
  }

  var activeSheet: ActiveCPTSheet? {
    guard isSheetPresented else { return nil }
    if isUploadSheetPresented {
      return .uploadData
    }
    if isCPTListPresented {
      return .cptDataList
    }
    return hasUploadedCPTData ? .recommendedPoint : .emptyState
  }

  var coordinates: [CLLocationCoordinate2D] {
    if project.boundaryPoints.isEmpty {
      return Self.defaultSamplePoints.map(\.coordinate)
    }
    return project.boundaryCoordinates
  }

  var resolvedBoundaryRegion: MKCoordinateRegion {
    if project.boundaryPoints.isEmpty {
      let sampleProject = Project(name: project.name, boundaryPoints: Self.defaultSamplePoints)
      return sampleProject.boundaryRegion
    }
    return project.boundaryRegion
  }

  var recommendedCoordinateOnMap: CLLocationCoordinate2D? {
    (hasUploadedCPTData && !recommendation.isSufficient && recommendation.hasRecommendation) ? recommendation.coordinate : nil
  }

  var pendingUploadCoordinate: CLLocationCoordinate2D? {
    guard isUploadSheetPresented else { return nil }
    guard let coordinate = Self.parseCoordinate(from: uploadCoordinatesText, referenceCoordinate: coordinates.first) else { return nil }
    guard isCoordinateInsideBoundary(coordinate) else { return nil }
    return coordinate
  }

  func isCoordinateInsideBoundary(_ coordinate: CLLocationCoordinate2D) -> Bool {
    guard coordinates.count >= 3 else { return false }
    let path = CGMutablePath()
    let firstPoint = MKMapPoint(coordinates[0])
    path.move(to: CGPoint(x: firstPoint.x, y: firstPoint.y))
    for pt in coordinates.dropFirst() {
      let mp = MKMapPoint(pt)
      path.addLine(to: CGPoint(x: mp.x, y: mp.y))
    }
    path.closeSubpath()

    let testPoint = MKMapPoint(coordinate)
    let pt = CGPoint(x: testPoint.x, y: testPoint.y)
    if path.contains(pt) {
      return true
    }
    let stroked = path.copy(strokingWithWidth: 20, lineCap: .round, lineJoin: .round, miterLimit: 10)
    return stroked.contains(pt)
  }

  // MARK: - Intents

  func handleMapTap(at coordinate: CLLocationCoordinate2D) {
    guard isUploadSheetPresented else { return }

    // A map selection is a manual action even if it lands on the same coordinate.
    activeRecommendationAcceptance = nil

    guard isCoordinateInsideBoundary(coordinate) else {
      uploadValidationError = "Lokasi berada di luar batas proyek. Pilih titik di dalam area."
      AccessibilityCaptionCenter.shared.announce(
        "Selected location is outside the project boundary. Please tap inside the boundary area."
      )
      return
    }

    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    uploadCoordinatesText = UTMCoordinateConverter.formatAsUTM(coordinate)
    uploadValidationError = nil
    AccessibilityCaptionCenter.shared.announce(
      "Coordinate updated to \(uploadCoordinatesText).",
      soundDescription: "Map tap"
    )
  }

  func presentInitialSheet() {
    isUploadSheetPresented = false
    isCPTListPresented = false
    isSheetPresented = true
    selectedSheetDetent = hasUploadedCPTData ? targetRecommendationSheetDetent : Self.defaultSheetDetent
  }

  func presentEmptyStateSheet() {
    presentInitialSheet()
  }

  func dismissSheet() {
    isUploadSheetPresented = false
    isCPTListPresented = false
    isSheetPresented = false
  }

  func presentUploadSheet() {
    activeRecommendationAcceptance = nil
    uploadedCPTFile = nil
    uploadParsedRows = []
    uploadValidationError = nil
    if hasUploadedCPTData, !recommendation.isSufficient, recommendation.hasRecommendation {
      uploadCoordinatesText = recommendation.formattedCoordinate
      if project.cptDistancePolicy == .sufficiencyV32SiteDiagonal,
         recommendation.recommendationSource == "DQN V4.6-A Core ML",
         let state = CPTSufficiencyHistory.stateID(projectID: project.id, gridPolicy: project.gridPolicy,
           distancePolicy: project.cptDistancePolicy, boundary: project.boundaryPoints, points: cptPoints) {
        if let existing = project.cptRecommendationEvidence.last(where: { $0.stateBefore == state && $0.acceptedCPTID == nil &&
          $0.model == recommendation.recommendationSource && $0.distancePolicy == project.cptDistancePolicy.rawValue &&
          $0.recommendedLatitude == recommendation.coordinate.latitude && $0.recommendedLongitude == recommendation.coordinate.longitude }) {
          activeRecommendationAcceptance = existing.id
        } else {
          let evidence = CPTRecommendationEvidence(id: UUID(), stateBefore: state,
            recommendedLatitude: recommendation.coordinate.latitude, recommendedLongitude: recommendation.coordinate.longitude,
            model: recommendation.recommendationSource, distancePolicy: project.cptDistancePolicy.rawValue,
            acceptedCPTID: nil, stateAfter: nil, coordinateMatches: nil, acceptedWithoutManualChange: nil)
          project.cptRecommendationEvidence.append(evidence)
          activeRecommendationAcceptance = evidence.id
        }
      }
    } else if uploadCoordinatesText.isEmpty {
      let center = resolvedBoundaryRegion.center
      uploadCoordinatesText = UTMCoordinateConverter.formatAsUTM(center)
    }
    isUploadSheetPresented = true
    isCPTListPresented = false
    isSheetPresented = true
    selectedSheetDetent = Self.uploadSheetDetent
  }

  func dismissUploadSheet() {
    activeRecommendationAcceptance = nil
    isUploadSheetPresented = false
    selectedSheetDetent = hasUploadedCPTData ? targetRecommendationSheetDetent : Self.defaultSheetDetent
  }

  func submitCPTUpload() {
    guard let file = uploadedCPTFile, !uploadParsedRows.isEmpty,
          file.rowCount == uploadParsedRows.count,
          selectedCPTType.requiredColumns.allSatisfy({ file.isColumnMatched($0) }) else {
      uploadValidationError = "Pilih file CSV CPT yang valid dengan kolom dan data yang lengkap."
      return
    }
    guard let parsedCoordinate = Self.parseCoordinate(from: uploadCoordinatesText, referenceCoordinate: coordinates.first) else {
      uploadValidationError = "Koordinat tidak valid. Masukkan format UTM (misal: 48S 702634 E, 9309747 N) atau Latitude, Longitude."
      return
    }
    let acceptedEvidence = project.cptRecommendationEvidence.first { $0.id == activeRecommendationAcceptance && $0.acceptedCPTID == nil }
    let coordinate = acceptedEvidence.map { CLLocationCoordinate2D(latitude: $0.recommendedLatitude, longitude: $0.recommendedLongitude) } ?? parsedCoordinate
    guard isCoordinateInsideBoundary(coordinate) else {
      uploadValidationError = "Koordinat berada di luar batas proyek. Pilih titik di dalam area."
      return
    }
    uploadValidationError = nil
    let rows = uploadParsedRows
    let entry = CPTPointEntry(
      type: selectedCPTType,
      coordinate: coordinate,
      file: file,
      rows: rows
    )
    let stateBefore = CPTSufficiencyHistory.stateID(projectID: project.id, gridPolicy: project.gridPolicy, distancePolicy: project.cptDistancePolicy,
      boundary: project.boundaryPoints, points: cptPoints)
    cptPoints.append(entry)
    let stateAfter = CPTSufficiencyHistory.stateID(projectID: project.id, gridPolicy: project.gridPolicy, distancePolicy: project.cptDistancePolicy,
      boundary: project.boundaryPoints, points: cptPoints)
    if cptPoints.count == 1, project.cptDistancePolicy == .sufficiencyV32SiteDiagonal,
       let stateBefore, let stateAfter {
      project.cptInitialObservation = .init(stateBefore: stateBefore, stateAfter: stateAfter,
        cptID: entry.id, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
    if let stateBefore, let stateAfter, let acceptedEvidence,
       let index = project.cptRecommendationEvidence.lastIndex(where: {
         $0.stateBefore == stateBefore && $0.acceptedCPTID == nil &&
           $0.id == acceptedEvidence.id
       }) {
      project.cptRecommendationEvidence[index].acceptedCPTID = entry.id
      project.cptRecommendationEvidence[index].stateAfter = stateAfter
      project.cptRecommendationEvidence[index].coordinateMatches =
        coordinate.latitude == project.cptRecommendationEvidence[index].recommendedLatitude &&
        coordinate.longitude == project.cptRecommendationEvidence[index].recommendedLongitude
      project.cptRecommendationEvidence[index].acceptedWithoutManualChange =
        acceptedEvidence.id == project.cptRecommendationEvidence[index].id
    }
    activeRecommendationAcceptance = nil

    let previousConsecutive = project.consecutiveSufficientCount
    var assessmentProject = project
    assessmentProject.cptPoints = cptPoints
    let result = CPTPipelineCoordinator.runPipeline(
      boundaryCoordinates: coordinates,
      cptPoints: cptPoints,
      previousConsecutiveSufficientCount: previousConsecutive,
      gridPolicy: project.gridPolicy,
      distancePolicy: project.cptDistancePolicy,
      assessmentProject: assessmentProject
    )

    hasUploadedCPTData = true
    recommendation = result
    persistCPTStateToProject()

    uploadedCPTFile = nil
    uploadParsedRows = []
    uploadCoordinatesText = ""

    isUploadSheetPresented = false
    isCPTListPresented = false
    selectedSheetDetent = result.isSufficient ? Self.sufficientSheetDetent : Self.recommendationSheetDetent

    if result.isSufficient {
      AccessibilityCaptionCenter.shared.announce(
        "CPT data uploaded. Sufficiency criteria reached — no more CPT points needed."
      )
    } else if result.hasRecommendation {
      AccessibilityCaptionCenter.shared.announce(
        "CPT data uploaded successfully. Next recommended point: \(result.spotName) at \(result.formattedCoordinate)."
      )
    } else {
      AccessibilityCaptionCenter.shared.announce("Rekomendasi DQN belum tersedia.")
    }
  }

  func openCPTDataList() {
    isUploadSheetPresented = false
    isCPTListPresented = true
    selectedSheetDetent = Self.cptDataListSheetDetent
  }

  func dismissCPTDataList() {
    isCPTListPresented = false
    selectedSheetDetent = hasUploadedCPTData ? targetRecommendationSheetDetent : Self.defaultSheetDetent
  }

  func deleteCPTPoint(id: UUID) {
    cptPoints.removeAll(where: { $0.id == id })
    if cptPoints.isEmpty {
      hasUploadedCPTData = false
      recommendation = CPTRecommendationResult()
      persistCPTStateToProject()
      isCPTListPresented = false
      selectedSheetDetent = Self.defaultSheetDetent
      AccessibilityCaptionCenter.shared.announce("Deleted CPT Point. No CPT points remaining.")
    } else {
      recommendation = CPTPipelineCoordinator.recomputeFromScratch(
        boundaryCoordinates: coordinates,
        cptPoints: cptPoints,
        gridPolicy: project.gridPolicy,
        distancePolicy: project.cptDistancePolicy,
        assessmentProject: project
      )
      persistCPTStateToProject()
      AccessibilityCaptionCenter.shared.announce("CPT Point deleted. \(cptPoints.count) remaining.")
    }
  }

  func resolveProject(with id: Project.ID?, from projectViewModel: ProjectViewModel?) {
    self.projectViewModel = projectViewModel
    guard let id, let projectViewModel else { return }
    if let foundProject = projectViewModel.projects.first(where: { $0.id == id }) {
      updateProject(foundProject)
    }
  }

  func updateProject(_ newProject: Project) {
    project = newProject
    cameraPosition = .region(resolvedBoundaryRegion)
    syncStateFromProject(newProject)
  }

  private func syncStateFromProject(_ sourceProject: Project) {
    cptPoints = sourceProject.cptPoints
    hasUploadedCPTData = !sourceProject.cptPoints.isEmpty
    // A historical recommendation can predate CPT edits or the review-only
    // state. Recompute from the actual saved CPT sequence before displaying it.
    if !sourceProject.cptPoints.isEmpty {
      recommendation = CPTPipelineCoordinator.recomputeFromScratch(
        boundaryCoordinates: coordinates,
        cptPoints: sourceProject.cptPoints,
        gridPolicy: sourceProject.gridPolicy,
        distancePolicy: sourceProject.cptDistancePolicy,
        assessmentProject: sourceProject
      )
    }
  }

  private func persistCPTStateToProject() {
    project.cptPoints = cptPoints
    project.latestRecommendation = hasUploadedCPTData ? recommendation : nil
    project.consecutiveSufficientCount = hasUploadedCPTData ? recommendation.consecutiveSufficientCount : 0
    project.sufficiencyObservations = CPTSufficiencyHistory.retainValidPrefixes(project.sufficiencyObservations,
      projectID: project.id, gridPolicy: project.gridPolicy, distancePolicy: project.cptDistancePolicy, boundary: project.boundaryPoints, points: cptPoints)
    if let state = CPTSufficiencyHistory.stateID(projectID: project.id, gridPolicy: project.gridPolicy, distancePolicy: project.cptDistancePolicy,
       boundary: project.boundaryPoints, points: cptPoints) {
      if recommendation.assessmentSource == "Sufficiency V3.2 experimental; STOP unavailable: DQN trajectory not verified" {
        CPTSufficiencyHistory.record(.init(stateID: state, cptCount: cptPoints.count,
          probability: recommendation.sufficiencyProbability), in: &project.sufficiencyObservations)
      }
      if project.cptDistancePolicy == .sufficiencyV32SiteDiagonal && recommendation.hasRecommendation && recommendation.recommendationSource == "DQN V4.6-A Core ML" &&
         !project.cptRecommendationEvidence.contains(where: { $0.stateBefore == state && $0.acceptedCPTID == nil &&
           $0.recommendedLatitude == recommendation.coordinate.latitude && $0.recommendedLongitude == recommendation.coordinate.longitude }) {
        project.cptRecommendationEvidence.append(.init(id: UUID(), stateBefore: state,
          recommendedLatitude: recommendation.coordinate.latitude, recommendedLongitude: recommendation.coordinate.longitude,
          model: "DQN V4.6-A Core ML", distancePolicy: project.cptDistancePolicy.rawValue,
          acceptedCPTID: nil, stateAfter: nil, coordinateMatches: nil, acceptedWithoutManualChange: nil))
      }
    }
    project.lastEdited = Date()
    projectViewModel?.updateProject(project)
  }

  func toggleMapLayer() {
    isSatelliteStyle.toggle()
  }

  func focusBoundary() {
    cameraPosition = .region(resolvedBoundaryRegion)
  }

  func editArea() {
    AccessibilityCaptionCenter.shared.announce("Edit Area selected.")
  }

  func viewAnalysis3D() {
    AccessibilityCaptionCenter.shared.announce("View Analysis 3D selected.")
  }

  func uploadCPTData() {
    presentUploadSheet()
  }

  func seeSupportingData() {
    AccessibilityCaptionCenter.shared.announce("See Supporting Data opened.")
  }

  // MARK: - Helpers

  static func parseCoordinate(
    from text: String,
    referenceCoordinate: CLLocationCoordinate2D? = nil
  ) -> CLLocationCoordinate2D? {
    UTMCoordinateConverter.parseCoordinate(from: text, referenceCoordinate: referenceCoordinate)
  }
}
