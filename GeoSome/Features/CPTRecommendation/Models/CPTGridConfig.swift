import CoreLocation
import Foundation

/// Persisted per project. Existing projects decode as legacy to preserve their grid and DQN results.
enum CPTGridPolicy: String, Codable, Hashable, Sendable {
  case legacyDynamic
  case qcfsV3Enumerated
}

struct CPTGridConfig: Sendable {
  let nx: Int
  let ny: Int
  let nz: Int
  let dxM: Double
  let dyM: Double
  let dzM: Double

  let originLatitude: Double
  let originLongitude: Double
  let metersPerDegreeLat: Double
  let metersPerDegreeLon: Double

  let siteWidthM: Double
  let siteHeightM: Double
  let siteDiagonalM: Double
  let siteAreaM2: Double
  let aspectRatio: Double

  /// 2D boolean mask [nx][ny] indicating whether cell center (x, y) is inside the project boundary polygon.
  let validXYMask: [[Bool]]

  /// Physical voxel centers are (ix*dxM, iy*dyM, iz*dzM) from the southwest
  /// geographic origin; X increases east, Y north, and Z is depth downward.
  var centerExtentXM: Double { Double(nx - 1) * dxM }
  var centerExtentYM: Double { Double(ny - 1) * dyM }
  var centerExtentDepthM: Double { Double(nz - 1) * dzM }

  static let qcfsShapes: [(nx: Int, ny: Int, nz: Int)] = [
    (24, 24, 12), (32, 32, 16), (40, 40, 24), (48, 32, 20)
  ]

  var isQCFSV3Shape: Bool {
    Self.qcfsShapes.contains { $0.nx == nx && $0.ny == ny && $0.nz == nz }
  }

  func hasSamePhysicalGrid(as other: CPTGridConfig) -> Bool {
    nx == other.nx && ny == other.ny && nz == other.nz &&
    abs(dxM - other.dxM) < 1e-9 && abs(dyM - other.dyM) < 1e-9 && abs(dzM - other.dzM) < 1e-9 &&
    abs(originLatitude - other.originLatitude) < 1e-12 &&
    abs(originLongitude - other.originLongitude) < 1e-12 &&
    validXYMask == other.validXYMask
  }

  /// Selects the enumerated model shape nearest the existing dynamic grid in
  /// relative cell counts. This changes sampling density, not polygon, origin,
  /// CPT coordinates, or depth data. Ties prefer fewer voxels.
  static func qcfsShape(near nx: Int, _ ny: Int, _ nz: Int) -> (nx: Int, ny: Int, nz: Int) {
    qcfsShapes.min { lhs, rhs in
      func score(_ s: (nx: Int, ny: Int, nz: Int)) -> Double {
        pow(log(Double(s.nx) / Double(nx)), 2) +
        pow(log(Double(s.ny) / Double(ny)), 2) +
        pow(log(Double(s.nz) / Double(nz)), 2)
      }
      let a = score(lhs), b = score(rhs)
      return abs(a - b) > 1e-12 ? a < b : lhs.nx * lhs.ny * lhs.nz < rhs.nx * rhs.ny * rhs.nz
    }!
  }

  static func build(
    boundaryCoordinates: [CLLocationCoordinate2D],
    cptPoints: [CPTPointEntry],
    policy: CPTGridPolicy = .legacyDynamic
  ) -> CPTGridConfig {
    let polygon = boundaryCoordinates.count >= 3
      ? boundaryCoordinates
      : CPTRecommendationViewModel.defaultSamplePoints.map(\.coordinate)

    var minLat = polygon[0].latitude
    var maxLat = polygon[0].latitude
    var minLon = polygon[0].longitude
    var maxLon = polygon[0].longitude

    for coord in polygon {
      minLat = min(minLat, coord.latitude)
      maxLat = max(maxLat, coord.latitude)
      minLon = min(minLon, coord.longitude)
      maxLon = max(maxLon, coord.longitude)
    }

    // Ensure uploaded CPT points are also within the bounding box
    for point in cptPoints {
      minLat = min(minLat, point.coordinate.latitude)
      maxLat = max(maxLat, point.coordinate.latitude)
      minLon = min(minLon, point.coordinate.longitude)
      maxLon = max(maxLon, point.coordinate.longitude)
    }

    let meanLatRad = ((minLat + maxLat) * 0.5) * .pi / 180.0
    let mPerDegLat = 111_132.92 - 559.82 * cos(2.0 * meanLatRad) + 1.175 * cos(4.0 * meanLatRad)
    let mPerDegLon = max(111_412.84 * cos(meanLatRad) - 93.5 * cos(3.0 * meanLatRad), 1.0)

    let rawWidthM = max((maxLon - minLon) * mPerDegLon, 24.0)
    let rawHeightM = max((maxLat - minLat) * mPerDegLat, 24.0)

    // Choose nx, ny in [24, 36] preserving aspect ratio (CoreML range is 16...96, DQN max candidates 4096)
    let ratio = rawWidthM / max(rawHeightM, 1.0)
    let baseCells = 24
    let nx: Int
    let ny: Int
    if ratio >= 1.0 {
      ny = baseCells
      nx = min(max(Int((Double(baseCells) * ratio).rounded()), 24), 36)
    } else {
      nx = baseCells
      ny = min(max(Int((Double(baseCells) / max(ratio, 0.25)).rounded()), 24), 36)
    }

    // Determine vertical grid (nz in 12...24, CoreML range is 8...32)
    let maxObservedDepth = cptPoints
      .flatMap(\.rows)
      .map(\.depth)
      .max() ?? 12.0
    let targetDepth = max(maxObservedDepth, 11.0)

    let dzM: Double
    if targetDepth <= 11.5 {
      dzM = 0.5
    } else if targetDepth <= 23.0 {
      dzM = 1.0
    } else {
      dzM = ceil(targetDepth / 20.0)
    }
    let rawNz = Int(ceil(targetDepth / dzM)) + 1
    let legacyNz = min(max(rawNz, 12), 24)
    let selected = policy == .qcfsV3Enumerated ? qcfsShape(near: nx, ny, legacyNz) : (nx, ny, legacyNz)
    let finalNx = selected.0, finalNy = selected.1, nz = selected.2
    // Keep the deepest measured CPT within the selected vertical center range.
    let finalDzM = policy == .legacyDynamic ? dzM : max(dzM, targetDepth / Double(nz - 1))
    let dxM = policy == .legacyDynamic
      ? max(rawWidthM / Double(max(finalNx - 1, 1)), 1.0)
      : max((maxLon - minLon) * mPerDegLon / Double(finalNx - 1), 1e-6)
    let dyM = policy == .legacyDynamic
      ? max(rawHeightM / Double(max(finalNy - 1, 1)), 1.0)
      : max((maxLat - minLat) * mPerDegLat / Double(finalNy - 1), 1e-6)

    // Project polygon vertices to local meters
    let polyXY: [(x: Double, y: Double)] = polygon.map { coord in
      let x = (coord.longitude - minLon) * mPerDegLon
      let y = (coord.latitude - minLat) * mPerDegLat
      return (x, y)
    }

    // Compute polygon area via shoelace formula
    var shoelace = 0.0
    for i in polyXY.indices {
      let p1 = polyXY[i]
      let p2 = polyXY[(i + 1) % polyXY.count]
      shoelace += (p1.x * p2.y) - (p2.x * p1.y)
    }
    let polygonAreaM2 = max(abs(shoelace) * 0.5, rawWidthM * rawHeightM * 0.5)

    // Build 2D valid mask inside polygon
    var mask2D = Array(repeating: Array(repeating: false, count: finalNy), count: finalNx)
    var validCount = 0
    for ix in 0 ..< finalNx {
      let x = Double(ix) * dxM
      for iy in 0 ..< finalNy {
        let y = Double(iy) * dyM
        if isPointInPolygon(x: x, y: y, polygon: polyXY) {
          mask2D[ix][iy] = true
          validCount += 1
        }
      }
    }

    // Fallback if polygon is very narrow ordegenerate
    if validCount < 4, policy == .legacyDynamic {
      for ix in 0 ..< finalNx {
        for iy in 0 ..< finalNy {
          mask2D[ix][iy] = true
        }
      }
    }

    let extentX = Double(finalNx) * dxM
    let extentY = Double(finalNy) * dyM
    let diagonal = hypot(extentX, extentY)
    let aspect = max(extentX, extentY) / max(min(extentX, extentY), 1.0)

    return CPTGridConfig(
      nx: finalNx,
      ny: finalNy,
      nz: nz,
      dxM: dxM,
      dyM: dyM,
      dzM: finalDzM,
      originLatitude: minLat,
      originLongitude: minLon,
      metersPerDegreeLat: mPerDegLat,
      metersPerDegreeLon: mPerDegLon,
      siteWidthM: extentX,
      siteHeightM: extentY,
      siteDiagonalM: diagonal,
      siteAreaM2: polygonAreaM2,
      aspectRatio: aspect,
      validXYMask: mask2D
    )
  }

  func xyMeters(for coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double) {
    let x = (coordinate.longitude - originLongitude) * metersPerDegreeLon
    let y = (coordinate.latitude - originLatitude) * metersPerDegreeLat
    return (x, y)
  }

  func xyMeters(ix: Int, iy: Int) -> (x: Double, y: Double) {
    (Double(ix) * dxM, Double(iy) * dyM)
  }

  func coordinate(ix: Int, iy: Int) -> CLLocationCoordinate2D {
    let x = Double(ix) * dxM
    let y = Double(iy) * dyM
    let lon = originLongitude + (x / metersPerDegreeLon)
    let lat = originLatitude + (y / metersPerDegreeLat)
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }

  func gridIndices(for coordinate: CLLocationCoordinate2D) -> (ix: Int, iy: Int) {
    let (x, y) = xyMeters(for: coordinate)
    let ix = min(max(Int((x / dxM).rounded()), 0), nx - 1)
    let iy = min(max(Int((y / dyM).rounded()), 0), ny - 1)
    return (ix, iy)
  }

  func distanceMeters(from c1: CLLocationCoordinate2D, to c2: CLLocationCoordinate2D) -> Double {
    let p1 = xyMeters(for: c1)
    let p2 = xyMeters(for: c2)
    return hypot(p1.x - p2.x, p1.y - p2.y)
  }

  func contains(_ coordinate: CLLocationCoordinate2D, in boundary: [CLLocationCoordinate2D]) -> Bool {
    guard boundary.count >= 3 else { return false }
    let point = xyMeters(for: coordinate)
    let polygon = boundary.map { xyMeters(for: $0) }
    return Self.isPointInPolygon(x: point.x, y: point.y, polygon: polygon)
  }

  private static func isPointInPolygon(
    x: Double,
    y: Double,
    polygon: [(x: Double, y: Double)]
  ) -> Bool {
    guard polygon.count >= 3 else { return true }
    var inside = false
    var j = polygon.count - 1
    for i in 0 ..< polygon.count {
      let xi = polygon[i].x, yi = polygon[i].y
      let xj = polygon[j].x, yj = polygon[j].y
      let intersect = ((yi > y) != (yj > y)) &&
        (x < (xj - xi) * (y - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi)
      if intersect {
        inside.toggle()
      }
      j = i
    }
    return inside
  }
}

