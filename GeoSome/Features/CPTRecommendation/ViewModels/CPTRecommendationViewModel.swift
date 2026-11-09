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

  // Upload Sheet State
  var selectedCPTType: CPTType = .electrical
  var uploadCoordinatesText: String = ""
  var uploadedCPTFile: CPTUploadedFile?

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
    hasUploadedCPTData ? recommendation.coordinate : nil
  }

  // MARK: - Intents

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
    if uploadCoordinatesText.isEmpty {
      uploadCoordinatesText = "-6.215432, 106.845321"
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
    let coordinate = Self.parseCoordinate(from: uploadCoordinatesText)
      ?? CLLocationCoordinate2D(latitude: -6.215432, longitude: 106.845321)
    let file = uploadedCPTFile ?? CPTUploadedFile(name: "CPTResultFile.csv", byteSize: 24 * 1024, rowCount: 52)
    let entry = CPTPointEntry(type: selectedCPTType, coordinate: coordinate, file: file)
    cptPoints.append(entry)

    hasUploadedCPTData = true
    recommendation = CPTRecommendationResult(
      coordinate: coordinate,
      rmse: 0.0064,
      confidenceLevel: 90,
      spotName: "Spot B",
      nearestCPTDistance: 16.2
    )

    isUploadSheetPresented = false
    isCPTListPresented = false
    selectedSheetDetent = Self.recommendationSheetDetent

    AccessibilityCaptionCenter.shared.announce("CPT data uploaded successfully. Recommended point generated.")
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
      isCPTListPresented = false
      selectedSheetDetent = Self.defaultSheetDetent
      AccessibilityCaptionCenter.shared.announce("Deleted CPT Point. No CPT points remaining.")
    } else {
      AccessibilityCaptionCenter.shared.announce("CPT Point deleted. \(cptPoints.count) remaining.")
    }
  }

  func resolveProject(with id: Project.ID?, from projectViewModel: ProjectViewModel?) {
    guard let id, let projectViewModel else { return }
    if let foundProject = projectViewModel.projects.first(where: { $0.id == id }) {
      updateProject(foundProject)
    }
  }

  func updateProject(_ newProject: Project) {
    project = newProject
    cameraPosition = .region(resolvedBoundaryRegion)
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
