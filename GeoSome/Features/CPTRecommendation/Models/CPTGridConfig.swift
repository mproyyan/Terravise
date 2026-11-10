import CoreLocation
import Foundation

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

  static func build(
    boundaryCoordinates: [CLLocationCoordinate2D],
    cptPoints: [CPTPointEntry]
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

    let dxM = max(rawWidthM / Double(max(nx - 1, 1)), 1.0)
    let dyM = max(rawHeightM / Double(max(ny - 1, 1)), 1.0)

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
    let nz = min(max(rawNz, 12), 24)

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
    var mask2D = Array(repeating: Array(repeating: false, count: ny), count: nx)
    var validCount = 0
    for ix in 0 ..< nx {
      let x = Double(ix) * dxM
      for iy in 0 ..< ny {
        let y = Double(iy) * dyM
        if isPointInPolygon(x: x, y: y, polygon: polyXY) {
          mask2D[ix][iy] = true
          validCount += 1
        }
      }
    }

    // Fallback if polygon is very narrow ordegenerate
    if validCount < 4 {
      for ix in 0 ..< nx {
        for iy in 0 ..< ny {
          mask2D[ix][iy] = true
        }
      }
    }

    let extentX = Double(nx) * dxM
    let extentY = Double(ny) * dyM
    let diagonal = hypot(extentX, extentY)
    let aspect = max(extentX, extentY) / max(min(extentX, extentY), 1.0)

    return CPTGridConfig(
      nx: nx,
      ny: ny,
      nz: nz,
      dxM: dxM,
      dyM: dyM,
      dzM: dzM,
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

