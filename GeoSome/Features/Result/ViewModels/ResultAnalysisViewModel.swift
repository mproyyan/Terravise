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
  static let defaultCameraZoom: Float = 1.35

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

  // Real-time Cross-Section Slicing Controls (in meters)
  var slicingXMeters: Double
  var slicingYMeters: Double
  var isSlicingCardExpanded: Bool = true

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
  var shallowestBearingDepthText: String = "2.7 m"
  var deepestBearingDepthText: String = "4.9 m"
  var variationBearingDepthText: String = "2.2 m"
  var coneResistanceCriteriaText: String = "≥ 15.0 MPa"
  var soilBehaviorIndexCriteriaText: String = "≤ 1.80"
  var minLayerThicknessCriteriaText: String = "≥ 1.0 m"
  var relativeUncertaintyText: String = "± 12%"
  var highUncertaintyAreaPercentText: String = "10%"
  var highUncertaintyDescription: String =
    "High uncertainty is concentrated in the southern sector, where CPT coverage is limited."

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
      cptPoints: resolvedProject.cptPoints
    )
    self.volume = builtVolume
    self.slicingXMeters = Double(builtVolume.widthXM)
    self.slicingYMeters = Double(builtVolume.lengthZM)

    if let rec = resolvedProject.latestRecommendation {
      let uncertainty = max(1, 100 - rec.confidenceLevel)
      self.predictionUncertaintyPercent = uncertainty
      self.relativeUncertaintyText = "± \(uncertainty)%"
    }
    if !resolvedProject.cptPoints.isEmpty {
      updateBearingSummaryMetrics(from: builtVolume)
    }
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
      cptPoints: newProject.cptPoints
    )
    volume = builtVolume
    slicingXMeters = Double(builtVolume.widthXM)
    slicingYMeters = Double(builtVolume.lengthZM)
    selectedVoxel = nil

    if let rec = newProject.latestRecommendation {
      let uncertainty = max(1, 100 - rec.confidenceLevel)
      predictionUncertaintyPercent = uncertainty
      relativeUncertaintyText = "± \(uncertainty)%"
    }
    if !newProject.cptPoints.isEmpty {
      updateBearingSummaryMetrics(from: builtVolume)
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
    isProfilePopoverPresented = false
    isLeftSheetPresented = true
    selectedSheetDetent = .large
    AccessibilityCaptionCenter.shared.announce("\(tab.rawValue) selected.")
  }

  func resetView() {
    slicingXMeters = maxSlicingXMeters
    slicingYMeters = maxSlicingYMeters
    cameraYaw = Self.defaultCameraYaw
    cameraPitch = Self.defaultCameraPitch
    cameraZoom = Self.defaultCameraZoom
    bearingCameraYaw = Self.defaultBearingCameraYaw
    bearingCameraPitch = Self.defaultBearingCameraPitch
    bearingCameraZoom = Self.defaultBearingCameraZoom
    selectedVoxel = nil
    selectedPipePosition3D = nil
    isProfilePopoverPresented = false
    selectedSheetDetent = Self.collapsedSheetDetent
    AccessibilityCaptionCenter.shared.announce("3D view and slicing reset.")
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

  private func updateBearingSummaryMetrics(from volume: SubsurfaceVoxelVolume) {
    let depths = volume.bearingVoxels.values.map(\.bearingDepthM)
    guard let minDepth = depths.min(), let maxDepth = depths.max() else { return }
    let variation = max(maxDepth - minDepth, 0.0)
    shallowestBearingDepthText = String(format: "%.1f m", minDepth)
    deepestBearingDepthText = String(format: "%.1f m", maxDepth)
    variationBearingDepthText = String(format: "%.1f m", variation)
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
