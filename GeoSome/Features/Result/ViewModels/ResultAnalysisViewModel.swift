import CoreLocation
import Foundation
import Observation
import SwiftUI

nonisolated struct GeotechnicalConcernItem: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let implication: String
  let locationAndDepthLines: [String]
  var affectedVoxels: Set<GridCoord> = []
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
  var isSlicingCardExpanded: Bool = true
  var isHardSoilVisible: Bool = true

  /// Shared boundary coordinates from `project.boundaryCoordinates` (with fallback for empty preview projects)
  /// so the 3D volume and `SubsurfaceMinimapView` read the exact same polygon without duplicating state.
  var activeBoundaryCoordinates: [CLLocationCoordinate2D] {
    project.boundaryPoints.isEmpty
      ? CPTRecommendationViewModel.defaultSamplePoints.map(\.coordinate)
      : project.boundaryCoordinates
  }

  // Left Sheet State & Subsurface Conditions Content
  var isLeftSheetPresented: Bool = false
  var selectedSheetDetent: PresentationDetent = ResultAnalysisViewModel.collapsedSheetDetent
  var isSubsurfaceConditionsEmpty: Bool = false
  var isGeotechnicalConcernsEmpty: Bool = false
  var groundConditionsSummary: String =
    "The site generally exhibits alternating layers of clay-dominant and sand-like soil behavior. Subsurface conditions vary across the investigation area, with deeper competent strata predicted toward the southern sector."
  var geotechnicalConcerns: [GeotechnicalConcernItem] = ResultAnalysisViewModel.defaultConcerns
  var selectedConcernID: String? = nil
  var predictionUncertaintyPercent: Int = 12

  var activeConcernVoxels: Set<GridCoord>? {
    guard let selectedConcernID,
          let concern = geotechnicalConcerns.first(where: { $0.id == selectedConcernID }),
          !concern.affectedVoxels.isEmpty
    else {
      return nil
    }
    return concern.affectedVoxels
  }

  // Interactive Voxel Selection & Camera Rig State
  var selectedVoxel: SoilVoxel?
  var selectedPipePosition3D: SIMD3<Float>?
  var cameraController = SubsurfaceCameraController()
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
    self.cameraController.configure(for: builtVolume, resetState: true)
    self.cameraController.onCameraMoved = { [weak self] in
      guard let self, self.isProfilePopoverPresented else { return }
      self.isProfilePopoverPresented = false
    }

    if let rec = resolvedProject.latestRecommendation {
      let uncertainty = max(1, 100 - rec.confidenceLevel)
      self.predictionUncertaintyPercent = uncertainty
    }
    reevaluateBearingRule()
    updateGeotechnicalConcernsAndSummary()
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

  /// Returns the unique set of geotechnical soil classifications that actually exist in the current 3D volume,
  /// ordered according to standard Robertson SBT progression.
  var existingSoilTypes: [SoilLayerType] {
    var present = Set<SoilLayerType>()
    for voxel in volume.voxels.values {
      present.insert(voxel.soilClassification)
    }
    if present.isEmpty {
      return SoilLayerType.allCases
    }
    return SoilLayerType.allCases.filter { present.contains($0) }
  }

  /// Dynamic legend items corresponding strictly to the soil layers present in the site investigation area.
  var activeLegendItems: [LegendMapItem] {
    existingSoilTypes.map { LegendMapItem(soilType: $0) }
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
    selectedConcernID = nil
    selectedBearingVoxel = nil
    isBearingPopoverPresented = false
    comparedBearingPoints.removeAll()
    isCompareDataSheetActive = false
    selectedPipePosition3D = nil
    cameraController.configure(for: builtVolume, resetState: true)

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
    updateGeotechnicalConcernsAndSummary()
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
    cameraController.reset(for: volume)
    cameraYaw = Self.defaultCameraYaw
    cameraPitch = Self.defaultCameraPitch
    cameraZoom = Self.defaultCameraZoom
    bearingCameraYaw = Self.defaultBearingCameraYaw
    bearingCameraPitch = Self.defaultBearingCameraPitch
    bearingCameraZoom = Self.defaultBearingCameraZoom
    selectedVoxel = nil
    selectedConcernID = nil
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
    if let hitPt = local3DPoint {
      guard volume.isMetricPointInsideActiveArea(
        xM: hitPt.x,
        zM: hitPt.z,
        maxSliceX: maxSliceXIndex,
        maxSliceZ: maxSliceZIndex
      ) else {
        isProfilePopoverPresented = false
        return
      }
    }

    profilePopoverLocation = screenPoint

    // Collapse the left sheet to its peek detent instead of dismissing it completely.
    // This leaves the 3D model and popover unobstructed, while keeping the sheet visible
    // just slightly at the bottom so the user can easily drag it back up anytime.
    selectedSheetDetent = Self.collapsedSheetDetent
    isLeftSheetPresented = true

    // Query continuous bilinearly interpolated field at the exact tapped metric (x, z) coordinate
    if let hitPt = local3DPoint {
      selectedPopoverLayers = buildBilinearPopoverLayers(metricX: hitPt.x, metricZ: hitPt.z)
      let exactGeo = volume.geographicCoordinate(forMetricX: hitPt.x, zM: hitPt.z)
      selectedCPTPointLatitude = String(format: "%.6f", exactGeo.latitude)
      selectedCPTPointLongitude = String(format: "%.6f", exactGeo.longitude)

      if let pinHit = findPinNearMetricPoint(metricX: hitPt.x, metricZ: hitPt.z) {
        // Tapped an Actual CPT borehole pin: keep the orange Actual CPT visible without overlapping a Virtual CPT pipe
        selectedCPTPointTitle = pinHit.title
        selectedPipePosition3D = nil
        selectedVoxel = nil
      } else {
        // Tapped a custom location: place the Cyan/Blue Virtual CPT pipe at this exact metric coordinate
        selectedCPTPointTitle = String(format: "Virtual CPT (%.1fm, %.1fm)", hitPt.x, hitPt.z)
        selectedPipePosition3D = SIMD3<Float>(hitPt.x, 0.0, hitPt.z)
        selectedVoxel = voxel
      }
    } else if let voxel {
      selectedVoxel = voxel
      selectedPipePosition3D = nil
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
      isProfilePopoverPresented = false
      return
    }

    // Present the native popover immediately
    isProfilePopoverPresented = true
    AccessibilityCaptionCenter.shared.announce("Showing \(selectedCPTPointTitle) SBT profile popover.")
  }

  /// Creates/places a Virtual CPT in the 3D scene at the current minimap center position (`cameraController.target`)
  /// and presents the SBT stratigraphy popover immediately, only if the minimap center lies inside the active boundary area.
  func createVirtualCPTAtMinimapCenter() {
    let centerPt = SIMD3<Float>(cameraController.target.x, 0.0, cameraController.target.z)
    guard volume.isMetricPointInsideActiveArea(
      xM: centerPt.x,
      zM: centerPt.z,
      maxSliceX: maxSliceXIndex,
      maxSliceZ: maxSliceZIndex
    ) else {
      isProfilePopoverPresented = false
      AccessibilityCaptionCenter.shared.announce(
        "Minimap center is outside the active boundary area."
      )
      return
    }

    selectedPipePosition3D = centerPt

    // Collapse the left sheet to its peek detent so the 3D model and popover are unobstructed
    selectedSheetDetent = Self.collapsedSheetDetent
    isLeftSheetPresented = true

    let (fx, fz) = volume.continuousGridCoordinates(forMetricX: centerPt.x, zM: centerPt.z)
    let xGrid = min(max(Int(fx.rounded()), 0), volume.nx - 1)
    let zGrid = min(max(Int(fz.rounded()), 0), volume.nz - 1)
    selectedVoxel = volume.voxels[GridCoord(x: xGrid, y: volume.ny - 1, z: zGrid)]

    selectedPopoverLayers = buildBilinearPopoverLayers(metricX: centerPt.x, metricZ: centerPt.z)
    let exactGeo = volume.geographicCoordinate(forMetricX: centerPt.x, zM: centerPt.z)
    selectedCPTPointLatitude = String(format: "%.6f", exactGeo.latitude)
    selectedCPTPointLongitude = String(format: "%.6f", exactGeo.longitude)
    selectedCPTPointTitle = String(format: "Virtual CPT (%.1fm, %.1fm)", centerPt.x, centerPt.z)

    // Since `cameraController.target` is at the center of the 3D camera's look axis,
    // its screen projection is the center of the 3D viewport.
    let vw = max(cameraController.viewportSize.width, 320.0)
    let vh = max(cameraController.viewportSize.height, 320.0)
    profilePopoverLocation = CGPoint(x: vw * 0.5, y: vh * 0.46)
    isProfilePopoverPresented = true

    AccessibilityCaptionCenter.shared.announce(
      "Created \(selectedCPTPointTitle) at minimap center and showing SBT profile popover."
    )
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

  /// Builds the SBT stratigraphy popover layers from the continuous bilinearly interpolated `Ic` field
  /// at the exact tapped metric coordinate `(metricX, metricZ)` rather than snapping to a voxel.
  private func buildBilinearPopoverLayers(metricX: Float, metricZ: Float) -> [SBTProfileLayerItem] {
    let interpolatedSlices = volume.sampleInterpolatedStratigraphy(
      metricX: metricX,
      metricZ: metricZ,
      verticalSubdivisions: 40
    )
    guard !interpolatedSlices.isEmpty else {
      return CPTPointProfilePopoverView.defaultLayers
    }

    struct RawSegment {
      var topDepthM: Double
      var bottomDepthM: Double
      var soilType: SoilLayerType
    }

    var segments: [RawSegment] = []
    for slice in interpolatedSlices {
      if let last = segments.last, last.soilType == slice.soilType {
        segments[segments.count - 1].bottomDepthM = slice.bottomDepthM
      } else {
        segments.append(
          RawSegment(
            topDepthM: slice.topDepthM,
            bottomDepthM: slice.bottomDepthM,
            soilType: slice.soilType
          )
        )
      }
    }

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

  /// Checks if the tapped metric coordinate `(metricX, metricZ)` is within the tap radius of an uploaded/reference CPT borehole pin.
  private func findPinNearMetricPoint(metricX: Float, metricZ: Float) -> (index: Int, title: String)? {
    let pinPositions = volume.cptMetricSurfacePositions
    guard !pinPositions.isEmpty else { return nil }
    let hitRadiusM = max(min(volume.cellStepXM, volume.cellStepZM) * 1.25, 1.0)
    let hitRadiusSq = hitRadiusM * hitRadiusM

    var bestIdx: Int?
    var bestDistSq: Float = hitRadiusSq

    for (idx, pos) in pinPositions.enumerated() {
      let dx = pos.x - metricX
      let dz = pos.z - metricZ
      let distSq = dx * dx + dz * dz
      if distSq <= bestDistSq {
        bestDistSq = distSq
        bestIdx = idx
      }
    }

    guard let matched = bestIdx else { return nil }
    return (matched, String(format: "CPT Point-%02d", matched + 1))
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

  private func updateGeotechnicalConcernsAndSummary() {
    let allVoxels = Array(volume.voxels.values)
    guard !allVoxels.isEmpty else {
      geotechnicalConcerns = []
      return
    }

    let qcfsVolume: QCFSVolume?
    if case .coreML(let vol) = qcfsResult {
      qcfsVolume = vol
    } else {
      qcfsVolume = nil
    }

    func sampleQcMPa(for voxel: SoilVoxel) -> Double {
      if let qv = qcfsVolume {
        let fx = Double(voxel.coord.x) / Double(max(volume.nx - 1, 1))
        let fy = 1.0 - (Double(voxel.coord.z) / Double(max(volume.nz - 1, 1)))
        let depthIdxFromTop = (volume.ny - 1) - voxel.coord.y
        let fzDepth = (Double(depthIdxFromTop) + 0.5) / Double(max(volume.ny, 1))
        let qx = min(max(Int((fx * Double(max(qv.grid.nx - 1, 0))).rounded()), 0), max(qv.grid.nx - 1, 0))
        let qy = min(max(Int((fy * Double(max(qv.grid.ny - 1, 0))).rounded()), 0), max(qv.grid.ny - 1, 0))
        let qz = min(max(Int((fzDepth * Double(max(qv.grid.nz - 1, 0))).rounded()), 0), max(qv.grid.nz - 1, 0))
        let val = qv.qcMPa[qx][qy][qz]
        if val.isFinite, val > 0 {
          return val
        }
      }
      // Estimate representative qc (MPa) from Robertson Ic when QC-FS CNN V3 is unavailable
      let ic = Double(voxel.robertsonIc)
      return max(0.4, min(25.0, 22.0 * exp(-0.85 * max(ic - 1.3, 0.0))))
    }

    // 1. Build dynamic Ground Conditions Summary from 3D voxel stratigraphy
    var shallowCounts: [SoilLayerType: Int] = [:]
    var midCounts: [SoilLayerType: Int] = [:]
    var deepCounts: [SoilLayerType: Int] = [:]
    let ny = max(volume.ny, 1)

    for v in allVoxels {
      let depthRatio = Double(v.layerIdx) / Double(ny)
      if depthRatio < 0.34 {
        shallowCounts[v.soilClassification, default: 0] += 1
      } else if depthRatio < 0.67 {
        midCounts[v.soilClassification, default: 0] += 1
      } else {
        deepCounts[v.soilClassification, default: 0] += 1
      }
    }

    let dominantShallow = shallowCounts.max(by: { $0.value < $1.value })?.key.displayName.lowercased() ?? "sand mixtures"
    let dominantMid = midCounts.max(by: { $0.value < $1.value })?.key.displayName.lowercased() ?? "silt mixtures"
    let dominantDeep = deepCounts.max(by: { $0.value < $1.value })?.key.displayName.lowercased() ?? "dense sand"

    if !project.cptPoints.isEmpty {
      if let out = bearingRuleOutput,
         let shallowB = out.summary.shallowestTopDepthM,
         let deepB = out.summary.deepestBottomDepthM
      {
        groundConditionsSummary = String(
          format: "Reconstructed 3D stratigraphy transitions from predominantly %@ in the upper profile to %@ at mid-depth and %@ at deeper horizons. Competent bearing strata are identified between %.1f m and %.1f m depth across the site.",
          dominantShallow,
          dominantMid,
          dominantDeep,
          shallowB,
          deepB
        )
      } else {
        groundConditionsSummary = String(
          format: "Reconstructed 3D stratigraphy transitions from predominantly %@ near the surface to %@ at mid-depth and %@ across deeper horizons (up to %.1f m investigation depth).",
          dominantShallow,
          dominantMid,
          dominantDeep,
          Double(volume.depthYM)
        )
      }
    }

    // 2. Evaluate the 3 Potential Geotechnical Concerns across the 3D voxel grid
    let minVerticalCells = max(1, Int(ceil(1.0 / Double(max(volume.cellStepYM, 0.25)))))
    var settlementVoxels = Set<GridCoord>()
    var settlementQcSum = 0.0
    var settlementIcSum = 0.0

    var liquefactionVoxels = Set<GridCoord>()
    var liquefactionQcSum = 0.0
    var liquefactionIcSum = 0.0

    var contrastVoxels = Set<GridCoord>()
    var maxDeltaQc = 0.0

    for ix in 0 ..< volume.nx {
      for iz in 0 ..< volume.nz {
        guard volume.voxels[GridCoord(x: ix, y: volume.ny - 1, z: iz)] != nil else { continue }

        // A. Consolidation Settlement: contiguous fine-grained / organic clay runs (Ic >= 2.95 & low qc)
        var softRun: [SoilVoxel] = []
        for iy in stride(from: volume.ny - 1, through: 0, by: -1) {
          if let v = volume.voxels[GridCoord(x: ix, y: iy, z: iz)] {
            let qc = sampleQcMPa(for: v)
            let isSoftClay = (v.robertsonIc >= 2.95 && qc <= 2.4) ||
              v.soilClassification == .sensitiveFineGrained ||
              v.soilClassification == .organicClay ||
              (v.soilClassification == .clayToSiltyClay && qc <= 2.2)
            if isSoftClay {
              softRun.append(v)
            } else {
              if softRun.count >= minVerticalCells {
                for sv in softRun {
                  settlementVoxels.insert(sv.coord)
                  settlementQcSum += sampleQcMPa(for: sv)
                  settlementIcSum += Double(sv.robertsonIc)
                }
              }
              softRun.removeAll(keepingCapacity: true)
            }
          }
        }
        if softRun.count >= minVerticalCells {
          for sv in softRun {
            settlementVoxels.insert(sv.coord)
            settlementQcSum += sampleQcMPa(for: sv)
            settlementIcSum += Double(sv.robertsonIc)
          }
        }

        // B. Liquefaction Susceptibility: shallow-to-moderate loose cohesionless sand/silty sand (depth <= 15m)
        var looseSandRun: [SoilVoxel] = []
        for iy in stride(from: volume.ny - 1, through: 0, by: -1) {
          if let v = volume.voxels[GridCoord(x: ix, y: iy, z: iz)] {
            let qc = sampleQcMPa(for: v)
            let isShallowEnough = v.topDepthM <= 15.0
            let isSandLike = (v.robertsonIc >= 1.65 && v.robertsonIc < 2.65) ||
              v.soilClassification == .sandMixtures ||
              v.soilClassification == .cleanSands
            let isLoose = qc < 7.5
            if isShallowEnough && isSandLike && isLoose {
              looseSandRun.append(v)
            } else {
              if looseSandRun.count >= minVerticalCells {
                for lv in looseSandRun {
                  liquefactionVoxels.insert(lv.coord)
                  liquefactionQcSum += sampleQcMPa(for: lv)
                  liquefactionIcSum += Double(lv.robertsonIc)
                }
              }
              looseSandRun.removeAll(keepingCapacity: true)
            }
          }
        }
        if looseSandRun.count >= minVerticalCells {
          for lv in looseSandRun {
            liquefactionVoxels.insert(lv.coord)
            liquefactionQcSum += sampleQcMPa(for: lv)
            liquefactionIcSum += Double(lv.robertsonIc)
          }
        }

        // C. Soil Stiffness Contrast: sharp vertical jump between adjacent depth layers or variable bearing horizon
        for iy in 0 ..< (volume.ny - 1) {
          guard let vLower = volume.voxels[GridCoord(x: ix, y: iy, z: iz)],
                let vUpper = volume.voxels[GridCoord(x: ix, y: iy + 1, z: iz)]
          else { continue }
          let qcLower = sampleQcMPa(for: vLower)
          let qcUpper = sampleQcMPa(for: vUpper)
          let deltaQc = abs(qcLower - qcUpper)
          let deltaIc = abs(Double(vLower.robertsonIc - vUpper.robertsonIc))
          if deltaQc >= 6.0 || deltaIc >= 0.45 ||
             (vUpper.robertsonIc >= 2.75 && vLower.robertsonIc <= 2.15) ||
             (vLower.robertsonIc >= 2.75 && vUpper.robertsonIc <= 2.15)
          {
            contrastVoxels.insert(vLower.coord)
            contrastVoxels.insert(vUpper.coord)
            maxDeltaQc = max(maxDeltaQc, deltaQc)
          }
        }
      }
    }

    // Fallback: if any of the 3 buckets is empty on a very uniform site, highlight the most representative horizon
    // so all 3 early-warning cards can still be inspected when desired.
    if settlementVoxels.isEmpty {
      let sortedByIc = allVoxels.sorted { $0.robertsonIc > $1.robertsonIc }
      let topSlice = sortedByIc.prefix(max(allVoxels.count / 8, 1))
      for v in topSlice where v.robertsonIc >= 2.55 {
        settlementVoxels.insert(v.coord)
        settlementQcSum += sampleQcMPa(for: v)
        settlementIcSum += Double(v.robertsonIc)
      }
    }

    if liquefactionVoxels.isEmpty {
      let shallowSands = allVoxels.filter { $0.topDepthM <= 15.0 && $0.robertsonIc < 2.70 }
      let sortedByLowQc = shallowSands.sorted { sampleQcMPa(for: $0) < sampleQcMPa(for: $1) }
      for v in sortedByLowQc.prefix(max(shallowSands.count / 5, 1)) {
        liquefactionVoxels.insert(v.coord)
        liquefactionQcSum += sampleQcMPa(for: v)
        liquefactionIcSum += Double(v.robertsonIc)
      }
    }

    if contrastVoxels.isEmpty {
      let deepCompetent = allVoxels.filter { $0.robertsonIc <= 2.15 || $0.layerIdx >= (volume.ny * 2) / 3 }
      for v in deepCompetent {
        contrastVoxels.insert(v.coord)
        maxDeltaQc = max(maxDeltaQc, sampleQcMPa(for: v))
      }
    }

    var builtConcerns: [GeotechnicalConcernItem] = []

    // Build Concern 1: Consolidation Settlement
    if !settlementVoxels.isEmpty {
      let stats = computeClusterStats(for: settlementVoxels)
      let count = Double(settlementVoxels.count)
      let meanQc = settlementQcSum / count
      let meanIc = settlementIcSum / count
      let implication: String
      if stats.thicknessM >= 2.5 {
        implication = String(
          format: "Thick low-resistance clay strata (mean qc %.1f MPa, Ic %.2f) indicate high compressibility under sustained loads. Shallow foundations may experience excessive settlement without ground improvement or deep pile transfer.",
          meanQc,
          meanIc
        )
      } else {
        implication = String(
          format: "Compressible fine-grained lens (mean qc %.1f MPa, Ic %.2f) may cause localized consolidation settlement beneath shallow footings or ground-bearing slabs.",
          meanQc,
          meanIc
        )
      }
      builtConcerns.append(
        GeotechnicalConcernItem(
          id: "soft-sensitive-clay-lens",
          title: "Soft Compressible Clay Zone (Consolidation Settlement)",
          implication: implication,
          locationAndDepthLines: [
            "\(stats.sectorName) (E: \(stats.minEM)–\(stats.maxEM) m, N: \(stats.minNM)–\(stats.maxNM) m)",
            String(format: "Depth: %.1f m to %.1f m (thickness %.1f m)", stats.topDepthM, stats.bottomDepthM, stats.thicknessM)
          ],
          affectedVoxels: settlementVoxels
        )
      )
    }

    // Build Concern 2: Liquefaction Susceptibility
    if !liquefactionVoxels.isEmpty {
      let stats = computeClusterStats(for: liquefactionVoxels)
      let count = Double(liquefactionVoxels.count)
      let meanQc = liquefactionQcSum / count
      let meanIc = liquefactionIcSum / count
      let implication = String(
        format: "Shallow loose sand-like strata (mean qc %.1f MPa, Ic %.2f) exhibit low penetration resistance. If saturated below the groundwater table, this zone may be susceptible to cyclic pore-pressure buildup during seismic events.",
        meanQc,
        meanIc
      )
      builtConcerns.append(
        GeotechnicalConcernItem(
          id: "loose-saturated-sand",
          title: "Loose Cohesionless Sand (Liquefaction Susceptibility)",
          implication: implication,
          locationAndDepthLines: [
            "\(stats.sectorName) (E: \(stats.minEM)–\(stats.maxEM) m, N: \(stats.minNM)–\(stats.maxNM) m)",
            String(format: "Depth: %.1f m to %.1f m (thickness %.1f m)", stats.topDepthM, stats.bottomDepthM, stats.thicknessM)
          ],
          affectedVoxels: liquefactionVoxels
        )
      )
    }

    // Build Concern 3: Soil Stiffness Contrast / Variable Bearing Depth
    if !contrastVoxels.isEmpty {
      let stats = computeClusterStats(for: contrastVoxels)
      let bearingDepths = volume.bearingVoxels.values.map(\.bearingDepthM)
      let minB = bearingDepths.min() ?? Float(stats.topDepthM)
      let maxB = bearingDepths.max() ?? Float(stats.bottomDepthM)
      let deltaB = max(maxB - minB, 0.0)

      let implication: String
      let depthLine: String
      if deltaB >= 1.5 {
        implication = String(
          format: "Competent bearing strata vary by %.1f m across the site, accompanied by sharp vertical stiffness transitions. Foundation design should account for differential settlement or stepped pile embedment lengths.",
          deltaB
        )
        depthLine = String(format: "Bearing Horizon: %.1f m → %.1f m (Δ%.1f m)", minB, maxB, deltaB)
      } else {
        implication = String(
          format: "Abrupt vertical transitions between softer strata and stiffer layers (Δqc up to %.1f MPa) can induce localized stress concentrations and differential settlement across the footprint.",
          max(maxDeltaQc, 5.5)
        )
        depthLine = String(format: "Transition Depth: %.1f m to %.1f m", stats.topDepthM, stats.bottomDepthM)
      }

      builtConcerns.append(
        GeotechnicalConcernItem(
          id: "dipping-hard-stratum",
          title: "High Soil Stiffness Contrast / Variable Bearing Depth",
          implication: implication,
          locationAndDepthLines: [
            "\(stats.sectorName) (E: \(stats.minEM)–\(stats.maxEM) m, N: \(stats.minNM)–\(stats.maxNM) m)",
            depthLine
          ],
          affectedVoxels: contrastVoxels
        )
      )
    }

    geotechnicalConcerns = builtConcerns
    if let selectedConcernID, !builtConcerns.contains(where: { $0.id == selectedConcernID }) {
      self.selectedConcernID = nil
    }
  }

  private func computeClusterStats(for coords: Set<GridCoord>) -> (
    sectorName: String,
    minEM: Int,
    maxEM: Int,
    minNM: Int,
    maxNM: Int,
    topDepthM: Double,
    bottomDepthM: Double,
    thicknessM: Double
  ) {
    var minX = Int.max
    var maxX = Int.min
    var minZ = Int.max
    var maxZ = Int.min
    var sumX = 0.0
    var sumZ = 0.0
    var topDepth = Double.greatestFiniteMagnitude
    var bottomDepth = 0.0

    for c in coords {
      minX = min(minX, c.x)
      maxX = max(maxX, c.x)
      minZ = min(minZ, c.z)
      maxZ = max(maxZ, c.z)
      sumX += Double(c.x)
      sumZ += Double(c.z)
      if let v = volume.voxels[c] {
        topDepth = min(topDepth, Double(v.topDepthM))
        bottomDepth = max(bottomDepth, Double(v.bottomDepthM))
      }
    }

    let count = max(Double(coords.count), 1.0)
    let meanXRatio = (sumX / count) / Double(max(volume.nx - 1, 1))
    // Note: z == 0 is North, z == nz - 1 is South, so North ratio is 1.0 - (z / (nz - 1))
    let meanNRatio = 1.0 - ((sumZ / count) / Double(max(volume.nz - 1, 1)))

    let ewLabel: String = if meanXRatio < 0.38 {
      "West"
    } else if meanXRatio > 0.62 {
      "East"
    } else {
      "Central"
    }

    let nsLabel: String = if meanNRatio < 0.38 {
      "South"
    } else if meanNRatio > 0.62 {
      "North"
    } else {
      "Central"
    }

    let sectorName: String
    if nsLabel == "Central" && ewLabel == "Central" {
      sectorName = "Central Sector"
    } else if nsLabel == "Central" {
      sectorName = "\(ewLabel)ern & Central Sector"
    } else if ewLabel == "Central" {
      sectorName = "\(nsLabel)ern & Central Sector"
    } else {
      sectorName = "\(nsLabel)\(ewLabel.lowercased()) Quadrant"
    }

    let stepE = Double(volume.cellStepXM)
    let stepN = Double(volume.cellStepZM)
    let minEM = Int((Double(minX) * stepE).rounded())
    let maxEM = max(Int((Double(maxX + 1) * stepE).rounded()), minEM + 1)
    let minNIdx = max(volume.nz - 1 - maxZ, 0)
    let maxNIdx = max(volume.nz - minZ, minNIdx + 1)
    let minNM = Int((Double(minNIdx) * stepN).rounded())
    let maxNM = max(Int((Double(maxNIdx) * stepN).rounded()), minNM + 1)

    let safeTop = topDepth.isFinite ? topDepth : 0.0
    let safeBot = max(bottomDepth, safeTop + Double(volume.cellStepYM))
    return (
      sectorName: sectorName,
      minEM: minEM,
      maxEM: maxEM,
      minNM: minNM,
      maxNM: maxNM,
      topDepthM: safeTop,
      bottomDepthM: safeBot,
      thicknessM: max(safeBot - safeTop, Double(volume.cellStepYM))
    )
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
