import CoreLocation
import Foundation

public struct UTMCoordinate: Hashable, Sendable {
  public let zone: Int
  public let isSouthernHemisphere: Bool
  public let easting: Double
  public let northing: Double

  public init(
    zone: Int,
    isSouthernHemisphere: Bool,
    easting: Double,
    northing: Double
  ) {
    self.zone = zone
    self.isSouthernHemisphere = isSouthernHemisphere
    self.easting = easting
    self.northing = northing
  }

  public var zoneIdentifier: String {
    "\(zone)\(isSouthernHemisphere ? "S" : "N")"
  }

  /// Formatted UTM string for engineering displays (e.g., "48S 702634 E, 9309747 N")
  public var formattedString: String {
    let eRound = Int(easting.rounded())
    let nRound = Int(northing.rounded())
    return "\(zoneIdentifier) \(eRound) E, \(nRound) N"
  }

  /// Formatted UTM string with decimal precision (e.g., "48S 702634.0 E, 9309747.2 N")
  public var formattedDetailedString: String {
    let eStr = String(format: "%.1f", easting)
    let nStr = String(format: "%.1f", northing)
    return "\(zoneIdentifier) \(eStr) E, \(nStr) N"
  }
}

public enum UTMCoordinateConverter {
  // WGS84 Ellipsoid Parameters
  private static let a: Double = 6378137.0
  private static let f: Double = 1.0 / 298.257223563
  private static let b: Double = a * (1.0 - f)
  private static let e2: Double = (a * a - b * b) / (a * a)
  private static let ep2: Double = (a * a - b * b) / (b * b)
  private static let k0: Double = 0.9996

  // Default fallback zone for Indonesian projects (Zone 48S, West Java / Jakarta)
  public static let defaultZone = 48
  public static let defaultIsSouthernHemisphere = true

  // MARK: - Forward Conversion (WGS84 Lat/Lon -> UTM)

  public static func coordinateToUTM(_ coordinate: CLLocationCoordinate2D) -> UTMCoordinate {
    let lat = coordinate.latitude
    let lon = coordinate.longitude

    var zone = Int((lon + 180.0) / 6.0) + 1
    if zone < 1 { zone = 1 }
    if zone > 60 { zone = 60 }

    let isSouth = lat < 0.0

    let lon0 = Double((zone - 1) * 6 - 180 + 3)
    let latRad = lat * .pi / 180.0
    let lonRad = lon * .pi / 180.0
    let lon0Rad = lon0 * .pi / 180.0
    let dlon = lonRad - lon0Rad

    let sinLat = sin(latRad)
    let cosLat = cos(latRad)
    let tanLat = tan(latRad)

    let n = a / sqrt(1.0 - e2 * sinLat * sinLat)
    let t = tanLat * tanLat
    let c = ep2 * cosLat * cosLat
    let bigA = dlon * cosLat

    let m = a * (
      (1.0 - e2 / 4.0 - 3.0 * e2 * e2 / 64.0 - 5.0 * e2 * e2 * e2 / 256.0) * latRad
        - (3.0 * e2 / 8.0 + 3.0 * e2 * e2 / 32.0 + 45.0 * e2 * e2 * e2 / 1024.0) * sin(2.0 * latRad)
        + (15.0 * e2 * e2 / 256.0 + 45.0 * e2 * e2 * e2 / 1024.0) * sin(4.0 * latRad)
        - (35.0 * e2 * e2 * e2 / 3072.0) * sin(6.0 * latRad)
    )

    let easting = k0 * n * (
      bigA + (1.0 - t + c) * pow(bigA, 3) / 6.0
        + (5.0 - 18.0 * t + t * t + 72.0 * c - 58.0 * ep2) * pow(bigA, 5) / 120.0
    ) + 500000.0

    var northing = k0 * (
      m + n * tanLat * (
        pow(bigA, 2) / 2.0
          + (5.0 - t + 9.0 * c + 4.0 * c * c) * pow(bigA, 4) / 24.0
          + (61.0 - 58.0 * t + t * t + 600.0 * c - 330.0 * ep2) * pow(bigA, 6) / 720.0
      )
    )

    if isSouth {
      northing += 10000000.0
    }

    return UTMCoordinate(
      zone: zone,
      isSouthernHemisphere: isSouth,
      easting: easting,
      northing: northing
    )
  }

  // MARK: - Validation Limits
  public static let validZoneRange = 1 ... 60
  public static let validEastingRange: ClosedRange<Double> = 100000.0 ... 900000.0
  public static let validNorthingRange: ClosedRange<Double> = 0.0 ... 10000000.0

  public static func isValidUTM(
    zone: Int,
    easting: Double,
    northing: Double
  ) -> Bool {
    validZoneRange.contains(zone) &&
      validEastingRange.contains(easting) &&
      validNorthingRange.contains(northing)
  }

  // MARK: - Inverse Conversion (UTM -> WGS84 Lat/Lon)

  public static func utmToCoordinate(
    easting: Double,
    northing: Double,
    zone: Int,
    isSouthernHemisphere: Bool
  ) -> CLLocationCoordinate2D? {
    guard isValidUTM(zone: zone, easting: easting, northing: northing) else {
      return nil
    }

    let lon0 = Double((zone - 1) * 6 - 180 + 3)
    let lon0Rad = lon0 * .pi / 180.0

    let yAdj = isSouthernHemisphere ? (northing - 10000000.0) : northing
    let m = yAdj / k0
    let e1 = (1.0 - sqrt(1.0 - e2)) / (1.0 + sqrt(1.0 - e2))
    let mu = m / (a * (1.0 - e2 / 4.0 - 3.0 * e2 * e2 / 64.0 - 5.0 * e2 * e2 * e2 / 256.0))

    let phi1 = mu
      + (3.0 * e1 / 2.0 - 27.0 * pow(e1, 3) / 32.0) * sin(2.0 * mu)
      + (21.0 * pow(e1, 2) / 16.0 - 55.0 * pow(e1, 4) / 32.0) * sin(4.0 * mu)
      + (151.0 * pow(e1, 3) / 96.0) * sin(6.0 * mu)
      + (1097.0 * pow(e1, 4) / 512.0) * sin(8.0 * mu)

    let sinPhi1 = sin(phi1)
    let cosPhi1 = cos(phi1)
    let tanPhi1 = tan(phi1)

    let n1 = a / sqrt(1.0 - e2 * sinPhi1 * sinPhi1)
    let t1 = tanPhi1 * tanPhi1
    let c1 = ep2 * cosPhi1 * cosPhi1
    let r1 = a * (1.0 - e2) / pow(1.0 - e2 * sinPhi1 * sinPhi1, 1.5)
    let d = (easting - 500000.0) / (n1 * k0)

    let latRad = phi1 - (n1 * tanPhi1 / r1) * (
      d * d / 2.0
        - (5.0 + 3.0 * t1 + 10.0 * c1 - 4.0 * c1 * c1 - 9.0 * ep2) * pow(d, 4) / 24.0
        + (61.0 + 90.0 * t1 + 298.0 * c1 + 45.0 * t1 * t1 - 252.0 * ep2 - 3.0 * c1 * c1) * pow(d, 6) / 720.0
    )

    let lonRad = lon0Rad + (
      d - (1.0 + 2.0 * t1 + c1) * pow(d, 3) / 6.0
        + (5.0 - 2.0 * c1 + 28.0 * t1 - 3.0 * c1 * c1 + 8.0 * ep2 + 24.0 * t1 * t1) * pow(d, 5) / 120.0
    ) / cosPhi1

    let lat = latRad * 180.0 / .pi
    let lon = lonRad * 180.0 / .pi

    let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    guard CLLocationCoordinate2DIsValid(coord),
          (-80.0 ... 84.0).contains(lat),
          (-180.0 ... 180.0).contains(lon)
    else {
      return nil
    }

    return coord
  }

  // MARK: - Formatter

  public static func formatAsUTM(_ coordinate: CLLocationCoordinate2D) -> String {
    guard coordinate.latitude.isFinite, coordinate.longitude.isFinite else {
      return "—"
    }
    return coordinateToUTM(coordinate).formattedString
  }

  // MARK: - Component-Based UTM Parser

  /// Parses discrete Zone, Easting, and Northing strings into `CLLocationCoordinate2D`.
  public static func parseUTMComponents(
    zoneText: String,
    eastingText: String,
    northingText: String,
    referenceCoordinate: CLLocationCoordinate2D? = nil
  ) -> CLLocationCoordinate2D? {
    let zoneClean = zoneText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !zoneClean.isEmpty else { return nil }

    let zonePattern = #"^([0-9]{1,2})\s*([NSns]?)$"#
    guard let zoneRegex = try? NSRegularExpression(pattern: zonePattern),
          let match = zoneRegex.firstMatch(in: zoneClean, range: NSRange(zoneClean.startIndex..., in: zoneClean)),
          let zoneRange = Range(match.range(at: 1), in: zoneClean),
          let zoneNumber = Int(zoneClean[zoneRange]),
          validZoneRange.contains(zoneNumber)
    else {
      return nil
    }

    let isSouth: Bool
    if match.range(at: 2).location != NSNotFound,
       let hemRange = Range(match.range(at: 2), in: zoneClean),
       !zoneClean[hemRange].isEmpty {
      isSouth = zoneClean[hemRange].uppercased() == "S"
    } else if let ref = referenceCoordinate {
      isSouth = coordinateToUTM(ref).isSouthernHemisphere
    } else {
      isSouth = defaultIsSouthernHemisphere
    }

    let eClean = eastingText
      .replacingOccurrences(of: ",", with: ".")
      .replacingOccurrences(of: "m", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "E", with: "", options: .caseInsensitive)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let nClean = northingText
      .replacingOccurrences(of: ",", with: ".")
      .replacingOccurrences(of: "m", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "N", with: "", options: .caseInsensitive)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let easting = Double(eClean), let northing = Double(nClean) else {
      return nil
    }

    return utmToCoordinate(
      easting: easting,
      northing: northing,
      zone: zoneNumber,
      isSouthernHemisphere: isSouth
    )
  }

  // MARK: - Flexible Parser (Supports UTM and Lat/Lon)

  /// Parses text into `CLLocationCoordinate2D`.
  /// Supports:
  /// - UTM format with zone: `"48S 702634 E, 9309747 N"`, `"48S 702634, 9309747"`
  /// - UTM format without zone: `"702634 E, 9309747 N"`, `"702634, 9309747"` (uses referenceCoordinate to infer zone)
  /// - Standard Lat/Lon format: `"-6.2415, 106.8315"`
  public static func parseCoordinate(
    from text: String,
    referenceCoordinate: CLLocationCoordinate2D? = nil
  ) -> CLLocationCoordinate2D? {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }

    // 1. Check for UTM Zone prefix like "48S", "48N", "49S"
    let pattern = #"^([0-9]{1,2})\s*([NSns])\s+(.+)$"#
    if let regex = try? NSRegularExpression(pattern: pattern),
       let match = regex.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)) {
      if let zoneRange = Range(match.range(at: 1), in: clean),
         let hemRange = Range(match.range(at: 2), in: clean),
         let restRange = Range(match.range(at: 3), in: clean),
         let zone = Int(clean[zoneRange]) {
        let hem = clean[hemRange].uppercased()
        let isSouth = hem == "S"
        let rest = String(clean[restRange])
        if let (easting, northing) = parseEastingNorthing(rest) {
          return utmToCoordinate(
            easting: easting,
            northing: northing,
            zone: zone,
            isSouthernHemisphere: isSouth
          )
        }
      }
    }

    // 2. Try parsing as 2 comma/space-separated numbers
    let cleanedNumbers = clean
      .replacingOccurrences(of: "m", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "E", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "N", with: "", options: .caseInsensitive)

    let separators = CharacterSet(charactersIn: ",; \t")
    let rawParts = cleanedNumbers.components(separatedBy: separators).filter { !$0.isEmpty }

    if rawParts.count >= 2,
       let first = Double(rawParts[0]),
       let second = Double(rawParts[1]) {

      // Check if this is UTM (Eastings are typically 100,000–900,000; Northings > 1,000)
      if first > 1000.0 || second > 1000.0 {
        let easting = min(first, second)
        let northing = max(first, second)

        let refZone: Int
        let refIsSouth: Bool
        if let ref = referenceCoordinate {
          let utm = coordinateToUTM(ref)
          refZone = utm.zone
          refIsSouth = utm.isSouthernHemisphere
        } else {
          refZone = defaultZone
          refIsSouth = defaultIsSouthernHemisphere
        }

        return utmToCoordinate(
          easting: easting,
          northing: northing,
          zone: refZone,
          isSouthernHemisphere: refIsSouth
        )
      }

      // Check if this is Lat/Lon (Lat within -90...90, Lon within -180...180)
      if (-90.0 ... 90.0).contains(first), (-180.0 ... 180.0).contains(second) {
        return CLLocationCoordinate2D(latitude: first, longitude: second)
      }
      if (-90.0 ... 90.0).contains(second), (-180.0 ... 180.0).contains(first) {
        return CLLocationCoordinate2D(latitude: second, longitude: first)
      }
    }

    return nil
  }

  private static func parseEastingNorthing(_ text: String) -> (Double, Double)? {
    let cleaned = text
      .replacingOccurrences(of: "m", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "E", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "N", with: "", options: .caseInsensitive)

    let separators = CharacterSet(charactersIn: ",; \t")
    let parts = cleaned.components(separatedBy: separators).filter { !$0.isEmpty }
    guard parts.count >= 2,
          let v1 = Double(parts[0]),
          let v2 = Double(parts[1])
    else {
      return nil
    }

    let easting = min(v1, v2)
    let northing = max(v1, v2)
    return (easting, northing)
  }
}
