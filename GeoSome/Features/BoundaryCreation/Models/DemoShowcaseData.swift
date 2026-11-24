import CoreLocation
import Foundation
import MapKit

/// Showcase / demo prefill configuration.
/// Automatically pre-populates the geofencing boundary and initial CPT soundings
/// so developers and presenters can showcase the app without repetitive manual setup.
enum DemoShowcaseData {
  // MARK: - Geofencing Corner Coordinates (UTM 48S)
  // 1) 48S 701635 E, 9314120 N
  // 2) 48S 701644 E, 9314155 N
  // 3) 48S 701543 E, 9314178 N
  // 4) 48S 701536 E, 9314143 N
  static let boundaryCoordinatesUTM: [(easting: Double, northing: Double)] = [
    (701635.0, 9314120.0),
    (701644.0, 9314155.0),
    (701543.0, 9314178.0),
    (701536.0, 9314143.0)
  ]

  // MARK: - Initial CPT Spot Coordinates (UTM 48S)
  // 1) 48S 701590 E, 9314149 N
  // 2) 48S 701642 E, 9314154 N
  // 3) 48S 701634 E, 9314122 N
  static let cptCoordinatesUTM: [(easting: Double, northing: Double)] = [
    (701590.0, 9314149.0),
    (701642.0, 9314154.0),
    (701634.0, 9314122.0)
  ]

  /// Pre-built `BoundaryPoint` models corresponding to the 4 demo corner coordinates.
  static var boundaryPoints: [BoundaryPoint] {
    boundaryCoordinatesUTM.compactMap { utm in
      guard let coord = UTMCoordinateConverter.utmToCoordinate(
        easting: utm.easting,
        northing: utm.northing,
        zone: 48,
        isSouthernHemisphere: true
      ) else { return nil }
      return BoundaryPoint(coordinate: coord)
    }
  }

  /// Initial boundary region framed around the 4 demo corner coordinates.
  static var initialBoundaryRegion: MKCoordinateRegion {
    let coords = boundaryPoints.map(\.coordinate)
    guard let first = coords.first else {
      return BoundaryMapConfiguration.defaultRegion
    }

    var minLat = first.latitude
    var maxLat = first.latitude
    var minLon = first.longitude
    var maxLon = first.longitude

    for c in coords {
      minLat = min(minLat, c.latitude)
      maxLat = max(maxLat, c.latitude)
      minLon = min(minLon, c.longitude)
      maxLon = max(maxLon, c.longitude)
    }

    let center = CLLocationCoordinate2D(
      latitude: (minLat + maxLat) * 0.5,
      longitude: (minLon + maxLon) * 0.5
    )
    let span = MKCoordinateSpan(
      latitudeDelta: max((maxLat - minLat) * 1.8, 0.0015),
      longitudeDelta: max((maxLon - minLon) * 1.8, 0.0015)
    )
    return MKCoordinateRegion(center: center, span: span)
  }

  /// Pre-built `CPTPointEntry` models corresponding to the 3 initial CPT spots,
  /// populated with geotechnical sounding data from `Resources/CPT/cpt_data.csv`.
  static var initialCPTPoints: [CPTPointEntry] {
    let rows = loadDemoCPTRows()
    let file = CPTUploadedFile(
      name: "cpt_data.csv",
      byteSize: 673,
      rowCount: rows.count,
      matchedColumns: ["depth_(m)", "qc_(MPa)", "fs_(kPa)"],
      isDemo: true
    )

    return cptCoordinatesUTM.compactMap { utm in
      guard let coord = UTMCoordinateConverter.utmToCoordinate(
        easting: utm.easting,
        northing: utm.northing,
        zone: 48,
        isSouthernHemisphere: true
      ) else { return nil }
      return CPTPointEntry(
        type: .electrical,
        coordinate: coord,
        file: file,
        rows: rows,
        uploadedAt: Date()
      )
    }
  }

  /// Creates a ready-to-demo project prefilled with the geofenced boundary,
  /// 3 initial CPT soundings from `cpt_data.csv`, and precomputed Core ML recommendation.
  static func makeDemoProject(name: String = "Demo Showcase") -> Project {
    let cpts = initialCPTPoints
    var project = Project(
      name: name,
      lastEdited: Date(),
      boundaryPoints: boundaryPoints,
      cptPoints: cpts,
      cptDistancePolicy: .sufficiencyV32SiteDiagonal
    )
    if !cpts.isEmpty {
      let recomputed = CPTPipelineCoordinator.recomputeFromScratch(
        boundaryCoordinates: project.boundaryCoordinates,
        cptPoints: project.cptPoints,
        gridPolicy: project.gridPolicy,
        distancePolicy: project.cptDistancePolicy,
        assessmentProject: project
      )
      project.latestRecommendation = recomputed
      project.stratigraphicEvidence = recomputed.stratigraphicEvidence
      project.consecutiveSufficientCount = recomputed.consecutiveSufficientCount
    }
    return project
  }

  /// Loads and parses rows from `cpt_data.csv`.
  /// Tries the main bundle, relative project path, and falls back to embedded data so it never fails.
  static func loadDemoCPTRows() -> [CPTRowData] {
    // 1. Try App Bundle
    if let url = Bundle.main.url(forResource: "cpt_data", withExtension: "csv"),
       let text = try? String(contentsOf: url, encoding: .utf8) {
      let result = CPTCSVParser.parse(text: text, cptType: .electrical)
      if !result.rows.isEmpty {
        return result.rows
      }
    }

    // 2. Try direct relative development path
    let devCandidates = [
      "GeoSome/Resources/CPT/cpt_data.csv",
      "Resources/CPT/cpt_data.csv"
    ]
    for path in devCandidates {
      if let text = try? String(contentsOfFile: path, encoding: .utf8) {
        let result = CPTCSVParser.parse(text: text, cptType: .electrical)
        if !result.rows.isEmpty {
          return result.rows
        }
      }
    }

    // 3. Guaranteed embedded raw CSV fallback from Resources/CPT/cpt_data.csv
    let embeddedCSV = """
    depth_(m),qc_mpa(mPa),fs_kpa(kPa)
    0.0,1.2,18.0
    0.5,1.38,19.25
    1.0,1.55,20.5
    1.5,1.72,21.75
    2.0,1.9,23.0
    2.5,2.0,25.0
    3.0,2.08,26.5
    3.5,2.15,28.0
    4.0,2.22,29.5
    4.5,2.3,31.0
    5.0,2.38,32.5
    5.5,2.45,34.0
    6.0,3.0,35.0
    6.5,3.45,37.0
    7.0,3.9,39.0
    7.5,4.35,41.0
    8.0,4.8,43.0
    8.5,5.25,45.0
    9.0,5.7,47.0
    9.5,6.15,49.0
    10.0,6.6,51.0
    10.5,6.82,52.25
    11.0,7.05,53.5
    11.5,7.28,54.75
    12.0,7.5,56.0
    12.5,7.72,57.25
    13.0,7.95,58.5
    13.5,8.17,59.75
    14.0,8.4,61.0
    14.5,8.95,62.75
    15.0,9.5,64.5
    15.5,10.05,66.25
    16.0,10.6,68.0
    16.5,11.15,69.75
    17.0,11.7,71.5
    17.5,12.25,73.25
    18.0,12.8,75.0
    18.5,13.35,76.75
    19.0,13.9,78.5
    19.5,14.45,80.25
    20.0,15.0,82.0
    """
    return CPTCSVParser.parse(text: embeddedCSV, cptType: .electrical).rows
  }
}
