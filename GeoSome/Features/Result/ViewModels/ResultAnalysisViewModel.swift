import CoreLocation
import Foundation
import Observation
import SwiftUI

struct GeotechnicalConcernItem: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let implication: String
  let locationAndDepthLines: [String]
}

@MainActor
@Observable
final class ResultAnalysisViewModel {
  static let collapsedSheetDetent: PresentationDetent = .height(74)
  static let defaultSheetDetent: PresentationDetent = .height(460)
  static let expandedSheetDetent: PresentationDetent = .height(680)

  static let defaultCameraYaw: Float = -0.54
  static let defaultCameraPitch: Float = 0.34
    static let defaultCameraZoom: Float = 2.5

  static let defaultBearingCameraYaw: Float = -0.05
  static let defaultBearingCameraPitch: Float = 0.68
  static let defaultBearingCameraZoom: Float = 1.35

  nonisolated static let defaultConcerns: [GeotechnicalConcernItem] = [
    GeotechnicalConcernItem(
      id: "soft-sensitive-clay-lens",
      title: "Soft Sensitive Clay Lens (Consolidation Settlement)",
      implication: "Precludes shallow raft foundations without ground improvement or deep pile transfer.",
      locationAndDepthLines: [
        "Northeast & Central Sector",
        "(E: 18-32m, N: 12-26m)",
        "Depth: 4.0 m to 8.5 m (thickness 4.5 m)"
      ]
    ),
    GeotechnicalConcernItem(
      id: "loose-saturated-sand",
      title: "Loose Saturated Sand (Liquefaction Susceptibility)",
      implication: "Requires dynamic compaction or vibro-stone columns if supporting ground-bearing slabs.",
      locationAndDepthLines: [
        "Northwest Quadrant",
        "(E: 4-12m, N: 28-36m)",
        "Depth: 0.5 m to 2.8 m"
      ]
    ),
    GeotechnicalConcernItem(
      id: "dipping-hard-stratum",
      title: "Dipping Hard Stratum / Non-Uniform Pile Refusal",
      implication: "Requires stepped pile schedule divided into Zone North (10m) and Zone South (18m).",
      locationAndDepthLines: [
        "Site-Wide Southward Dip (Dip Angle ~14°) •",
        "Depth: North: -8.2 m → South: -17.8 m"
      ]
    )
  ]

  var project: Project
  var selectedTab: ResultAnalysisTab = .threeDLayer

  // Pure Data Model: [GridCoord: SoilVoxel] inside SubsurfaceVoxelVolume
  private(set) var volume: SubsurfaceVoxelVolume
  /// Cached inference and rule output for the existing Bearing Layer presentation.
  private(set) var qcfsResult: QCFSInferenceResult?
  private(set) var bearingRuleEvaluation: BearingRuleEvaluation?
  private(set) var bearingRenderRevision: Int = 0

  var bearingRuleOutput: BearingRuleOutput? {
    if case .candidateDetected(let output) = bearingRuleEvaluation { return output }
    return nil
  }

  var bearingStatusText: String {
    if case .coreML(let qcfs) = qcfsResult, qcfs.inputProvenance == "Demo CPT" {
      return "Simulasi/demo — hasil bukan pengukuran lapangan. " + (bearingRuleEvaluation?.statusText ?? "Analisis belum tersedia.")
    }
    let status = bearingRuleEvaluation?.statusText ?? "QC-FS belum tersedia; belum ada hasil Bearing Layer."
    return status
  }

  var bearingIcFilterActive: Bool { bearingIcThresholdText != "N/A" }
  let bearingUncertaintyProductionValidated = false
  var bearingUncertaintyExperimentalInferenceReady = false
  var bearingDepthErrorBoundText = "Belum tersedia"

  /// The slider's configured value is independent of the Ic at a tapped candidate.
  /// Candidate screening requires a valid, aligned SchemaGAN reconstruction.
  var bearingIcThresholdText: String {
    guard case .coreML(let qcfs) = qcfsResult,
          let ic = qcfs.icReconstruction,
          ic.inferenceSource == "SchemaGAN V4.2 Flexible Core ML",
          ic.grid.hasSamePhysicalGrid(as: qcfs.grid),
          ic.reconstructedIc.count == qcfs.grid.nx,
          ic.validMask.count == qcfs.grid.nx,
          qcfs.validMask.count == qcfs.grid.nx else { return "N/A" }
    var hasValidVoxel = false
    for x in 0..<qcfs.grid.nx {
      guard ic.reconstructedIc[x].count == qcfs.grid.ny,
            ic.validMask[x].count == qcfs.grid.ny,
            qcfs.validMask[x].count == qcfs.grid.ny else { return "N/A" }
      for y in 0..<qcfs.grid.ny {
        guard ic.reconstructedIc[x][y].count == qcfs.grid.nz,
              ic.validMask[x][y].count == qcfs.grid.nz,
              qcfs.validMask[x][y].count == qcfs.grid.nz,
              ic.validMask[x][y] == qcfs.validMask[x][y] else { return "N/A" }
        for z in 0..<qcfs.grid.nz where ic.validMask[x][y][z] {
          guard ic.reconstructedIc[x][y][z].isFinite else { return "N/A" }
          hasValidVoxel = true
        }
      }
    }
    return hasValidVoxel ? String(format: "%.2f", soilBehaviorIndexIc) : "N/A"
  }

  /// Reuses the current QC-FS volume; criteria changes never rerun the CNN.
  func reevaluateBearingRule() {
    let previousCell = selectedBearingCell
    let previousLocation = bearingPopoverLocation
    let wasPopoverPresented = isBearingPopoverPresented
    isBearingPopoverPresented = false
    selectedBearingVoxel = nil
    selectedBearingTopDepthM = nil
    selectedBearingCell = nil
    selectedBearingIcText = "N/A"
    comparedBearingPoints.removeAll()
    isCompareDataSheetActive = false
    bearingRuleEvaluation = qcfsResult.map {
      guard bearingIcFilterActive else {
        return .invalidInput("Hasil Bearing Layer memerlukan rekonstruksi Ic SchemaGAN yang valid dan selaras.")
      }
      return BearingRuleService.evaluate(qcfs: $0, criteria: .init(
        qcMinimumMPa: coneResistanceQc, minimumThicknessM: minLayerThickness,
        minimumLateralFraction: 0.05
      ), experimentalIcMaximum: soilBehaviorIndexIc)
    }
    bearingRenderRevision += 1
    updateBearingSummaryMetrics()
    if let previousCell, let previousLocation,
       bearingRuleOutput?.intervals.contains(where: {
         $0.xIndex == previousCell.x && $0.yIndex == previousCell.y
       }) == true {
      handleBearingLayerTap(
        at: previousLocation, voxel: nil,
        gridX: previousCell.x, gridZ: previousCell.y,
        announceSelection: false
      )
      isBearingPopoverPresented = wasPopoverPresented
    }
  }

  // Real-time Cross-Section Slicing Controls (in meters)
  var slicingXMeters: Double
  var slicingYMeters: Double
  var isSlicingCardExpanded: Bool = false
  var isHardSoilVisible: Bool = true

  // Left Sheet State & Subsurface Conditions Content
  var isLeftSheetPresented: Bool = false
  var selectedSheetDetent: PresentationDetent = ResultAnalysisViewModel.collapsedSheetDetent
  var isSubsurfaceConditionsEmpty: Bool = false
  var isGeotechnicalConcernsEmpty: Bool = false
  var groundConditionsSummary: String =
    "The site generally exhibits alternating layers of clay-dominant and sand-like soil behavior. Subsurface conditions vary across the investigation area, with deeper competent strata predicted toward the southern sector."
  var geotechnicalConcerns: [GeotechnicalConcernItem] = ResultAnalysisViewModel.defaultConcerns
  var selectedConcernID: String? = ResultAnalysisViewModel.defaultConcerns.first?.id
  var predictionUncertaintyPercent: Int = 12

  // Interactive Voxel Selection & Camera Orbit State
  var selectedVoxel: SoilVoxel?
  var selectedPipePosition3D: SIMD3<Float>?
  var cameraYaw: Float = ResultAnalysisViewModel.defaultCameraYaw
  var cameraPitch: Float = ResultAnalysisViewModel.defaultCameraPitch
  var cameraZoom: Float = ResultAnalysisViewModel.defaultCameraZoom

  // Bearing Layer Camera & Summary State
  var selectedBearingVoxel: BearingLayerVoxel?
  var bearingCameraYaw: Float = ResultAnalysisViewModel.defaultBearingCameraYaw
  var bearingCameraPitch: Float = ResultAnalysisViewModel.defaultBearingCameraPitch
  var bearingCameraZoom: Float = ResultAnalysisViewModel.defaultBearingCameraZoom
  var shallowestBearingDepthText: String = "—"
  var deepestBearingDepthText: String = "—"
  var variationBearingDepthText: String = "—"
  var relativeUncertaintyText: String = "Belum tersedia"
  var highUncertaintyAreaPercentText: String = "Belum dapat ditentukan"
  var highUncertaintyDescription: String = "Ketidakpastian kedalaman Bearing Layer belum tervalidasi untuk proyek ini."

  // Bearing Layer Criteria & Slicing State
  var isBearingCriteriaCardExpanded: Bool = true
  var coneResistanceQc: Double = 15.0
  var soilBehaviorIndexIc: Double = 1.80
  var selectedBearingIcText: String = "N/A"
  var minLayerThickness: Double = 2.0

  // Bearing Layer Tapped Point Popover State
  var isBearingPopoverPresented: Bool = false
  var bearingPopoverLocation: CGPoint?
  var selectedBearingTitle: String = "Bearing Layer"
  var selectedBearingDepthText: String = "—"
  var selectedBearingTopDepthM: Double?
  var selectedBearingCell: (x: Int, y: Int)?
  var selectedBearingNorthingText: String = "—"
  var selectedBearingEastingText: String = "—"
  var isBearingCompared: Bool = false

  // Bearing Layer Comparison State
  var comparedBearingPoints: [ComparedBearingPointItem] = []
  var isCompareDataSheetActive: Bool = false
  var lastTappedGridX: Int = 0
  var lastTappedGridZ: Int = 0

  // Popover State for Tapping the Top of the 3D Object
  var isProfilePopoverPresented: Bool = false
  var profilePopoverLocation: CGPoint?
  var selectedCPTPointTitle: String = "CPT Point-01"
  var selectedCPTPointLatitude: String = "-6.215432"
  var selectedCPTPointLongitude: String = "106.845321"
  var selectedPopoverLayers: [SBTProfileLayerItem] = CPTPointProfilePopoverView.defaultLayers

  var displayedCPTPointsCount: Int {
    if isSubsurfaceConditionsEmpty {
      return project.cptPoints.count
    }
    return project.cptPoints.isEmpty ? 12 : project.cptPoints.count
  }

  init(project: Project? = nil) {
    let resolvedProject = project ?? Project(
      name: "Project name",
      lastEdited: Date(),
      boundaryPoints: CPTRecommendationViewModel.defaultSamplePoints
    )
    self.project = resolvedProject

    if let project, project.cptPoints.isEmpty {
      self.isSubsurfaceConditionsEmpty = true
      self.isGeotechnicalConcernsEmpty = true
    }

    let coords = resolvedProject.boundaryPoints.isEmpty
      ? CPTRecommendationViewModel.defaultSamplePoints.map(\.coordinate)
      : resolvedProject.boundaryCoordinates

    let builtVolume = VoxelMeshSynthesizer.buildVolume(
      boundaryCoordinates: coords,
      cptPoints: resolvedProject.cptPoints,
      gridPolicy: resolvedProject.gridPolicy
    )
    self.volume = builtVolume
    let initialQCFS = resolvedProject.cptPoints.isEmpty ? nil : CPTPipelineCoordinator.reconstructQCFS(
      boundaryCoordinates: coords,
      cptPoints: resolvedProject.cptPoints,
      gridPolicy: resolvedProject.gridPolicy
    )
    self.qcfsResult = initialQCFS
    self.bearingRuleEvaluation = nil
    self.slicingXMeters = Double(builtVolume.widthXM)
    self.slicingYMeters = Double(builtVolume.lengthZM)

    if let rec = resolvedProject.latestRecommendation {
      let uncertainty = max(1, 100 - rec.confidenceLevel)
      self.predictionUncertaintyPercent = uncertainty
    }
    reevaluateBearingRule()
  }

  var maxSlicingXMeters: Double {
    max(Double(volume.widthXM), 2.0)
  }

  var maxSlicingYMeters: Double {
    max(Double(volume.lengthZM), 2.0)
  }

  var minSlicingXMeters: Double {
    min(2.0, maxSlicingXMeters * 0.2)
  }

  var minSlicingYMeters: Double {
    min(2.0, maxSlicingYMeters * 0.2)
  }

  var maxSliceXIndex: Int {
    guard maxSlicingXMeters > 0 else { return volume.nx - 1 }
    let ratio = min(max(slicingXMeters / maxSlicingXMeters, 0.05), 1.0)
    return min(max(Int((ratio * Double(volume.nx - 1)).rounded()), 1), volume.nx - 1)
  }

  var maxSliceZIndex: Int {
    guard maxSlicingYMeters > 0 else { return volume.nz - 1 }
    let ratio = min(max(slicingYMeters / maxSlicingYMeters, 0.05), 1.0)
    return min(max(Int((ratio * Double(volume.nz - 1)).rounded()), 1), volume.nz - 1)
  }

  func resolveProject(with id: Project.ID?, from projectViewModel: ProjectViewModel?) {
    guard let id, let projectViewModel else { return }
    if let found = projectViewModel.projects.first(where: { $0.id == id }) {
      updateProject(found)
    }
  }

  func updateProject(_ newProject: Project) {
    project = newProject
    let coords = newProject.boundaryPoints.isEmpty
      ? CPTRecommendationViewModel.defaultSamplePoints.map(\.coordinate)
      : newProject.boundaryCoordinates

    let builtVolume = VoxelMeshSynthesizer.buildVolume(
      boundaryCoordinates: coords,
      cptPoints: newProject.cptPoints,
      gridPolicy: newProject.gridPolicy
    )
    volume = builtVolume
    qcfsResult = newProject.cptPoints.isEmpty ? nil : CPTPipelineCoordinator.reconstructQCFS(
      boundaryCoordinates: coords,
      cptPoints: newProject.cptPoints,
      gridPolicy: newProject.gridPolicy
    )
    reevaluateBearingRule()
    slicingXMeters = Double(builtVolume.widthXM)
    slicingYMeters = Double(builtVolume.lengthZM)
    selectedVoxel = nil
    selectedBearingVoxel = nil
    isBearingPopoverPresented = false
    comparedBearingPoints.removeAll()
    isCompareDataSheetActive = false

    if let rec = newProject.latestRecommendation {
      let uncertainty = max(1, 100 - rec.confidenceLevel)
      predictionUncertaintyPercent = uncertainty
    }

    if newProject.cptPoints.isEmpty {
      isSubsurfaceConditionsEmpty = true
      isGeotechnicalConcernsEmpty = true
    } else {
      isSubsurfaceConditionsEmpty = false
      isGeotechnicalConcernsEmpty = false
    }
  }

  func presentLeftSheetIfNeeded() {
    isLeftSheetPresented = true
  }

  func dismissLeftSheet() {
    if isCompareDataSheetActive {
      comparedBearingPoints.removeAll()
      isCompareDataSheetActive = false
    }
    isLeftSheetPresented = false
  }

  func openLeftSheet() {
    isProfilePopoverPresented = false
    selectedSheetDetent = .large
    isLeftSheetPresented = true
    AccessibilityCaptionCenter.shared.announce("Left analysis sheet opened.")
  }

  func toggleLeftSheet() {
    if selectedSheetDetent == Self.collapsedSheetDetent {
      openLeftSheet()
    } else {
      selectedSheetDetent = Self.collapsedSheetDetent
      AccessibilityCaptionCenter.shared.announce("Left analysis sheet collapsed.")
    }
  }

  func selectTab(_ tab: ResultAnalysisTab) {
    selectedTab = tab
    if tab == .bearingLayer { reevaluateBearingRule() }
    isProfilePopoverPresented = false
    isBearingPopoverPresented = false
    bearingPopoverLocation = nil
    if isCompareDataSheetActive {
      exitCompareMode()
    }
    isLeftSheetPresented = true
    if tab == .threeDLayer {
      selectedSheetDetent = Self.collapsedSheetDetent
      isSlicingCardExpanded = false
    } else {
      selectedSheetDetent = Self.defaultSheetDetent
    }
    AccessibilityCaptionCenter.shared.announce("\(tab.rawValue) selected.")
  }

  func resetBearingCriteria() {
    coneResistanceQc = 15.0
    soilBehaviorIndexIc = 1.80
    minLayerThickness = 2.0
    reevaluateBearingRule()
    AccessibilityCaptionCenter.shared.announce("Identification criteria reset to defaults.")
  }

  func resetView() {
    slicingXMeters = maxSlicingXMeters
    slicingYMeters = maxSlicingYMeters
    coneResistanceQc = 15.0
    soilBehaviorIndexIc = 1.80
    minLayerThickness = 2.0
    reevaluateBearingRule()
    cameraYaw = Self.defaultCameraYaw
    cameraPitch = Self.defaultCameraPitch
    cameraZoom = Self.defaultCameraZoom
    bearingCameraYaw = Self.defaultBearingCameraYaw
    bearingCameraPitch = Self.defaultBearingCameraPitch
    bearingCameraZoom = Self.defaultBearingCameraZoom
    selectedVoxel = nil
    selectedPipePosition3D = nil
    isProfilePopoverPresented = false
    isBearingPopoverPresented = false
    bearingPopoverLocation = nil
    comparedBearingPoints = []
    isCompareDataSheetActive = false
    selectedSheetDetent = Self.collapsedSheetDetent
    isSlicingCardExpanded = false
    isBearingCriteriaCardExpanded = false
    AccessibilityCaptionCenter.shared.announce("3D view and slicing reset.")
  }

  func handleBearingLayerTap(
    at screenPoint: CGPoint, voxel: BearingLayerVoxel?, gridX: Int, gridZ: Int,
    announceSelection: Bool = true
  ) {
    guard let output = bearingRuleOutput,
          (0..<output.grid.nx).contains(gridX), (0..<output.grid.ny).contains(gridZ) else { return }
    let columnIntervals = output.intervals
      .filter { $0.xIndex == gridX && $0.yIndex == gridZ }
      .sorted { $0.topDepthM < $1.topDepthM }
    guard let first = columnIntervals.first else { return }
    selectedBearingVoxel = nil
    selectedBearingCell = (gridX, gridZ)
    bearingPopoverLocation = screenPoint
    isProfilePopoverPresented = false
    lastTappedGridX = gridX
    lastTappedGridZ = gridZ

    let otherIntervals = columnIntervals.dropFirst().map {
      String(format: "%.1f–%.1f m (%.1f m)", $0.topDepthM, $0.bottomDepthM, $0.thicknessM)
    }.joined(separator: "; ")
    selectedBearingTitle = String(format: "Kandidat · dasar %.1f m · tebal %.1f m", first.bottomDepthM, first.thicknessM)
    if !otherIntervals.isEmpty {
      selectedBearingTitle += "; lain: " + otherIntervals
    }
    let intervalText = columnIntervals.map { String(format: "%.1f–%.1f m", $0.topDepthM, $0.bottomDepthM) }.joined(separator: ", ")
    selectedBearingDepthText = String(format: "%.1f m", first.topDepthM)
    selectedBearingTopDepthM = first.topDepthM
    selectedBearingNorthingText = String(format: "lokal %.1f m", first.projectYM)
    selectedBearingEastingText = String(format: "lokal %.1f m", first.projectXM)
    selectedBearingIcText = "N/A"
    if case .coreML(let qcfs) = qcfsResult {
      if let ic = qcfs.icReconstruction,
         ic.inferenceSource == "SchemaGAN V4.2 Flexible Core ML",
         ic.grid.hasSamePhysicalGrid(as: qcfs.grid) {
        let depthIndex = Int((first.topDepthM / ic.grid.dzM).rounded())
        if (0..<ic.grid.nz).contains(depthIndex),
           ic.validMask[gridX][gridZ][depthIndex] {
          let value = ic.reconstructedIc[gridX][gridZ][depthIndex]
          if value.isFinite {
            selectedBearingIcText = String(format: "%.2f", value)
          }
        }
      }
      let qValues = columnIntervals.compactMap { interval -> Double? in
        let z = Int((interval.topDepthM / output.grid.dzM).rounded())
        guard (0..<output.grid.nz).contains(z) else { return nil }
        return qcfs.qcMPa[gridX][gridZ][z]
      }
      let qcText = qValues.map { String(format: "%.2f", $0) }.joined(separator: ", ")
      highUncertaintyDescription = String(format:
        "%@. X %.1f m, Y %.1f m; interval %@; ketebalan total %.1f m; qc prediksi pada puncak interval %@ MPa; CPT terdekat %.1f m. Uncertainty terkalibrasi belum tersedia.",
        bearingStatusText, first.projectXM, first.projectYM, intervalText,
        output.totalThicknessMXY[output.grid.column(gridX, gridZ)], qcText,
        first.nearestCPTDistanceM)
    }

    isBearingCompared = false
    isBearingPopoverPresented = true
    if announceSelection {
      AccessibilityCaptionCenter.shared.announce("Bearing layer selected: \(selectedBearingTitle), depth \(selectedBearingDepthText).")
    }
  }

  func addCurrentBearingToCompare() {
    guard let output = bearingRuleOutput,
          let interval = output.intervals
            .filter({ $0.xIndex == lastTappedGridX && $0.yIndex == lastTappedGridZ })
            .min(by: { $0.topDepthM < $1.topDepthM }) else { return }
    isBearingPopoverPresented = false
    let nextNum = comparedBearingPoints.count + 1
    let label = "B-\(nextNum)"
    let title = String(format: "Bearing Layer - %02d", nextNum)

    let depthVal = Float(interval.topDepthM)
    let gX = lastTappedGridX
    let gZ = lastTappedGridZ
    let wX = BearingCandidateGeometry.localX(Double(gX), output: output, volume: volume)
    let wZ = BearingCandidateGeometry.localZ(Double(gZ), output: output, volume: volume)

    let newItem = ComparedBearingPointItem(
      id: UUID(),
      label: label,
      title: title,
      depthText: selectedBearingDepthText,
      depthValueM: depthVal,
      northingText: selectedBearingNorthingText,
      eastingText: selectedBearingEastingText,
      gridX: gX,
      gridZ: gZ,
      worldX: wX,
      worldZ: wZ
    )
    comparedBearingPoints.append(newItem)
    isCompareDataSheetActive = true
    selectedSheetDetent = Self.defaultSheetDetent
    isLeftSheetPresented = true
    AccessibilityCaptionCenter.shared.announce("Added \(label) to compare data.")
  }

  func removeComparedPoint(_ item: ComparedBearingPointItem) {
    comparedBearingPoints.removeAll { $0.id == item.id }
    for idx in 0 ..< comparedBearingPoints.count {
      let num = idx + 1
      comparedBearingPoints[idx].label = "B-\(num)"
      comparedBearingPoints[idx].title = String(format: "Bearing Layer - %02d", num)
    }
    if comparedBearingPoints.isEmpty {
      isCompareDataSheetActive = false
    }
    AccessibilityCaptionCenter.shared.announce("Removed \(item.label) from comparison.")
  }

  func exitCompareMode() {
    isCompareDataSheetActive = false
    comparedBearingPoints.removeAll()
    AccessibilityCaptionCenter.shared.announce("Closed compare data and cleared stored points.")
  }

  func handleVoxelSelection(_ voxel: SoilVoxel?) {
    if selectedVoxel == voxel {
      selectedVoxel = nil
      selectedPipePosition3D = nil
    } else {
      selectedVoxel = voxel
      if let voxel {
        AccessibilityCaptionCenter.shared.announce(
          "Selected voxel (\(voxel.coord.x), \(voxel.coord.z)): \(voxel.soilClassification.displayName), bearing capacity \(Int(voxel.bearingCapacityKPa)) kPa."
        )
      }
    }
  }

  func selectConcern(_ concern: GeotechnicalConcernItem) {
    if selectedConcernID == concern.id {
      selectedConcernID = nil
      AccessibilityCaptionCenter.shared.announce("Cleared highlight for \(concern.title).")
    } else {
      selectedConcernID = concern.id
      AccessibilityCaptionCenter.shared.announce("Highlighted concern: \(concern.title).")
    }
  }

  func clearHighlight() {
    selectedConcernID = nil
    selectedVoxel = nil
    selectedPipePosition3D = nil
    isProfilePopoverPresented = false
    AccessibilityCaptionCenter.shared.announce("Cleared geotechnical concern highlight.")
  }

  func handleTopSurfaceTap(at screenPoint: CGPoint, local3DPoint: SIMD3<Float>?, voxel: SoilVoxel?) {
    profilePopoverLocation = screenPoint
    selectedPipePosition3D = local3DPoint

    // Collapse the left sheet to its peek detent instead of dismissing it completely.
    // This leaves the 3D model and popover unobstructed, while keeping the sheet visible
    // just slightly at the bottom so the user can easily drag it back up anytime.
    selectedSheetDetent = Self.collapsedSheetDetent
    isLeftSheetPresented = true

    // Set CPT point details and dynamic SchemaGAN SBT stratigraphy profile
    if let voxel {
      selectedVoxel = voxel
      selectedPopoverLayers = buildPopoverLayers(forColumnX: voxel.coord.x, z: voxel.coord.z)
      if let closest = findClosestCPTPoint(to: voxel) {
        selectedCPTPointTitle = closest.title
        selectedCPTPointLatitude = closest.latitude
        selectedCPTPointLongitude = closest.longitude
      } else {
        selectedCPTPointTitle = "CPT Point-01"
        selectedCPTPointLatitude = String(format: "%.6f", voxel.latitude)
        selectedCPTPointLongitude = String(format: "%.6f", voxel.longitude)
      }
    } else {
      selectedPopoverLayers = CPTPointProfilePopoverView.defaultLayers
      selectedCPTPointTitle = "CPT Point-01"
      selectedCPTPointLatitude = "-6.215432"
      selectedCPTPointLongitude = "106.845321"
    }

    // Present the native popover immediately
    isProfilePopoverPresented = true
    AccessibilityCaptionCenter.shared.announce("Showing \(selectedCPTPointTitle) SBT profile popover.")
  }

  func handleBearingCPTPointTap(at screenPoint: CGPoint, pointIndex: Int) {
    profilePopoverLocation = screenPoint
    selectedSheetDetent = Self.collapsedSheetDetent
    isLeftSheetPresented = true

    let safeIndex = max(pointIndex, 0)
    if !project.cptPoints.isEmpty {
      let clampedIdx = min(safeIndex, project.cptPoints.count - 1)
      let pt = project.cptPoints[clampedIdx]
      selectedCPTPointTitle = String(format: "CPT Point-%02d", clampedIdx + 1)
      selectedCPTPointLatitude = pt.formattedLatitude
      selectedCPTPointLongitude = pt.formattedLongitude
    } else {
      let defaultCoords: [(String, String, String)] = [
        ("CPT Point-01", "-6.215432", "106.845321"),
        ("CPT Point-02", "-6.215510", "106.845640"),
        ("CPT Point-03", "-6.215485", "106.845912")
      ]
      let item = defaultCoords[min(safeIndex, defaultCoords.count - 1)]
      selectedCPTPointTitle = item.0
      selectedCPTPointLatitude = item.1
      selectedCPTPointLongitude = item.2
    }

    if !volume.cptSurfacePositions.isEmpty {
      let posIdx = min(safeIndex, volume.cptSurfacePositions.count - 1)
      let pos = volume.cptSurfacePositions[posIdx]
      let xGrid = min(max(Int((pos.x + volume.centerX).rounded()), 0), volume.nx - 1)
      let zGrid = min(max(Int((pos.z + volume.centerZ).rounded()), 0), volume.nz - 1)
      selectedPopoverLayers = buildPopoverLayers(forColumnX: xGrid, z: zGrid)
    } else {
      selectedPopoverLayers = CPTPointProfilePopoverView.defaultLayers
    }

    isProfilePopoverPresented = true
    AccessibilityCaptionCenter.shared.announce("Showing \(selectedCPTPointTitle) SBT profile popover.")
  }

  private func buildPopoverLayers(forColumnX x: Int, z: Int) -> [SBTProfileLayerItem] {
    var columnVoxels: [SoilVoxel] = []
    for y in stride(from: volume.ny - 1, through: 0, by: -1) {
      if let v = volume.voxels[GridCoord(x: x, y: y, z: z)] {
        columnVoxels.append(v)
      }
    }
    guard !columnVoxels.isEmpty else {
      return CPTPointProfilePopoverView.defaultLayers
    }

    struct RawSegment {
      var topDepthM: Double
      var bottomDepthM: Double
      var soilType: SoilLayerType
    }

    var segments: [RawSegment] = []
    for v in columnVoxels {
      let top = Double(v.topDepthM)
      let bot = Double(v.bottomDepthM)
      if let last = segments.last, last.soilType == v.soilClassification {
        segments[segments.count - 1].bottomDepthM = bot
      } else {
        segments.append(RawSegment(topDepthM: top, bottomDepthM: bot, soilType: v.soilClassification))
      }
    }

    // Keep at most 6 segments so the popover card height stays compact and readable
    while segments.count > 6 {
      var minIdx = 0
      var minThickness = Double.greatestFiniteMagnitude
      for (i, seg) in segments.enumerated() {
        let thick = seg.bottomDepthM - seg.topDepthM
        if thick < minThickness {
          minThickness = thick
          minIdx = i
        }
      }
      if minIdx > 0 {
        segments[minIdx - 1].bottomDepthM = segments[minIdx].bottomDepthM
        segments.remove(at: minIdx)
      } else if segments.count > 1 {
        segments[1].topDepthM = segments[0].topDepthM
        segments.remove(at: 0)
      } else {
        break
      }
    }

    let totalDepth = max(segments.last?.bottomDepthM ?? Double(volume.depthYM), 1.0)
    let targetTotalHeight: CGFloat = 220.0

    return segments.map { seg in
      let ratio = CGFloat((seg.bottomDepthM - seg.topDepthM) / totalDepth)
      let barHeight = min(max((ratio * targetTotalHeight).rounded(), 30), 64)
      let isLightLayer: Bool = switch seg.soilType {
      case .sandMixtures, .cleanSands, .stiffFineGrained:
        true
      default:
        false
      }
      return SBTProfileLayerItem(
        topDepthM: (seg.topDepthM * 10).rounded() / 10,
        bottomDepthM: (seg.bottomDepthM * 10).rounded() / 10,
        name: seg.soilType.displayName,
        color: Color(seg.soilType.uiColor),
        textColor: isLightLayer ? Color.black.opacity(0.9) : Color.white,
        barHeight: barHeight
      )
    }
  }

  private func updateBearingSummaryMetrics() {
    bearingUncertaintyExperimentalInferenceReady = false
    relativeUncertaintyText = "Belum tersedia"
    highUncertaintyAreaPercentText = "Belum dapat ditentukan"
    bearingDepthErrorBoundText = "Belum tersedia"
    let output: BearingRuleOutput?
    switch bearingRuleEvaluation {
    case .candidateDetected(let value), .noCandidateDetected(let value): output = value
    default: output = nil
    }
    guard let output else {
      shallowestBearingDepthText = "—"; deepestBearingDepthText = "—"; variationBearingDepthText = "—"
      highUncertaintyDescription = bearingStatusText
      return
    }
    if let shallow = output.summary.shallowestTopDepthM, let deep = output.summary.deepestBottomDepthM {
      shallowestBearingDepthText = String(format: "%.1f m", shallow)
      deepestBearingDepthText = String(format: "%.1f m", deep)
      variationBearingDepthText = String(format: "%.1f m", deep - shallow)
    } else {
      shallowestBearingDepthText = "—"; deepestBearingDepthText = "—"; variationBearingDepthText = "—"
    }
    highUncertaintyDescription = bearingStatusText + " Uncertainty belum tersedia."
    guard bearingIcFilterActive, case .coreML(let volume) = qcfsResult else { return }
    do {
      let model = try BearingUncertaintyV3Model.load()
      let result = try BearingUncertaintyV3Service.evaluate(volume: volume, output: output,
        qcMinimum: coneResistanceQc, icMaximum: soilBehaviorIndexIc, thickness: minLayerThickness, model: model)
      relativeUncertaintyText = String(format: "%.1f%% · Experimental", result.meanRiskPercent)
      highUncertaintyAreaPercentText = String(format: "%.1f%% · Experimental", result.highRiskAreaPercent)
      if let depth = result.meanDepthM { bearingDepthErrorBoundText = String(format: "%.3f m", depth) }
      highUncertaintyDescription = "Experimental — GeoSyn. Rata-rata risiko pada seluruh kolom valid; area berisiko tinggi memakai ambang ≥20%. Bukan keamanan fondasi atau kepastian geologi."
      bearingUncertaintyExperimentalInferenceReady = true
    } catch {
#if DEBUG
      print("[Bearing uncertainty V3] unavailable: \(error)")
#endif
    }
  }

  private func findClosestCPTPoint(to voxel: SoilVoxel) -> (title: String, latitude: String, longitude: String)? {
    guard !project.cptPoints.isEmpty else { return nil }

    var bestIndex = 0
    var bestDist = Double.greatestFiniteMagnitude

    for (index, point) in project.cptPoints.enumerated() {
      let dLat = point.coordinate.latitude - voxel.latitude
      let dLon = point.coordinate.longitude - voxel.longitude
      let dist = (dLat * dLat) + (dLon * dLon)
      if dist < bestDist {
        bestDist = dist
        bestIndex = index
      }
    }

    let point = project.cptPoints[bestIndex]
    return (
      title: String(format: "CPT Point-%02d", bestIndex + 1),
      latitude: point.formattedLatitude,
      longitude: point.formattedLongitude
    )
  }
}
