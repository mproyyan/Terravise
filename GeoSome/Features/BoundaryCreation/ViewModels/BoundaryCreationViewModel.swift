import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

@MainActor
@Observable
final class BoundaryCreationViewModel {
  static let collapsedSheetDetent: PresentationDetent = .height(68)
  static let defaultSheetDetent: PresentationDetent = .height(260)
  static let editSheetDetent: PresentationDetent = .height(370)
  static let populatedSheetDetent: PresentationDetent = .height(420)

  var projectName: String
  var cameraPosition: MapCameraPosition
  var isSatelliteStyle: Bool
  var activeSheet: SheetDestination?
  var selectedSheetDetent: PresentationDetent
  var isAddCoordinateSheetPresented: Bool
  var isDiscardConfirmationPresented: Bool
  var isInvalidCoordinateAlertPresented: Bool
  var editingPoint: BoundaryPoint?
  var editLatitudeText: String
  var editLongitudeText: String
  var isDeletePointAlertPresented: Bool
  var isEditDiscardConfirmationPresented: Bool
  var isEditInvalidCoordinateAlertPresented: Bool
  var coordinateInputText: String
  var isTooltipVisible: Bool

  private struct EditorSnapshot: Equatable {
    var projectName: String
    var points: [BoundaryPoint]
  }

  private(set) var points: [BoundaryPoint]
  private var editingProject: Project?
  private var undoStack: [EditorSnapshot] = []
  private var redoStack: [EditorSnapshot] = []
  private var isEditingNameSession = false
  private var hasRecordedNameEditInSession = false

  var canUndo: Bool {
    !undoStack.isEmpty
  }

  var canRedo: Bool {
    !redoStack.isEmpty
  }

  var canCreateProject: Bool {
    points.count >= 3
  }

  var boundaryPointsSummaryText: String {
    "\(points.count) \(points.count == 1 ? "point" : "points")"
  }

  var areaSquareMeters: Double {
    guard points.count >= 3 else { return 0 }

    let mapPoints = points.map { MKMapPoint($0.coordinate) }
    var shoelaceSum = 0.0
    for index in mapPoints.indices {
      let current = mapPoints[index]
      let next = mapPoints[(index + 1) % mapPoints.count]
      shoelaceSum += (current.x * next.y) - (next.x * current.y)
    }

    let areaInMapPoints = abs(shoelaceSum) * 0.5
    let averageLatitude = points.reduce(0.0) { $0 + $1.latitude } / Double(points.count)
    let metersPerMapPoint = MKMetersPerMapPointAtLatitude(averageLatitude)
    return areaInMapPoints * metersPerMapPoint * metersPerMapPoint
  }

  var areaSquareMetersText: String {
    let formatted = areaSquareMeters.formatted(
      .number.precision(.fractionLength(0 ... 1))
    )
    return "\(formatted) m²"
  }

  var areaHectaresText: String {
    let hectares = areaSquareMeters / 10000.0
    let formatted = hectares.formatted(
      .number.precision(.fractionLength(0 ... 2))
    )
    return "\(formatted) ha"
  }

  var hasUnsavedCoordinateInput: Bool {
    !coordinateInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var canSubmitCoordinate: Bool {
    hasUnsavedCoordinateInput
  }

  var hasUnsavedEditCoordinateChanges: Bool {
    guard let editingPoint else { return false }
    let trimmedLat = editLatitudeText.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedLon = editLongitudeText.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedLat != editingPoint.formattedLatitude || trimmedLon != editingPoint.formattedLongitude
  }

  var canSubmitEditedCoordinate: Bool {
    !editLatitudeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !editLongitudeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  init(
    projectName: String = "Project name",
    cameraPosition: MapCameraPosition? = nil,
    isSatelliteStyle: Bool = false,
    activeSheet: SheetDestination? = nil,
    selectedSheetDetent: PresentationDetent = .height(260),
    isAddCoordinateSheetPresented: Bool = false,
    isDiscardConfirmationPresented: Bool = false,
    isInvalidCoordinateAlertPresented: Bool = false,
    editingPoint: BoundaryPoint? = nil,
    editLatitudeText: String = "",
    editLongitudeText: String = "",
    isDeletePointAlertPresented: Bool = false,
    isEditDiscardConfirmationPresented: Bool = false,
    isEditInvalidCoordinateAlertPresented: Bool = false,
    coordinateInputText: String = "",
    isTooltipVisible: Bool = false,
    points: [BoundaryPoint] = []
  ) {
    self.projectName = projectName
    self.cameraPosition = cameraPosition ?? .region(BoundaryMapConfiguration.defaultRegion)
    self.isSatelliteStyle = isSatelliteStyle
    self.activeSheet = activeSheet
    self.selectedSheetDetent = selectedSheetDetent
    self.isAddCoordinateSheetPresented = isAddCoordinateSheetPresented
    self.isDiscardConfirmationPresented = isDiscardConfirmationPresented
    self.isInvalidCoordinateAlertPresented = isInvalidCoordinateAlertPresented
    self.editingPoint = editingPoint
    self.editLatitudeText = editLatitudeText
    self.editLongitudeText = editLongitudeText
    self.isDeletePointAlertPresented = isDeletePointAlertPresented
    self.isEditDiscardConfirmationPresented = isEditDiscardConfirmationPresented
    self.isEditInvalidCoordinateAlertPresented = isEditInvalidCoordinateAlertPresented
    self.coordinateInputText = coordinateInputText
    self.isTooltipVisible = isTooltipVisible
    self.points = points
  }

  // MARK: - Intents (Placeholders)

  func presentCoordinateSheet() {
    activeSheet = .boundaryCoordinate
  }

  func dismissCoordinateSheet() {
    isDiscardConfirmationPresented = false
    isInvalidCoordinateAlertPresented = false
    dismissEditCoordinateSheet()
    isAddCoordinateSheetPresented = false
    activeSheet = nil
  }

  func handleMapTap(at coordinate: CLLocationCoordinate2D) {
    guard
      !isAddCoordinateSheetPresented,
      editingPoint == nil,
      CLLocationCoordinate2DIsValid(coordinate)
    else {
      return
    }

    recordUndoSnapshot()
    let newPoint = BoundaryPoint(coordinate: coordinate)
    points.append(newPoint)
    syncSheetDetentForPointCount()
    AccessibilityCaptionCenter.shared.announce(
      "Added CPT Point \(points.count) at \(newPoint.formattedCoordinate). \(canCreateProject ? "Boundary ready." : "Need \(3 - points.count) more to complete boundary.")",
      soundDescription: "Map tap"
    )
  }

  func beginPointDrag() {
    guard !isAddCoordinateSheetPresented, editingPoint == nil else { return }
    recordUndoSnapshot()
  }

  func updatePointCoordinate(
    id: BoundaryPoint.ID,
    to coordinate: CLLocationCoordinate2D
  ) {
    guard
      !isAddCoordinateSheetPresented,
      editingPoint == nil,
      CLLocationCoordinate2DIsValid(coordinate),
      let index = points.firstIndex(where: { $0.id == id })
    else {
      return
    }

    points[index].latitude = coordinate.latitude
    points[index].longitude = coordinate.longitude
  }

  func addCoordinate() {
    isAddCoordinateSheetPresented = true
  }

  func title(for point: BoundaryPoint) -> String {
    if let index = points.firstIndex(where: { $0.id == point.id }) {
      return "CPT Point \(index + 1)"
    }
    return "CPT Point 1"
  }

  func selectPointForEditing(_ point: BoundaryPoint) {
    let currentPoint = points.first(where: { $0.id == point.id }) ?? point
    isDeletePointAlertPresented = false
    isEditDiscardConfirmationPresented = false
    isEditInvalidCoordinateAlertPresented = false
    editLatitudeText = currentPoint.formattedLatitude
    editLongitudeText = currentPoint.formattedLongitude
    editingPoint = currentPoint
  }

  func requestDismissEditCoordinateSheet() {
    if hasUnsavedEditCoordinateChanges {
      isEditDiscardConfirmationPresented = true
    } else {
      dismissEditCoordinateSheet()
    }
  }

  func confirmDiscardEditCoordinateChanges() {
    dismissEditCoordinateSheet()
  }

  func dismissEditCoordinateSheet() {
    isDeletePointAlertPresented = false
    isEditDiscardConfirmationPresented = false
    isEditInvalidCoordinateAlertPresented = false
    editLatitudeText = ""
    editLongitudeText = ""
    editingPoint = nil
  }

  func submitEditedCoordinate() {
    guard
      let editingPoint,
      let updatedCoordinate = Self.parseCoordinatePair(
        latitudeText: editLatitudeText,
        longitudeText: editLongitudeText
      )
    else {
      isEditInvalidCoordinateAlertPresented = true
      return
    }

    if let index = points.firstIndex(where: { $0.id == editingPoint.id }) {
      let hasChanged =
        points[index].latitude != updatedCoordinate.latitude ||
        points[index].longitude != updatedCoordinate.longitude
      if hasChanged {
        recordUndoSnapshot()
        points[index].latitude = updatedCoordinate.latitude
        points[index].longitude = updatedCoordinate.longitude
        AccessibilityCaptionCenter.shared.announce(
          "Updated CPT Point \(index + 1) to \(points[index].formattedCoordinate)."
        )
      }
    }

    dismissEditCoordinateSheet()
  }

  func requestDeleteEditingPoint() {
    isDeletePointAlertPresented = true
  }

  func confirmDeleteEditingPoint() {
    var deletedTitle = "CPT Point"
    if let editingPoint, let index = points.firstIndex(where: { $0.id == editingPoint.id }) {
      deletedTitle = "CPT Point \(index + 1)"
      recordUndoSnapshot()
      points.remove(at: index)
    }
    syncSheetDetentForPointCount()
    dismissEditCoordinateSheet()
    AccessibilityCaptionCenter.shared.announce(
      "Deleted \(deletedTitle). \(boundaryPointsSummaryText) remaining.",
      soundDescription: "Point deleted"
    )
  }

  func deletePoint(id: BoundaryPoint.ID) {
    guard let index = points.firstIndex(where: { $0.id == id }) else { return }
    let deletedTitle = "CPT Point \(index + 1)"
    recordUndoSnapshot()
    points.remove(at: index)
    if editingPoint?.id == id {
      dismissEditCoordinateSheet()
    }
    syncSheetDetentForPointCount()
    AccessibilityCaptionCenter.shared.announce(
      "Deleted \(deletedTitle). \(boundaryPointsSummaryText) remaining.",
      soundDescription: "Point deleted"
    )
  }

  func requestDismissAddCoordinateSheet() {
    if hasUnsavedCoordinateInput {
      isDiscardConfirmationPresented = true
    } else {
      dismissAddCoordinateSheet()
    }
  }

  func confirmDiscardCoordinateInput() {
    dismissAddCoordinateSheet()
  }

  func dismissAddCoordinateSheet() {
    isDiscardConfirmationPresented = false
    isInvalidCoordinateAlertPresented = false
    coordinateInputText = ""
    isAddCoordinateSheetPresented = false
  }

  func submitCoordinate() {
    guard let parsedPoints = Self.parseCoordinates(coordinateInputText) else {
      isInvalidCoordinateAlertPresented = true
      return
    }

    recordUndoSnapshot()
    points.append(contentsOf: parsedPoints)
    syncSheetDetentForPointCount()
    focusOnCoordinates(points.map(\.coordinate))
    dismissAddCoordinateSheet()
    AccessibilityCaptionCenter.shared.announce(
      "Added \(parsedPoints.count) \(parsedPoints.count == 1 ? "coordinate" : "coordinates"). Total \(boundaryPointsSummaryText)."
    )
  }

  private func focusOnCoordinates(_ coordinates: [CLLocationCoordinate2D]) {
    guard let first = coordinates.first else { return }

    if coordinates.count == 1 {
      cameraPosition = .region(
        MKCoordinateRegion(
          center: first,
          span: BoundaryMapConfiguration.defaultSpan
        )
      )
      return
    }

    var minLat = first.latitude
    var maxLat = first.latitude
    var minLon = first.longitude
    var maxLon = first.longitude

    for coordinate in coordinates {
      minLat = min(minLat, coordinate.latitude)
      maxLat = max(maxLat, coordinate.latitude)
      minLon = min(minLon, coordinate.longitude)
      maxLon = max(maxLon, coordinate.longitude)
    }

    let center = CLLocationCoordinate2D(
      latitude: (minLat + maxLat) / 2,
      longitude: (minLon + maxLon) / 2
    )
    let span = MKCoordinateSpan(
      latitudeDelta: max((maxLat - minLat) * 1.6, BoundaryMapConfiguration.defaultSpan.latitudeDelta),
      longitudeDelta: max((maxLon - minLon) * 1.6, BoundaryMapConfiguration.defaultSpan.longitudeDelta)
    )
    cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
  }

  static func isValidCoordinateInput(_ text: String) -> Bool {
    parseCoordinates(text) != nil
  }

  static func parseCoordinates(_ text: String) -> [BoundaryPoint]? {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else { return nil }

    let lines = trimmedText.components(separatedBy: .newlines)
    var result: [BoundaryPoint] = []
    result.reserveCapacity(lines.count)

    for line in lines {
      guard let point = parseCoordinateLine(line) else {
        return nil
      }
      result.append(point)
    }

    return result
  }

  private static func parseCoordinateLine(_ line: String) -> BoundaryPoint? {
    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
    guard !trimmedLine.isEmpty else { return nil }

    let parts = trimmedLine.split(separator: ",", omittingEmptySubsequences: false)
    guard parts.count == 2,
          let coordinate = parseCoordinatePair(
            latitudeText: String(parts[0]),
            longitudeText: String(parts[1])
          )
    else {
      return nil
    }

    return BoundaryPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
  }

  static func parseCoordinatePair(
    latitudeText: String,
    longitudeText: String
  ) -> CLLocationCoordinate2D? {
    let latString = latitudeText.trimmingCharacters(in: .whitespacesAndNewlines)
    let lonString = longitudeText.trimmingCharacters(in: .whitespacesAndNewlines)

    guard
      let latitude = Double(latString),
      let longitude = Double(lonString),
      latitude.isFinite,
      longitude.isFinite
    else {
      return nil
    }

    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    guard CLLocationCoordinate2DIsValid(coordinate) else {
      return nil
    }

    return coordinate
  }

  func toggleTooltip() {
    isTooltipVisible.toggle()
  }

  func dismissTooltip() {
    isTooltipVisible = false
  }

  func toggleMapLayer() {
    isSatelliteStyle.toggle()
    AccessibilityCaptionCenter.shared.announce(
      "Map style changed to \(isSatelliteStyle ? "Satellite" : "Standard")."
    )
  }

  func focusLocation() {
    cameraPosition = .region(BoundaryMapConfiguration.defaultRegion)
    AccessibilityCaptionCenter.shared.announce("Map centered on default anchor location.")
  }

  func beginEditingProjectName() {
    isEditingNameSession = true
    hasRecordedNameEditInSession = false
  }

  func setProjectName(_ newName: String) {
    guard newName != projectName else { return }

    if !isEditingNameSession {
      recordUndoSnapshot()
      projectName = newName
      return
    }

    if !hasRecordedNameEditInSession {
      undoStack.append(
        EditorSnapshot(
          projectName: projectName,
          points: points
        )
      )
      redoStack.removeAll()
      hasRecordedNameEditInSession = true
    }

    projectName = newName
  }

  func finishEditingProjectName() {
    guard isEditingNameSession else { return }
    let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    projectName = trimmed.isEmpty ? "Project name" : trimmed

    if hasRecordedNameEditInSession,
       let lastSnapshot = undoStack.last,
       lastSnapshot.projectName == projectName,
       lastSnapshot.points == points
    {
      undoStack.removeLast()
    }

    isEditingNameSession = false
    hasRecordedNameEditInSession = false
  }

  func resetAnchor() {
    guard !points.isEmpty else { return }
    recordUndoSnapshot()
    points.removeAll()
    if editingPoint != nil {
      dismissEditCoordinateSheet()
    }
    syncSheetDetentForPointCount()
    AccessibilityCaptionCenter.shared.announce("All boundary points cleared.")
  }

  func undo() {
    finishEditingProjectName()
    guard let previousSnapshot = undoStack.popLast() else { return }
    redoStack.append(
      EditorSnapshot(
        projectName: projectName,
        points: points
      )
    )
    projectName = previousSnapshot.projectName
    points = previousSnapshot.points
    if let editingPoint, !points.contains(where: { $0.id == editingPoint.id }) {
      dismissEditCoordinateSheet()
    }
    syncSheetDetentForPointCount()
    AccessibilityCaptionCenter.shared.announce(
      "Undid last change. \(boundaryPointsSummaryText)."
    )
  }

  func redo() {
    finishEditingProjectName()
    guard let nextSnapshot = redoStack.popLast() else { return }
    undoStack.append(
      EditorSnapshot(
        projectName: projectName,
        points: points
      )
    )
    projectName = nextSnapshot.projectName
    points = nextSnapshot.points
    if let editingPoint, !points.contains(where: { $0.id == editingPoint.id }) {
      dismissEditCoordinateSheet()
    }
    syncSheetDetentForPointCount()
    AccessibilityCaptionCenter.shared.announce(
      "Redid change. \(boundaryPointsSummaryText)."
    )
  }

  private func recordUndoSnapshot() {
    finishEditingProjectName()
    undoStack.append(
      EditorSnapshot(
        projectName: projectName,
        points: points
      )
    )
    redoStack.removeAll()
  }

  private func syncSheetDetentForPointCount() {
    if points.count >= 3, selectedSheetDetent == Self.defaultSheetDetent {
      selectedSheetDetent = Self.populatedSheetDetent
    } else if points.count < 3, selectedSheetDetent == Self.populatedSheetDetent {
      selectedSheetDetent = Self.defaultSheetDetent
    }
  }

  @discardableResult
  func createProject() -> Project? {
    guard canCreateProject else { return nil }
    finishEditingProjectName()
    let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalName = trimmedName.isEmpty ? "Project name" : trimmedName

    if var existing = editingProject {
      existing.name = finalName
      existing.boundaryPoints = points
      existing.lastEdited = Date()
      if !existing.cptPoints.isEmpty {
        let recomputed = CPTPipelineCoordinator.recomputeFromScratch(
          boundaryCoordinates: existing.boundaryCoordinates,
          cptPoints: existing.cptPoints
        )
        existing.latestRecommendation = recomputed
        existing.consecutiveSufficientCount = recomputed.consecutiveSufficientCount
      }
      return existing
    }

    return Project(
      name: finalName,
      lastEdited: Date(),
      boundaryPoints: points
    )
  }

  func loadExistingProject(_ project: Project) {
    guard editingProject?.id != project.id else { return }
    editingProject = project
    projectName = project.name
    points = project.boundaryPoints
    undoStack.removeAll()
    redoStack.removeAll()
    selectedSheetDetent = points.count >= 3 ? Self.populatedSheetDetent : Self.defaultSheetDetent
    if !points.isEmpty {
      cameraPosition = .region(project.boundaryRegion)
    }
  }
}
