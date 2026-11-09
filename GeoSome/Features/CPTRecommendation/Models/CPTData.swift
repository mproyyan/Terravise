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
    case .electrical, .cptmBicone:
      ["depth_(m)", "qc_mpa(mPa)", "fs_kpa(kPa)"]
    case .cptu:
      ["depth_(m)", "qc_mpa(mPa)", "fs_kpa(kPa)", "u2_kpa(kPa)"]
    }
  }
}

struct CPTUploadedFile: Identifiable, Hashable, Codable, Sendable {
  let id: UUID
  var name: String
  var byteSize: Int64
  var rowCount: Int

  init(
    id: UUID = UUID(),
    name: String,
    byteSize: Int64 = 24 * 1024,
    rowCount: Int = 52
  ) {
    self.id = id
    self.name = name
    self.byteSize = byteSize
    self.rowCount = rowCount
  }

  var formattedSize: String {
    ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
  }
}

struct CPTPointEntry: Identifiable, Hashable, Sendable {
  let id: UUID
  var type: CPTType
  var coordinate: CLLocationCoordinate2D
  var file: CPTUploadedFile
  var uploadedAt: Date

  init(
    id: UUID = UUID(),
    type: CPTType,
    coordinate: CLLocationCoordinate2D,
    file: CPTUploadedFile,
    uploadedAt: Date = Date()
  ) {
    self.id = id
    self.type = type
    self.coordinate = coordinate
    self.file = file
    self.uploadedAt = uploadedAt
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  static func == (lhs: CPTPointEntry, rhs: CPTPointEntry) -> Bool {
    lhs.id == rhs.id
  }
}

struct CPTRecommendationResult: Hashable, Sendable {
  var coordinate: CLLocationCoordinate2D
  var rmse: Double
  var confidenceLevel: Int
  var spotName: String
  var nearestCPTDistance: Double

  init(
    coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: -6.215432, longitude: 106.845321),
    rmse: Double = 0.0064,
    confidenceLevel: Int = 90,
    spotName: String = "Spot B",
    nearestCPTDistance: Double = 16.2
  ) {
    self.coordinate = coordinate
    self.rmse = rmse
    self.confidenceLevel = confidenceLevel
    self.spotName = spotName
    self.nearestCPTDistance = nearestCPTDistance
  }

  var formattedCoordinate: String {
    String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(coordinate.latitude)
    hasher.combine(coordinate.longitude)
    hasher.combine(rmse)
    hasher.combine(confidenceLevel)
  }

  static func == (lhs: CPTRecommendationResult, rhs: CPTRecommendationResult) -> Bool {
    lhs.coordinate.latitude == rhs.coordinate.latitude &&
      lhs.coordinate.longitude == rhs.coordinate.longitude &&
      lhs.rmse == rhs.rmse &&
      lhs.confidenceLevel == rhs.confidenceLevel
  }
}
