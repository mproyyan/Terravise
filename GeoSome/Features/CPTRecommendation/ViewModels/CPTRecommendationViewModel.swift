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
  static let populatedSheetDetent: PresentationDetent = .height(420)
  static let cptDataListSheetDetent: PresentationDetent = .height(560)
  static let recommendationSheetDetent: PresentationDetent = .height(620)
  static let uploadSheetDetent: PresentationDetent = .height(640)

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
  var uploadCoordinatesText: String = ""
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
    (hasUploadedCPTData && !recommendation.isSufficient) ? recommendation.coordinate : nil
  }

  var pendingUploadCoordinate: CLLocationCoordinate2D? {
    guard isUploadSheetPresented else { return nil }
    guard let coordinate = Self.parseCoordinate(from: uploadCoordinatesText) else { return nil }
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

    guard isCoordinateInsideBoundary(coordinate) else {
      AccessibilityCaptionCenter.shared.announce(
        "Selected location is outside the project boundary. Please tap inside the boundary area."
      )
      return
    }

    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    uploadCoordinatesText = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    AccessibilityCaptionCenter.shared.announce(
      "Coordinate updated to \(uploadCoordinatesText).",
      soundDescription: "Map tap"
    )
  }

  func presentInitialSheet() {
    isUploadSheetPresented = false
    isCPTListPresented = false
    isSheetPresented = true
    selectedSheetDetent = hasUploadedCPTData ? Self.recommendationSheetDetent : Self.defaultSheetDetent
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
    uploadedCPTFile = nil
    uploadParsedRows = []
    if hasUploadedCPTData, !recommendation.isSufficient {
      uploadCoordinatesText = recommendation.formattedCoordinate
    } else if uploadCoordinatesText.isEmpty {
      let center = resolvedBoundaryRegion.center
      uploadCoordinatesText = String(format: "%.6f, %.6f", center.latitude, center.longitude)
    }
    isUploadSheetPresented = true
    isCPTListPresented = false
    isSheetPresented = true
    selectedSheetDetent = Self.uploadSheetDetent
  }

  func dismissUploadSheet() {
    isUploadSheetPresented = false
    selectedSheetDetent = hasUploadedCPTData ? Self.recommendationSheetDetent : Self.defaultSheetDetent
  }

  func submitCPTUpload() {
    let fallbackCoord = (hasUploadedCPTData && !recommendation.isSufficient)
      ? recommendation.coordinate
      : resolvedBoundaryRegion.center
    let coordinate = Self.parseCoordinate(from: uploadCoordinatesText) ?? fallbackCoord
    let rows = uploadParsedRows.isEmpty ? CPTRowData.sampleRows : uploadParsedRows
    let file = uploadedCPTFile ?? CPTUploadedFile(
      name: "CPTResultFile.csv",
      byteSize: 24 * 1024,
      rowCount: rows.count,
      matchedColumns: selectedCPTType.requiredColumns
    )
    let entry = CPTPointEntry(
      type: selectedCPTType,
      coordinate: coordinate,
      file: file,
      rows: rows
    )
    cptPoints.append(entry)

    let previousConsecutive = project.consecutiveSufficientCount
    let result = CPTPipelineCoordinator.runPipeline(
      boundaryCoordinates: coordinates,
      cptPoints: cptPoints,
      previousConsecutiveSufficientCount: previousConsecutive
    )

    hasUploadedCPTData = true
    recommendation = result
    persistCPTStateToProject()

    uploadedCPTFile = nil
    uploadParsedRows = []
    uploadCoordinatesText = ""

    isUploadSheetPresented = false
    isCPTListPresented = false
    selectedSheetDetent = Self.recommendationSheetDetent

    if result.isSufficient {
      AccessibilityCaptionCenter.shared.announce(
        "CPT data uploaded. Sufficiency criteria reached — no more CPT points needed."
      )
    } else {
      AccessibilityCaptionCenter.shared.announce(
        "CPT data uploaded successfully. Next recommended point: \(result.spotName) at \(result.formattedCoordinate)."
      )
    }
  }

  func openCPTDataList() {
    isUploadSheetPresented = false
    isCPTListPresented = true
    selectedSheetDetent = Self.cptDataListSheetDetent
  }

  func dismissCPTDataList() {
    isCPTListPresented = false
    selectedSheetDetent = hasUploadedCPTData ? Self.recommendationSheetDetent : Self.defaultSheetDetent
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
        cptPoints: cptPoints
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
    if let savedRec = sourceProject.latestRecommendation {
      recommendation = savedRec
    } else if !sourceProject.cptPoints.isEmpty {
      recommendation = CPTPipelineCoordinator.recomputeFromScratch(
        boundaryCoordinates: coordinates,
        cptPoints: sourceProject.cptPoints
      )
    }
  }

  private func persistCPTStateToProject() {
    project.cptPoints = cptPoints
    project.latestRecommendation = hasUploadedCPTData ? recommendation : nil
    project.consecutiveSufficientCount = hasUploadedCPTData ? recommendation.consecutiveSufficientCount : 0
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

  static func parseCoordinate(from text: String) -> CLLocationCoordinate2D? {
    let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard parts.count == 2,
          let lat = Double(parts[0]),
          let lon = Double(parts[1]),
          (-90.0 ... 90.0).contains(lat),
          (-180.0 ... 180.0).contains(lon)
    else {
      return nil
    }
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }
}
