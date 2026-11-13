import CoreLocation
import Foundation
import simd
import UIKit

/// Discrete 3D integer coordinate in the 1m² horizontal × vertical depth voxel grid.
/// - `x`: Easting grid index (1.0 m step)
/// - `y`: Vertical layer/depth index from bottom (`0` = deepest bedrock) to top (`maxY` = surface `Y = 0`)
/// - `z`: Northing grid index (1.0 m step)
struct GridCoord: Hashable, Sendable {
  let x: Int
  let y: Int
  let z: Int
}

/// 2D horizontal column coordinate `(x, z)` on the 1.0 m grid.
struct ColumnCoord: Hashable, Sendable {
  let x: Int
  let z: Int
}

/// Top-right mode switcher tabs on the Result Analysis screen.
enum ResultAnalysisTab: String, CaseIterable, Identifiable, Sendable {
  case threeDLayer = "3D Layer"
  case bearingLayer = "Bearing Layer"

  var id: String { rawValue }

  var iconName: String {
    switch self {
    case .threeDLayer:
      "cube.transparent.fill"
    case .bearingLayer:
      "map.fill"
    }
  }
}

/// Robertson Soil Behavior Type (SBT) / Stratified Geotechnical Layer Classification.
/// Matches the 9-zone geotechnical palette used in the 3D subsurface visualization.
enum SoilLayerType: Int, CaseIterable, Sendable {
  case sensitiveFineGrained = 0
  case organicClay = 1
  case clayToSiltyClay = 2
  case siltMixtures = 3
  case sandMixtures = 4
  case cleanSands = 5
  case denseSandToGravelly = 6
  case stiffSandToClayey = 7
  case stiffFineGrained = 8

  var displayName: String {
    switch self {
    case .sensitiveFineGrained:
      "Sensitive fine-grained soil"
    case .organicClay:
      "Clay - organic soil"
    case .clayToSiltyClay:
      "Clays: clay to silty clay"
    case .siltMixtures:
      "Silt mixtures: clayey silt & silty clay"
    case .sandMixtures:
      "Sand mixtures: silty sand to sandy silt"
    case .cleanSands:
      "Sands: clean sands to silty sands"
    case .denseSandToGravelly:
      "Dense sand to gravelly sand"
    case .stiffSandToClayey:
      "Stiff sand to clayey sand"
    case .stiffFineGrained:
      "Stiff fine grained"
    }
  }

  /// Earth-tone geotechnical color matching the reference 3D stratigraphy rendering.
  var uiColor: UIColor {
    switch self {
    case .sensitiveFineGrained:
      UIColor(red: 0.44, green: 0.23, blue: 0.17, alpha: 1.0)
    case .organicClay:
      UIColor(red: 0.65, green: 0.35, blue: 0.22, alpha: 1.0)
    case .clayToSiltyClay:
      UIColor(red: 0.56, green: 0.43, blue: 0.35, alpha: 1.0)
    case .siltMixtures:
      UIColor(red: 0.50, green: 0.52, blue: 0.43, alpha: 1.0)
    case .sandMixtures:
      UIColor(red: 0.84, green: 0.67, blue: 0.46, alpha: 1.0)
    case .cleanSands:
      UIColor(red: 0.78, green: 0.54, blue: 0.30, alpha: 1.0)
    case .denseSandToGravelly:
      UIColor(red: 0.60, green: 0.50, blue: 0.42, alpha: 1.0)
    case .stiffSandToClayey:
      UIColor(red: 0.52, green: 0.46, blue: 0.44, alpha: 1.0)
    case .stiffFineGrained:
      UIColor(red: 0.72, green: 0.65, blue: 0.62, alpha: 1.0)
    }
  }

  var typicalMoisturePercent: Float {
    switch self {
    case .sensitiveFineGrained: 44.0
    case .organicClay: 52.0
    case .clayToSiltyClay: 38.0
    case .siltMixtures: 31.0
    case .sandMixtures: 24.0
    case .cleanSands: 18.0
    case .denseSandToGravelly: 14.0
    case .stiffSandToClayey: 20.0
    case .stiffFineGrained: 26.0
    }
  }

  var typicalBearingCapacityKPa: Float {
    switch self {
    case .sensitiveFineGrained: 55.0
    case .organicClay: 45.0
    case .clayToSiltyClay: 95.0
    case .siltMixtures: 135.0
    case .sandMixtures: 190.0
    case .cleanSands: 260.0
    case .denseSandToGravelly: 420.0
    case .stiffSandToClayey: 310.0
    case .stiffFineGrained: 240.0
    }
  }

  static func fromRobertsonIc(_ ic: Double, depthRatio: Double) -> SoilLayerType {
    switch ic {
    case 3.60...:
      return depthRatio < 0.25 ? .sensitiveFineGrained : .organicClay
    case 3.20 ..< 3.60:
      return .organicClay
    case 2.95 ..< 3.20:
      return depthRatio > 0.75 ? .stiffFineGrained : .clayToSiltyClay
    case 2.60 ..< 2.95:
      return .siltMixtures
    case 2.30 ..< 2.60:
      return .sandMixtures
    case 2.05 ..< 2.30:
      return depthRatio > 0.70 ? .stiffSandToClayey : .cleanSands
    case 1.65 ..< 2.05:
      return .cleanSands
    default:
      return .denseSandToGravelly
    }
  }
}

/// Pure domain data model for a single 1m² × Δz geotechnical voxel.
/// Stored in `[GridCoord: SoilVoxel]` without instantiating per-voxel RealityKit entities.
struct SoilVoxel: Sendable, Equatable {
  let coord: GridCoord
  let latitude: Double
  let longitude: Double
  let topDepthM: Float
  let bottomDepthM: Float
  /// Stratified layer index from `0` (surface layer) downward to `numLayers - 1` (deepest bedrock).
  let layerIdx: Int
  let soilClassification: SoilLayerType
  let robertsonIc: Float
  let moisturePercent: Float
  let bearingCapacityKPa: Float
  /// Predicted bearing-layer depth (m) for this 1m² horizontal column `(coord.x, coord.z)`.
  var bearingLayerDepthM: Float = 3.5

  var materialIndex: UInt32 {
    UInt32(soilClassification.rawValue)
  }
}

/// Pure domain data model for a single 1m² horizontal voxel on the Bearing Layer Depth Map.
/// Stored in `[ColumnCoord: BearingLayerVoxel]` inside `SubsurfaceVoxelVolume`.
struct BearingLayerVoxel: Sendable, Equatable {
  let coord: ColumnCoord
  let latitude: Double
  let longitude: Double
  /// Predicted depth (m) to the competent bearing layer at this 1m² cell (e.g., 2.7m ... 4.9m).
  let bearingDepthM: Float
  /// Normalized depth value in `[0, 1]` (`0` = shallowest ≤ 2.75m, `1` = deepest ≥ 4.75m).
  let normalizedDepthRatio: Float
  /// Predicted Cone Resistance `qc` (MPa) at the bearing horizon (`>= 15.0 MPa`).
  let coneResistanceMPa: Float
  /// Predicted Soil Behavior Index `Ic` at the bearing horizon (`<= 1.80`).
  let soilBehaviorIndexIc: Float
  /// Continuous competent layer thickness (m) (`>= 1.0 m`).
  let layerThicknessM: Float
  /// Relative prediction uncertainty (%) at this 1m² cell.
  let uncertaintyPercent: Float
}

/// Spatial metadata and sparse storage for the 3D subsurface voxel field.
struct SubsurfaceVoxelVolume: Sendable {
  let id: UUID = UUID()
  /// Pure sparse hash map storing every active 1m² voxel (`[GridCoord: SoilVoxel]`).
  let voxels: [GridCoord: SoilVoxel]
  /// Pure sparse hash map storing the bearing-layer data for every active 1m² horizontal column (`[ColumnCoord: BearingLayerVoxel]`).
  var bearingVoxels: [ColumnCoord: BearingLayerVoxel] = [:]
  /// Fast flat array indexed by `(x * nz * ny) + (z * ny) + y` storing material index (`-1` if inactive).
  let flatMaterialGrid: [Int16]
  /// Grid dimensions: `nx` (X / Easting), `ny` (Y / vertical layers), `nz` (Z / Northing).
  let nx: Int
  let ny: Int
  let nz: Int
  /// Physical dimensions of the bounding box in meters.
  let widthXM: Float
  let depthYM: Float
  let lengthZM: Float
  /// Physical step size per grid cell (1.0 m horizontal grid spacing, vertical step `dzM`).
  let cellStepXM: Float
  let cellStepYM: Float
  let cellStepZM: Float
  /// Center offsets used for centering the volume around the scene origin `(0, 0, 0)` with top plane at `Y = 0`.
  let centerX: Float
  let centerZ: Float
  /// Local 3D positions of uploaded CPT boreholes on the top surface (`Y = 0`).
  let cptSurfacePositions: [SIMD3<Float>]
  /// Normalized `[0, 1] x [0, 1]` UV coordinates of the user-drawn boundary polygon vertices (`u`: West->East, `v`: North->South).
  var boundaryPolygonUV: [SIMD2<Float>] = [
    SIMD2<Float>(0, 0),
    SIMD2<Float>(1, 0),
    SIMD2<Float>(1, 1),
    SIMD2<Float>(0, 1)
  ]
  /// Normalized `[0, 1] x [0, 1]` UV coordinates of CPT points inside the boundary polygon.
  var cptNormalizedUVs: [SIMD2<Float>] = []

  @inline(__always)
  func flatIndex(x: Int, y: Int, z: Int) -> Int {
    (x * nz * ny) + (z * ny) + y
  }

  @inline(__always)
  func materialAt(x: Int, y: Int, z: Int, maxSliceX: Int, maxSliceZ: Int) -> Int16 {
    guard x >= 0, x <= maxSliceX, x < nx,
          y >= 0, y < ny,
          z >= 0, z <= maxSliceZ, z < nz
    else {
      return -1
    }
    return flatMaterialGrid[(x * nz * ny) + (z * ny) + y]
  }

  /// Converts a discrete grid coordinate `(x, y, z)` to local 3D world space where:
  /// - Voxel half-extent is `0.5` on the 1.0 m grid.
  /// - Top surface plane (`y == ny - 1` top face) lies exactly at `Y = 0`.
  func worldPosition(for coord: GridCoord) -> SIMD3<Float> {
    let wx = Float(coord.x) - centerX
    let wy = Float(coord.y) - Float(ny - 1) - 0.5
    let wz = Float(coord.z) - centerZ
    return SIMD3<Float>(wx, wy, wz)
  }
}
