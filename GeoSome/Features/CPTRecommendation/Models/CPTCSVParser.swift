import Foundation

struct CPTCSVParseResult: Sendable {
  let rows: [CPTRowData]
  let matchedRequiredColumns: [String]
  var error: String? = nil
}

enum CPTCSVParser {
  static func parse(
    url: URL,
    cptType: CPTType,
    equipment: CPTEquipmentParameters = CPTEquipmentParameters()
  ) -> CPTCSVParseResult {
    let ext = url.pathExtension.lowercased()
    guard ext == "csv" || ext == "xlsx" else {
      return CPTCSVParseResult(rows: [], matchedRequiredColumns: [],
                               error: "Format .\(ext) belum didukung. Ekspor data sebagai CSV atau Excel (.xlsx).")
    }

    if ext == "xlsx" {
      if let data = try? Data(contentsOf: url),
         let csvText = CPTXLSXCodec.extractCSVText(from: data) {
        return parse(text: csvText, cptType: cptType, equipment: equipment)
      }
    }

    guard let rawText = (try? String(contentsOf: url, encoding: .utf8))
      ?? (try? String(contentsOf: url, encoding: .ascii))
    else {
      return CPTCSVParseResult(rows: [], matchedRequiredColumns: [], error: "File tidak dapat dibaca.")
    }
    return parse(text: rawText, cptType: cptType, equipment: equipment)
  }

  static func parse(
    text: String,
    cptType: CPTType,
    equipment: CPTEquipmentParameters = CPTEquipmentParameters()
  ) -> CPTCSVParseResult {
    let cleanedText = text.replacingOccurrences(of: "\u{FEFF}", with: "")
    let rawLines = cleanedText
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    guard let headerLine = rawLines.first else {
      return CPTCSVParseResult(rows: [], matchedRequiredColumns: [], error: "CSV kosong.")
    }

    let delimiter: Character = headerLine.contains(";") && !headerLine.contains(",") ? ";" : ","
    let headers = splitCSVRow(headerLine, delimiter: delimiter)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    if cptType == .cptmBicone {
      return parseBiconeCSV(rawLines: rawLines, headers: headers, delimiter: delimiter, equipment: equipment)
    }

    var depthIndex: Int?
    var qcIndex: Int?
    var fsIndex: Int?
    var u2Index: Int?
    var icIndex: Int?

    for (idx, header) in headers.enumerated() {
      let normalized = header.replacingOccurrences(of: " ", with: "")
      if depthIndex == nil,
         normalized == "depth_(m)" || normalized == "depth_m" || normalized == "depth(m)" || normalized == "depth" || normalized == "z"
      {
        depthIndex = idx
      } else if qcIndex == nil,
                normalized == "qc_(mpa)" || normalized == "qc(mpa)" || normalized == "qc_mpa(mpa)" || normalized == "qc_mpa" || normalized == "qc" || normalized == "tip"
      {
        qcIndex = idx
      } else if fsIndex == nil,
                normalized == "fs_(kpa)" || normalized == "fs(kpa)" || normalized == "fs_kpa(kpa)" || normalized == "fs_kpa" || normalized == "fs" || normalized == "sleeve"
      {
        fsIndex = idx
      } else if u2Index == nil,
                normalized == "u2_(kpa)" || normalized == "u2(kpa)" || normalized == "u2_kpa(kpa)" || normalized == "u2_kpa" || normalized == "u2" || normalized == "pore_pressure_kpa"
      {
        u2Index = idx
      } else if icIndex == nil,
                normalized == "ic" || normalized == "robertson_ic"
      {
        icIndex = idx
      }
    }

    var matchedColumns: [String] = []
    if depthIndex != nil {
      matchedColumns.append("depth_(m)")
    }
    if qcIndex != nil {
      matchedColumns.append("qc_(MPa)")
    }
    if fsIndex != nil {
      matchedColumns.append("fs_(kPa)")
    }
    if u2Index != nil {
      matchedColumns.append("u2_(kPa)")
    }

    guard let dIdx = depthIndex, let qIdx = qcIndex, let fIdx = fsIndex,
          cptType != .cptu || u2Index != nil else {
      return CPTCSVParseResult(rows: [], matchedRequiredColumns: matchedColumns,
                               error: "Kolom wajib tidak lengkap: \(cptType.requiredColumns.joined(separator: ", ")).")
    }

    var parsedByDepth: [Int: CPTRowData] = [:]

    for (offset, line) in rawLines.dropFirst().enumerated() {
      let fields = splitCSVRow(line, delimiter: delimiter)
      guard dIdx < fields.count, qIdx < fields.count, fIdx < fields.count else {
        return CPTCSVParseResult(rows: [], matchedRequiredColumns: matchedColumns,
                                 error: "Baris \(offset + 2): jumlah kolom tidak lengkap.")
      }

      guard
        let depth = parseDouble(fields[dIdx]),
        let qc = parseDouble(fields[qIdx]),
        depth.isFinite,
        qc.isFinite,
        depth >= 0,
        qc >= 0
      else {
        return CPTCSVParseResult(rows: [], matchedRequiredColumns: matchedColumns,
                                 error: "Baris \(offset + 2): depth (m) atau qc (MPa) tidak valid.")
      }

      guard let fs = parseDouble(fields[fIdx]), fs.isFinite, fs >= 0 else {
        return CPTCSVParseResult(rows: [], matchedRequiredColumns: matchedColumns,
                                 error: "Baris \(offset + 2): fs (kPa) tidak valid.")
      }
      if cptType == .cptu {
        guard let uIdx = u2Index, uIdx < fields.count,
              let u2 = parseDouble(fields[uIdx]), u2.isFinite else {
          return CPTCSVParseResult(rows: [], matchedRequiredColumns: matchedColumns,
                                   error: "Baris \(offset + 2): u2 (kPa) tidak valid.")
        }
      }
      if let iIdx = icIndex {
        guard iIdx < fields.count, let ic = parseDouble(fields[iIdx]), ic.isFinite, ic > 0 else {
          return CPTCSVParseResult(rows: [], matchedRequiredColumns: matchedColumns,
                                   error: "Baris \(offset + 2): Ic tidak valid.")
        }
      }

      let u2: Double? = {
        guard cptType == .cptu else { return nil }
        if let uIdx = u2Index, uIdx < fields.count, let val = parseDouble(fields[uIdx]), val.isFinite {
          return val
        }
        return nil
      }()

      let explicitIc: Double? = {
        if let iIdx = icIndex, iIdx < fields.count, let val = parseDouble(fields[iIdx]), val.isFinite, val > 0 {
          return val
        }
        return nil
      }()

      // Key by millimeter to deduplicate identical depths while preserving sub-centimeter steps
      let depthKey = Int((depth * 1000.0).rounded())
      parsedByDepth[depthKey] = CPTRowData(
        depth: depth,
        coneResistance: qc,
        localFriction: fs,
        porePressure: u2,
        explicitIc: explicitIc,
        cptType: cptType,
        netAreaRatio: cptType == .cptu ? equipment.netAreaRatio : nil
      )
    }

    let sortedRows = parsedByDepth.values.sorted { $0.depth < $1.depth }
    return CPTCSVParseResult(rows: sortedRows, matchedRequiredColumns: matchedColumns,
                             error: sortedRows.isEmpty ? "CSV tidak memiliki data CPT." : nil)
  }

  private static func parseBiconeCSV(
    rawLines: [String],
    headers: [String],
    delimiter: Character,
    equipment: CPTEquipmentParameters
  ) -> CPTCSVParseResult {
    var depthCmIndex: Int?
    var cwIndex: Int?
    var twIndex: Int?
    var icIndex: Int?

    for (idx, header) in headers.enumerated() {
      let normalized = header.replacingOccurrences(of: " ", with: "")
      if depthCmIndex == nil,
         normalized == "depth_(cm)" || normalized == "depth_cm" || normalized == "depth(cm)"
      {
        depthCmIndex = idx
      } else if cwIndex == nil,
                normalized == "cw_(kg/cm2)" || normalized == "cw(kg/cm2)" || normalized == "cw"
      {
        cwIndex = idx
      } else if twIndex == nil,
                normalized == "tw_(kg/cm2)" || normalized == "tw(kg/cm2)" || normalized == "tw"
      {
        twIndex = idx
      } else if icIndex == nil,
                normalized == "ic" || normalized == "robertson_ic"
      {
        icIndex = idx
      }
    }

    var matchedColumns: [String] = []
    if depthCmIndex != nil {
      matchedColumns.append("depth_(cm)")
    }
    if cwIndex != nil {
      matchedColumns.append("Cw_(kg/cm2)")
    }
    if twIndex != nil {
      matchedColumns.append("Tw_(kg/cm2)")
    }

    guard let dIdx = depthCmIndex, let cIdx = cwIndex, let tIdx = twIndex else {
      return CPTCSVParseResult(rows: [], matchedRequiredColumns: matchedColumns,
                               error: "Kolom wajib tidak lengkap: \(CPTType.cptmBicone.requiredColumns.joined(separator: ", ")).")
    }

    let dpi = max(equipment.pistonDiameterCm, 0.1)
    let dc = max(equipment.coneDiameterCm, 0.1)
    let ds = max(equipment.frictionSleeveDiameterCm, 0.1)
    let ls = max(equipment.frictionSleeveLengthCm, 0.1)

    let coneAreaRatio = (dpi / dc) * (dpi / dc)
    let sleeveAreaRatio = (dpi * dpi) / (4.0 * ds * ls)

    var parsedByDepth: [Int: CPTRowData] = [:]

    for (offset, line) in rawLines.dropFirst().enumerated() {
      let fields = splitCSVRow(line, delimiter: delimiter)
      guard dIdx < fields.count, cIdx < fields.count, tIdx < fields.count else {
        return CPTCSVParseResult(rows: [], matchedRequiredColumns: matchedColumns,
                                 error: "Baris \(offset + 2): jumlah kolom tidak lengkap.")
      }

      guard
        let depthCm = parseDouble(fields[dIdx]),
        let cwKgCm2 = parseDouble(fields[cIdx]),
        depthCm.isFinite,
        cwKgCm2.isFinite,
        depthCm >= 0,
        cwKgCm2 >= 0
      else {
        return CPTCSVParseResult(rows: [], matchedRequiredColumns: matchedColumns,
                                 error: "Baris \(offset + 2): depth atau Cw tidak valid.")
      }

      guard let twKgCm2 = parseDouble(fields[tIdx]), twKgCm2.isFinite, twKgCm2 >= 0 else {
        return CPTCSVParseResult(rows: [], matchedRequiredColumns: matchedColumns,
                                 error: "Baris \(offset + 2): Tw tidak valid.")
      }
      if let iIdx = icIndex {
        guard iIdx < fields.count, let ic = parseDouble(fields[iIdx]), ic.isFinite, ic > 0 else {
          return CPTCSVParseResult(rows: [], matchedRequiredColumns: matchedColumns,
                                   error: "Baris \(offset + 2): Ic tidak valid.")
        }
      }

      let explicitIc: Double? = {
        if let iIdx = icIndex, iIdx < fields.count, let val = parseDouble(fields[iIdx]), val.isFinite, val > 0 {
          return val
        }
        return nil
      }()

      let depthM = depthCm / 100.0
      let qcKgCm2 = cwKgCm2 * coneAreaRatio
      let qcMPa = qcKgCm2 * 0.0980665

      let deltaPw = twKgCm2 >= cwKgCm2 ? (twKgCm2 - cwKgCm2) : max(twKgCm2, 0.0)
      let fsKgCm2 = deltaPw * sleeveAreaRatio
      let fsKPa = fsKgCm2 * 98.0665

      let depthKey = Int((depthM * 1000.0).rounded())
      parsedByDepth[depthKey] = CPTRowData(
        depth: depthM,
        coneResistance: qcMPa,
        localFriction: fsKPa,
        porePressure: nil,
        explicitIc: explicitIc,
        cptType: .cptmBicone
      )
    }

    let sortedRows = parsedByDepth.values.sorted { $0.depth < $1.depth }
    return CPTCSVParseResult(rows: sortedRows, matchedRequiredColumns: matchedColumns,
                             error: sortedRows.isEmpty ? "CSV tidak memiliki data CPT." : nil)
  }

  static func parseDouble(_ raw: String) -> Double? {
    let trimmed = raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\"", with: "")
      .replacingOccurrences(of: ",", with: ".")
    return Double(trimmed)
  }

  private static func splitCSVRow(_ line: String, delimiter: Character) -> [String] {
    var result: [String] = []
    var current = ""
    var inQuotes = false

    for char in line {
      if char == "\"" {
        inQuotes.toggle()
      } else if char == delimiter, !inQuotes {
        result.append(current)
        current = ""
      } else {
        current.append(char)
      }
    }
    result.append(current)
    return result
  }
}
