import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

enum ActiveCPTSheet: Identifiable {
  case emptyState
  case uploadData

  var id: String {
    switch self {
    case .emptyState:
      "emptyState"
    case .uploadData:
      "uploadData"
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
  static let uploadSheetDetent: PresentationDetent = .height(640)

  var project: Project
  var cameraPosition: MapCameraPosition
  var isSatelliteStyle: Bool
  var isSheetPresented: Bool
  var isUploadSheetPresented: Bool
  var selectedSheetDetent: PresentationDetent

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
    selectedSheetDetent = Self.defaultSheetDetent
  }

  var activeSheet: ActiveCPTSheet? {
    guard isSheetPresented else { return nil }
    return isUploadSheetPresented ? .uploadData : .emptyState
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

  // MARK: - Intents

  func presentEmptyStateSheet() {
    isUploadSheetPresented = false
    isSheetPresented = true
    selectedSheetDetent = Self.defaultSheetDetent
  }

  func dismissSheet() {
    isUploadSheetPresented = false
    isSheetPresented = false
  }

  func presentUploadSheet() {
    if uploadCoordinatesText.isEmpty {
      uploadCoordinatesText = "-6.215432, 106.845321"
    }
    isUploadSheetPresented = true
    isSheetPresented = true
    selectedSheetDetent = Self.uploadSheetDetent
  }

  func dismissUploadSheet() {
    isUploadSheetPresented = false
    selectedSheetDetent = Self.defaultSheetDetent
  }

  func submitCPTUpload() {
    AccessibilityCaptionCenter.shared.announce("CPT data uploaded successfully.")
    isUploadSheetPresented = false
    selectedSheetDetent = Self.defaultSheetDetent
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
}
