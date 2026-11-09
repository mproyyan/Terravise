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
