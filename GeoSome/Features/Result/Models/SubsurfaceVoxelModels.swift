import CoreLocation
import Foundation
import simd
import UIKit

/// Discrete 3D integer coordinate in the 1m² horizontal × vertical depth voxel grid.
/// - `x`: Easting grid index (1.0 m step)
/// - `y`: Vertical layer/depth index from bottom (`0` = deepest bedrock) to top (`maxY` = surface `Y = 0`)
/// - `z`: Northing grid index (1.0 m step)
nonisolated struct GridCoord: Hashable, Sendable {
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

/// Data item for compared bearing layer points displayed in Compare Data sheet and on 3D surface.
struct ComparedBearingPointItem: Identifiable, Equatable, Sendable {
  let id: UUID
  var label: String
  var title: String
  var depthText: String
  var depthValueM: Float
  var northingText: String
  var eastingText: String
  var gridX: Int
  var gridZ: Int
  var worldX: Float
  var worldZ: Float
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
  /// Local 3D positions of uploaded CPT boreholes on the top surface (`Y = 0`) in grid units (used by Bearing Layer).
  let cptSurfacePositions: [SIMD3<Float>]
  /// True metric 3D positions (`1 unit = 1 meter`) of CPT boreholes on the top surface (`Y = 0`).
  var cptMetricSurfacePositions: [SIMD3<Float>] = []
  /// Geographic bounding box of the site polygon for continuous lat/lon unprojection.
  var minLatitude: Double = -6.2430
  var maxLatitude: Double = -6.2405
  var minLongitude: Double = 106.8295
  var maxLongitude: Double = 106.8330
  /// Normalized `[0, 1] x [0, 1]` UV coordinates of the user-drawn boundary polygon vertices (`u`: West->East, `v`: North->South).
  var boundaryPolygonUV: [SIMD2<Float>] = [
    SIMD2<Float>(0, 0),
    SIMD2<Float>(1, 0),
    SIMD2<Float>(1, 1),
    SIMD2<Float>(0, 1)
  ]
  /// Normalized `[0, 1] x [0, 1]` UV coordinates of CPT points inside the boundary polygon.
  var cptNormalizedUVs: [SIMD2<Float>] = []
  /// True if at least one measured CPT sounding borehole is present in the volume.
  var hasMeasuredCPTData: Bool = false

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

  /// Converts a discrete grid coordinate `(x, y, z)` to grid-unit world space (used by Bearing Layer).
  func worldPosition(for coord: GridCoord) -> SIMD3<Float> {
    let wx = Float(coord.x) - centerX
    let wy = Float(coord.y) - Float(ny - 1) - 0.5
    let wz = Float(coord.z) - centerZ
    return SIMD3<Float>(wx, wy, wz)
  }

  /// Converts a discrete grid coordinate `(x, y, z)` to true metric 3D world space (`1 unit = 1 meter`),
  /// centered horizontally at `(0, 0)` with top surface at `Y = 0` and bottom at `Y = -depthYM`.
  func metricWorldPosition(for coord: GridCoord) -> SIMD3<Float> {
    let wx = (Float(coord.x) - centerX) * cellStepXM
    let wy = (Float(coord.y) - Float(ny - 1) - 0.5) * cellStepYM
    let wz = (Float(coord.z) - centerZ) * cellStepZM
    return SIMD3<Float>(wx, wy, wz)
  }

  /// Converts a metric horizontal location `(xM, zM)` (in meters from center) to continuous fractional
  /// grid coordinates `(fx, fz)` in `[0, nx - 1] × [0, nz - 1]`.
  func continuousGridCoordinates(forMetricX xM: Float, zM: Float) -> (fx: Float, fz: Float) {
    let safeStepX = max(cellStepXM, 1e-4)
    let safeStepZ = max(cellStepZM, 1e-4)
    let rawFX = (xM / safeStepX) + centerX
    let rawFZ = (zM / safeStepZ) + centerZ
    let fx = min(max(rawFX, 0.0), Float(max(nx - 1, 0)))
    let fz = min(max(rawFZ, 0.0), Float(max(nz - 1, 0)))
    return (fx, fz)
  }

  /// Converts an exact metric location `(xM, zM)` on the `Y = 0` surface into geographic `(latitude, longitude)`.
  func geographicCoordinate(forMetricX xM: Float, zM: Float) -> (latitude: Double, longitude: Double) {
    let (fx, fz) = continuousGridCoordinates(forMetricX: xM, zM: zM)
    let u = Double(fx) / Double(max(nx - 1, 1))
    let v = Double(fz) / Double(max(nz - 1, 1))
    let lon = minLongitude + u * (maxLongitude - minLongitude)
    let lat = maxLatitude - v * (maxLatitude - minLatitude)
    return (latitude: lat, longitude: lon)
  }

  /// Exact inverse of `geographicCoordinate(forMetricX:zM:)` in `Double` precision:
  /// converts a geographic `(latitude, longitude)` into local metric coordinates `(xM, zM)` in meters
  /// where `+X` is East and `+Z` is South (`-Z` is North).
  func metricPoint(for coordinate: CLLocationCoordinate2D) -> SIMD2<Double> {
    let lonSpan = max(maxLongitude - minLongitude, 1e-12)
    let latSpan = max(maxLatitude - minLatitude, 1e-12)
    let u = (coordinate.longitude - minLongitude) / lonSpan
    let v = (maxLatitude - coordinate.latitude) / latSpan
    let xM = (u - 0.5) * Double(widthXM)
    let zM = (v - 0.5) * Double(lengthZM)
    return SIMD2<Double>(xM, zM)
  }

  /// Returns `true` if the metric horizontal coordinate `(xM, zM)` lies strictly inside the drawn site
  /// boundary polygon AND within an active, non-sliced 3D voxel column (`0 ... maxSliceX`, `0 ... maxSliceZ`).
  func isMetricPointInsideActiveArea(
    xM: Float,
    zM: Float,
    maxSliceX: Int? = nil,
    maxSliceZ: Int? = nil
  ) -> Bool {
    let safeStepX = max(cellStepXM, 1e-4)
    let safeStepZ = max(cellStepZM, 1e-4)
    let rawFX = (xM / safeStepX) + centerX
    let rawFZ = (zM / safeStepZ) + centerZ

    let limitX = min(maxSliceX ?? (nx - 1), nx - 1)
    let limitZ = min(maxSliceZ ?? (nz - 1), nz - 1)

    guard rawFX >= -0.5, rawFX <= Float(limitX) + 0.5,
          rawFZ >= -0.5, rawFZ <= Float(limitZ) + 0.5
    else {
      return false
    }

    let xGrid = min(max(Int(rawFX.rounded()), 0), nx - 1)
    let zGrid = min(max(Int(rawFZ.rounded()), 0), nz - 1)
    guard xGrid <= limitX,
          zGrid <= limitZ,
          voxels[GridCoord(x: xGrid, y: ny - 1, z: zGrid)] != nil
    else {
      return false
    }

    // Verify exact point-in-polygon against the user-drawn boundary in normalized UV space [0, 1]
    if boundaryPolygonUV.count >= 3 {
      let u = (xM / max(widthXM, 1e-4)) + 0.5
      let v = (zM / max(lengthZM, 1e-4)) + 0.5
      guard u >= 0.0, u <= 1.0, v >= 0.0, v <= 1.0 else {
        return false
      }
      var inside = false
      var j = boundaryPolygonUV.count - 1
      for i in 0 ..< boundaryPolygonUV.count {
        let xi = boundaryPolygonUV[i].x, yi = boundaryPolygonUV[i].y
        let xj = boundaryPolygonUV[j].x, yj = boundaryPolygonUV[j].y
        let denom = (yj - yi) == 0 ? 1e-7 : (yj - yi)
        let intersect = ((yi > v) != (yj > v)) && (u < (xj - xi) * (v - yi) / denom + xi)
        if intersect {
          inside.toggle()
        }
        j = i
      }
      if !inside {
        return false
      }
    }

    return true
  }

  /// Bilinearly interpolates the continuous Robertson `Ic` value at exact metric coordinates `(metricX, metricZ)`
  /// for a given vertical layer `iy` (`0` = deepest, `ny - 1` = surface).
  func sampleBilinearIc(metricX: Float, metricZ: Float, iy: Int) -> Float? {
    let clampedY = min(max(iy, 0), ny - 1)
    let (fx, fz) = continuousGridCoordinates(forMetricX: metricX, zM: metricZ)

    let x0 = min(max(Int(floor(fx)), 0), nx - 1)
    let x1 = min(x0 + 1, nx - 1)
    let tx = fx - Float(x0)

    let z0 = min(max(Int(floor(fz)), 0), nz - 1)
    let z1 = min(z0 + 1, nz - 1)
    let tz = fz - Float(z0)

    let corners: [(x: Int, z: Int, weight: Float)] = [
      (x0, z0, (1.0 - tx) * (1.0 - tz)),
      (x1, z0, tx * (1.0 - tz)),
      (x0, z1, (1.0 - tx) * tz),
      (x1, z1, tx * tz)
    ]

    var weightedSum: Float = 0.0
    var weightTotal: Float = 0.0

    for c in corners where c.weight > 0 {
      if let v = voxels[GridCoord(x: c.x, y: clampedY, z: c.z)] {
        weightedSum += c.weight * v.robertsonIc
        weightTotal += c.weight
      }
    }

    if weightTotal > 1e-5 {
      return weightedSum / weightTotal
    }

    // Fallback to nearest active column if right on an irregular polygon boundary edge
    let nearestX = min(max(Int(fx.rounded()), 0), nx - 1)
    let nearestZ = min(max(Int(fz.rounded()), 0), nz - 1)
    if let direct = voxels[GridCoord(x: nearestX, y: clampedY, z: nearestZ)] {
      return direct.robertsonIc
    }

    // Expanding radius search for the closest active voxel at this depth layer
    for r in 1...8 {
      for dx in -r...r {
        for dz in -r...r {
          if abs(dx) != r && abs(dz) != r { continue }
          let qx = nearestX + dx
          let qz = nearestZ + dz
          guard qx >= 0, qx < nx, qz >= 0, qz < nz else { continue }
          if let v = voxels[GridCoord(x: qx, y: clampedY, z: qz)] {
            return v.robertsonIc
          }
        }
      }
    }

    return nil
  }

  /// Samples a continuous bilinearly + vertically interpolated Robertson `Ic` profile at `(metricX, metricZ)`.
  /// Returns `(topDepthM, bottomDepthM, icValue, soilType)` slices across the full depth `depthYM`.
  func sampleInterpolatedStratigraphy(
    metricX: Float,
    metricZ: Float,
    verticalSubdivisions: Int = 40
  ) -> [(topDepthM: Double, bottomDepthM: Double, ic: Float, soilType: SoilLayerType)] {
    let steps = max(verticalSubdivisions, ny)
    var rawLayerIcs: [Float] = []
    rawLayerIcs.reserveCapacity(ny)

    // Ordered from top surface (depthIndexFromTop = 0, iy = ny - 1) to bottom (iy = 0)
    for depthIdx in 0 ..< ny {
      let iy = (ny - 1) - depthIdx
      if let ic = sampleBilinearIc(metricX: metricX, metricZ: metricZ, iy: iy) {
        rawLayerIcs.append(ic)
      }
    }

    guard !rawLayerIcs.isEmpty else { return [] }
    let count = rawLayerIcs.count
    let sliceStepM = Double(depthYM) / Double(steps)

    var result: [(topDepthM: Double, bottomDepthM: Double, ic: Float, soilType: SoilLayerType)] = []
    result.reserveCapacity(steps)

    for s in 0 ..< steps {
      let normDepth = (Double(s) + 0.5) / Double(steps)
      let continuousLayerPos = Float(normDepth) * Float(max(count - 1, 0))
      let i0 = min(max(Int(floor(continuousLayerPos)), 0), count - 1)
      let i1 = min(i0 + 1, count - 1)
      let ty = continuousLayerPos - Float(i0)

      let interpolatedIc = rawLayerIcs[i0] * (1.0 - ty) + rawLayerIcs[i1] * ty
      let soilType = SoilLayerType.fromRobertsonIc(Double(interpolatedIc), depthRatio: normDepth)
      let topM = Double(s) * sliceStepM
      let botM = Double(s + 1) * sliceStepM
      result.append((topDepthM: topM, bottomDepthM: botM, ic: interpolatedIc, soilType: soilType))
    }

    return result
  }
}
