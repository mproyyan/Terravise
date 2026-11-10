import CoreLocation
import Foundation

enum CPTType: String, CaseIterable, Identifiable, Codable, Sendable {
  case electrical = "Electrical CPT"
  case cptmBicone = "CPTm Bicone"
  case cptu = "CPTu"

  var id: String {
    rawValue
  }

  var displayName: String {
    switch self {
    case .electrical:
      "Electrical CPT"
    case .cptmBicone:
      "CPTm Bicone"
    case .cptu:
      "CPTu"
    }
  }

  var requiredColumns: [String] {
    switch self {
    case .electrical:
      ["depth_(m)", "qc_mpa(mPa)", "fs_kpa(kPa)"]
    case .cptmBicone:
      ["depth_(cm)", "Cw_(kg/cm2)", "Tw_(kg/cm2)"]
    case .cptu:
      ["depth_(m)", "qc_mpa(mPa)", "fs_kpa(kPa)", "u2_kpa(kPa)"]
    }
  }
}

struct CPTEquipmentParameters: Hashable, Codable, Sendable {
  var netAreaRatio: Double
  var pistonDiameterCm: Double
  var coneDiameterCm: Double
  var frictionSleeveDiameterCm: Double
  var frictionSleeveLengthCm: Double

  init(
    netAreaRatio: Double = 0.80,
    pistonDiameterCm: Double = 3.57,
    coneDiameterCm: Double = 3.57,
    frictionSleeveDiameterCm: Double = 3.57,
    frictionSleeveLengthCm: Double = 13.3
  ) {
    self.netAreaRatio = netAreaRatio
    self.pistonDiameterCm = pistonDiameterCm
    self.coneDiameterCm = coneDiameterCm
    self.frictionSleeveDiameterCm = frictionSleeveDiameterCm
    self.frictionSleeveLengthCm = frictionSleeveLengthCm
  }
}

struct CPTUploadedFile: Identifiable, Hashable, Codable, Sendable {
  let id: UUID
  var name: String
  var byteSize: Int64
  var rowCount: Int
  var matchedColumns: [String]

  init(
    id: UUID = UUID(),
    name: String,
    byteSize: Int64 = 24 * 1024,
    rowCount: Int = 52,
    matchedColumns: [String] = ["depth_(m)", "qc_mpa(mPa)", "fs_kpa(kPa)", "u2_kpa(kPa)"]
  ) {
    self.id = id
    self.name = name
    self.byteSize = byteSize
    self.rowCount = rowCount
    self.matchedColumns = matchedColumns
  }

  var formattedSize: String {
    ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
  }

  func isColumnMatched(_ column: String) -> Bool {
    matchedColumns.contains(column)
  }
}

struct CPTRowData: Identifiable, Hashable, Codable, Sendable {
  let id: UUID
  var depth: Double
  var coneResistance: Double
  var localFriction: Double
  var porePressure: Double?
  var explicitIc: Double?
  var cptType: CPTType?
  var netAreaRatio: Double?

  init(
    id: UUID = UUID(),
    depth: Double,
    coneResistance: Double,
    localFriction: Double,
    porePressure: Double? = nil,
    explicitIc: Double? = nil,
    cptType: CPTType? = nil,
    netAreaRatio: Double? = nil
  ) {
    self.id = id
    self.depth = depth
    self.coneResistance = coneResistance
    self.localFriction = localFriction
    self.porePressure = porePressure
    self.explicitIc = explicitIc
    self.cptType = cptType
    self.netAreaRatio = netAreaRatio
  }

  /// Computes Soil Behavior Type Index (Ic) using the row's CPTType (or inferred from porePressure if nil).
  var ic: Double {
    let resolvedType = cptType ?? (porePressure != nil ? .cptu : .electrical)
    return ic(for: resolvedType)
  }

  /// Computes Soil Behavior Type Index (Ic) tailored to the specific CPT instrument type.
  func ic(for type: CPTType) -> Double {
    if let explicitIc, explicitIc.isFinite, explicitIc > 0 {
      return min(max(explicitIc, 1.0), 4.5)
    }
    return Self.calculateRobertsonIc(
      depth: depth,
      qcMPa: coneResistance,
      fsKPa: localFriction,
      u2KPa: porePressure,
      cptType: type,
      netAreaRatio: netAreaRatio ?? 0.80
    )
  }

  /// Calculates Robertson Soil Behavior Type Index (Ic) for the 3 supported CPT types:
  /// - `.cptu`: Robertson (2009) stress-normalized Ic with pore-pressure correction `qt = qc + (1 - a) * u2`.
  /// - `.electrical`: Robertson (2010) non-normalized SBT index `I_SBT` using `qc` and `Rf = (fs / qc) * 100%` (no `u2`, no net area ratio).
  /// - `.cptmBicone`: Applies Begemann mechanical-to-electrical sleeve conversion (`fs_eq = 0.75 * fs`, no `u2`, no net area ratio) before computing Robertson (2010) `I_SBT`.
  static func calculateRobertsonIc(
    depth: Double,
    qcMPa: Double,
    fsKPa: Double,
    u2KPa: Double? = nil,
    cptType: CPTType = .cptu,
    netAreaRatio: Double = 0.80
  ) -> Double {
    let paKPa = 100.0
    let paMPa = 0.10

    switch cptType {
    case .cptu:
      let z = max(depth, 0.1)
      let clampedA = min(max(netAreaRatio, 0.40), 1.0)
      let u2MPa = max((u2KPa ?? 0.0) / 1000.0, 0.0)
      let qtMPa = max(qcMPa + (1.0 - clampedA) * u2MPa, 0.05)

      // Total and effective vertical overburden stress assuming unit weight = 18 kN/m³
      let sigmaV0KPa = 18.0 * z
      let u0KPa = 9.81 * max(z - 1.0, 0.0)
      let sigmaPrimeV0KPa = max(sigmaV0KPa - u0KPa, 10.0)

      let netQtMPa = max(qtMPa - (sigmaV0KPa / 1000.0), 0.02)
      let netQtKPa = netQtMPa * 1000.0

      // Normalized friction ratio Fr (%)
      let safeFsKPa = max(fsKPa, 0.1)
      let frPercent = min(max((safeFsKPa / netQtKPa) * 100.0, 0.05), 15.0)

      // Two-pass stress exponent n refinement (Robertson 2009)
      var n = 1.0
      var icValue = 2.5
      let stressRatio = sigmaPrimeV0KPa / paKPa

      for _ in 0 ..< 2 {
        let cFactor = min(max(pow(paKPa / sigmaPrimeV0KPa, n), 0.2), 1.7)
        let qtn = min(max((netQtMPa / paMPa) * cFactor, 1.0), 1000.0)
        let termQ = 3.47 - log10(qtn)
        let termF = log10(frPercent) + 1.22
        icValue = sqrt(termQ * termQ + termF * termF)
        n = min(max(0.381 * icValue + 0.05 * stressRatio - 0.15, 0.5), 1.0)
      }

      if !icValue.isFinite {
        return 2.790332
      }
      return min(max(icValue, 1.0), 4.5)

    case .electrical:
      // Robertson (2010) non-normalized I_SBT using qc and Rf = (fs / qc) * 100% (no u2, no net area ratio)
      let safeQcMPa = max(qcMPa, 0.05)
      let safeQcKPa = safeQcMPa * 1000.0
      let safeFsKPa = max(fsKPa, 0.1)
      let rfPercent = min(max((safeFsKPa / safeQcKPa) * 100.0, 0.05), 15.0)

      let qRatio = min(max(safeQcMPa / paMPa, 1.0), 1000.0)
      let termQ = 3.47 - log10(qRatio)
      let termF = log10(rfPercent) + 1.22
      let icValue = sqrt(termQ * termQ + termF * termF)

      if !icValue.isFinite {
        return 2.790332
      }
      return min(max(icValue, 1.0), 4.5)

    case .cptmBicone:
      // Begemann Mechanical Bicone: no u2 and no net area ratio.
      // Apply mechanical-to-electrical sleeve conversion (fs_eq = 0.75 * fs_mech) to remove lower-bevel bearing bias,
      // then compute Robertson (2010) non-normalized I_SBT.
      let safeQcMPa = max(qcMPa, 0.05)
      let safeQcKPa = safeQcMPa * 1000.0
      let equivalentFsKPa = max(fsKPa * 0.75, 0.1)
      let rfPercent = min(max((equivalentFsKPa / safeQcKPa) * 100.0, 0.05), 15.0)

      let qRatio = min(max(safeQcMPa / paMPa, 1.0), 1000.0)
      let termQ = 3.47 - log10(qRatio)
      let termF = log10(rfPercent) + 1.22
      let icValue = sqrt(termQ * termQ + termF * termF)

      if !icValue.isFinite {
        return 2.790332
      }
      return min(max(icValue, 1.0), 4.5)
    }
  }

  static func soilBehaviorType(forIc ic: Double) -> String {
    switch ic {
    case ..<1.31:
      "gravelly sand"
    case 1.31 ..< 2.05:
      "sand"
    case 2.05 ..< 2.60:
      "silty sand"
    case 2.60 ..< 2.95:
      "sandy silt"
    case 2.95 ..< 3.60:
      "silty clay"
    default:
      "soft clay"
    }
  }

  static let sampleRows: [CPTRowData] = [
    CPTRowData(depth: 1.0, coneResistance: 4.80, localFriction: 42.0, porePressure: 5.0),
    CPTRowData(depth: 2.0, coneResistance: 6.20, localFriction: 55.0, porePressure: 12.0),
    CPTRowData(depth: 3.0, coneResistance: 5.40, localFriction: 58.0, porePressure: 22.0),
    CPTRowData(depth: 4.0, coneResistance: 3.10, localFriction: 48.0, porePressure: 35.0),
    CPTRowData(depth: 5.0, coneResistance: 2.20, localFriction: 44.0, porePressure: 48.0),
    CPTRowData(depth: 6.0, coneResistance: 1.65, localFriction: 39.0, porePressure: 62.0),
    CPTRowData(depth: 7.0, coneResistance: 1.40, localFriction: 36.0, porePressure: 75.0),
    CPTRowData(depth: 8.0, coneResistance: 1.85, localFriction: 45.0, porePressure: 88.0),
    CPTRowData(depth: 9.0, coneResistance: 3.60, localFriction: 64.0, porePressure: 95.0),
    CPTRowData(depth: 10.0, coneResistance: 7.50, localFriction: 92.0, porePressure: 102.0),
    CPTRowData(depth: 11.0, coneResistance: 12.40, localFriction: 118.0, porePressure: 110.0),
    CPTRowData(depth: 12.0, coneResistance: 16.80, localFriction: 145.0, porePressure: 118.0)
  ]
}

struct CPTPointEntry: Identifiable, Hashable, Codable, Sendable {
  let id: UUID
  var type: CPTType
  var coordinate: CLLocationCoordinate2D
  var file: CPTUploadedFile
  var rows: [CPTRowData]
  var uploadedAt: Date

  private enum CodingKeys: String, CodingKey {
    case id
    case type
    case latitude
    case longitude
    case file
    case rows
    case uploadedAt
  }

  init(
    id: UUID = UUID(),
    type: CPTType = .electrical,
    coordinate: CLLocationCoordinate2D,
    file: CPTUploadedFile,
    rows: [CPTRowData] = CPTRowData.sampleRows,
    uploadedAt: Date = Date()
  ) {
    self.id = id
    self.type = type
    self.coordinate = coordinate
    self.file = file
    self.rows = rows
    self.uploadedAt = uploadedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    type = try container.decode(CPTType.self, forKey: .type)
    let lat = try container.decode(Double.self, forKey: .latitude)
    let lon = try container.decode(Double.self, forKey: .longitude)
    coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    file = try container.decode(CPTUploadedFile.self, forKey: .file)
    rows = try container.decode([CPTRowData].self, forKey: .rows)
    uploadedAt = try container.decodeIfPresent(Date.self, forKey: .uploadedAt) ?? Date()
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(type, forKey: .type)
    try container.encode(coordinate.latitude, forKey: .latitude)
    try container.encode(coordinate.longitude, forKey: .longitude)
    try container.encode(file, forKey: .file)
    try container.encode(rows, forKey: .rows)
    try container.encode(uploadedAt, forKey: .uploadedAt)
  }

  var formattedCoordinate: String {
    String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
  }

  var formattedLatitude: String {
    String(format: "%.6f", coordinate.latitude)
  }

  var formattedLongitude: String {
    String(format: "%.6f", coordinate.longitude)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  static func == (lhs: CPTPointEntry, rhs: CPTPointEntry) -> Bool {
    lhs.id == rhs.id
  }
}

struct CPTRecommendationResult: Hashable, Codable, Sendable {
  var coordinate: CLLocationCoordinate2D
  var rmse: Double
  var confidenceLevel: Int
  var spotName: String
  var nearestCPTDistance: Double
  var nearbyCountWithin4m: Int
  var shallowSoilType: String
  var deepSoilType: String
  var lateralIcDifference: Double
  var qValue: Double
  var predictedCoverage: Double
  var sufficiencyProbability: Double
  var consecutiveSufficientCount: Int
  var isSufficient: Bool

  private enum CodingKeys: String, CodingKey {
    case latitude
    case longitude
    case rmse
    case confidenceLevel
    case spotName
    case nearestCPTDistance
    case nearbyCountWithin4m
    case shallowSoilType
    case deepSoilType
    case lateralIcDifference
    case qValue
    case predictedCoverage
    case sufficiencyProbability
    case consecutiveSufficientCount
    case isSufficient
  }

  init(
    coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: -6.2418, longitude: 106.8315),
    rmse: Double = 0.0064,
    confidenceLevel: Int = 90,
    spotName: String = "Spot B",
    nearestCPTDistance: Double = 16.2,
    nearbyCountWithin4m: Int = 0,
    shallowSoilType: String = "sand",
    deepSoilType: String = "soft clay",
    lateralIcDifference: Double = 0.18,
    qValue: Double = 0.0,
    predictedCoverage: Double = 0.90,
    sufficiencyProbability: Double = 0.0,
    consecutiveSufficientCount: Int = 0,
    isSufficient: Bool = false
  ) {
    self.coordinate = coordinate
    self.rmse = rmse
    self.confidenceLevel = confidenceLevel
    self.spotName = spotName
    self.nearestCPTDistance = nearestCPTDistance
    self.nearbyCountWithin4m = nearbyCountWithin4m
    self.shallowSoilType = shallowSoilType
    self.deepSoilType = deepSoilType
    self.lateralIcDifference = lateralIcDifference
    self.qValue = qValue
    self.predictedCoverage = predictedCoverage
    self.sufficiencyProbability = sufficiencyProbability
    self.consecutiveSufficientCount = consecutiveSufficientCount
    self.isSufficient = isSufficient
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let lat = try container.decode(Double.self, forKey: .latitude)
    let lon = try container.decode(Double.self, forKey: .longitude)
    coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    rmse = try container.decode(Double.self, forKey: .rmse)
    confidenceLevel = try container.decode(Int.self, forKey: .confidenceLevel)
    spotName = try container.decodeIfPresent(String.self, forKey: .spotName) ?? "Spot B"
    nearestCPTDistance = try container.decodeIfPresent(Double.self, forKey: .nearestCPTDistance) ?? 16.2
    nearbyCountWithin4m = try container.decodeIfPresent(Int.self, forKey: .nearbyCountWithin4m) ?? 0
    shallowSoilType = try container.decodeIfPresent(String.self, forKey: .shallowSoilType) ?? "sand"
    deepSoilType = try container.decodeIfPresent(String.self, forKey: .deepSoilType) ?? "soft clay"
    lateralIcDifference = try container.decodeIfPresent(Double.self, forKey: .lateralIcDifference) ?? 0.15
    qValue = try container.decodeIfPresent(Double.self, forKey: .qValue) ?? 0.0
    predictedCoverage = try container.decodeIfPresent(Double.self, forKey: .predictedCoverage) ?? 0.90
    sufficiencyProbability = try container.decodeIfPresent(Double.self, forKey: .sufficiencyProbability) ?? 0.0
    consecutiveSufficientCount = try container.decodeIfPresent(Int.self, forKey: .consecutiveSufficientCount) ?? 0
    isSufficient = try container.decodeIfPresent(Bool.self, forKey: .isSufficient) ?? false
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(coordinate.latitude, forKey: .latitude)
    try container.encode(coordinate.longitude, forKey: .longitude)
    try container.encode(rmse, forKey: .rmse)
    try container.encode(confidenceLevel, forKey: .confidenceLevel)
    try container.encode(spotName, forKey: .spotName)
    try container.encode(nearestCPTDistance, forKey: .nearestCPTDistance)
    try container.encode(nearbyCountWithin4m, forKey: .nearbyCountWithin4m)
    try container.encode(shallowSoilType, forKey: .shallowSoilType)
    try container.encode(deepSoilType, forKey: .deepSoilType)
    try container.encode(lateralIcDifference, forKey: .lateralIcDifference)
    try container.encode(qValue, forKey: .qValue)
    try container.encode(predictedCoverage, forKey: .predictedCoverage)
    try container.encode(sufficiencyProbability, forKey: .sufficiencyProbability)
    try container.encode(consecutiveSufficientCount, forKey: .consecutiveSufficientCount)
    try container.encode(isSufficient, forKey: .isSufficient)
  }

  var formattedCoordinate: String {
    String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(coordinate.latitude)
    hasher.combine(coordinate.longitude)
    hasher.combine(rmse)
    hasher.combine(confidenceLevel)
    hasher.combine(isSufficient)
    hasher.combine(spotName)
  }

  static func == (lhs: CPTRecommendationResult, rhs: CPTRecommendationResult) -> Bool {
    lhs.coordinate.latitude == rhs.coordinate.latitude &&
      lhs.coordinate.longitude == rhs.coordinate.longitude &&
      lhs.rmse == rhs.rmse &&
      lhs.confidenceLevel == rhs.confidenceLevel &&
      lhs.isSufficient == rhs.isSufficient &&
      lhs.spotName == rhs.spotName
  }
}
