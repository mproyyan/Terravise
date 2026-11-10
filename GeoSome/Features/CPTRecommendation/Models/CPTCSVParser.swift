import Foundation

struct CPTCSVParseResult: Sendable {
  let rows: [CPTRowData]
  let matchedRequiredColumns: [String]
}

enum CPTCSVParser {
  static func parse(
    url: URL,
    cptType: CPTType,
    equipment: CPTEquipmentParameters = CPTEquipmentParameters()
  ) -> CPTCSVParseResult {
    guard let rawText = (try? String(contentsOf: url, encoding: .utf8))
      ?? (try? String(contentsOf: url, encoding: .ascii))
    else {
      return CPTCSVParseResult(rows: [], matchedRequiredColumns: [])
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
      return CPTCSVParseResult(rows: [], matchedRequiredColumns: [])
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
      if depthIndex == nil,
         header == "depth_(m)" || header == "depth_m" || header == "depth" || header == "z" || header.hasPrefix("depth")
      {
        depthIndex = idx
      } else if qcIndex == nil,
                header == "qc_mpa(mpa)" || header == "qc_mpa" || header == "qc" || header == "tip" || header.hasPrefix("qc")
      {
        qcIndex = idx
      } else if fsIndex == nil,
                header == "fs_kpa(kpa)" || header == "fs_kpa" || header == "fs" || header == "sleeve" || header.hasPrefix("fs")
      {
        fsIndex = idx
      } else if u2Index == nil,
                header == "u2_kpa(kpa)" || header == "u2_kpa" || header == "u2" || header.hasPrefix("u2") || header.contains("pore")
      {
        u2Index = idx
      } else if icIndex == nil,
                header == "ic" || header == "robertson_ic"
      {
        icIndex = idx
      }
    }

    var matchedColumns: [String] = []
    if depthIndex != nil {
      matchedColumns.append("depth_(m)")
    }
    if qcIndex != nil {
      matchedColumns.append("qc_mpa(mPa)")
    }
    if fsIndex != nil {
      matchedColumns.append("fs_kpa(kPa)")
    }
    if u2Index != nil {
      matchedColumns.append("u2_kpa(kPa)")
    }

    guard let dIdx = depthIndex, let qIdx = qcIndex else {
      return CPTCSVParseResult(rows: [], matchedRequiredColumns: matchedColumns)
    }

    var parsedByDepth: [Int: CPTRowData] = [:]

    for line in rawLines.dropFirst() {
      let fields = splitCSVRow(line, delimiter: delimiter)
      guard dIdx < fields.count, qIdx < fields.count else { continue }

      guard
        let depth = parseDouble(fields[dIdx]),
        let qc = parseDouble(fields[qIdx]),
        depth.isFinite,
        qc.isFinite,
        depth >= 0,
        qc >= 0
      else {
        continue
      }

      let fs: Double = {
        if let fIdx = fsIndex, fIdx < fields.count, let val = parseDouble(fields[fIdx]), val.isFinite {
          return max(val, 0.0)
        }
        return 0.0
      }()

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
    return CPTCSVParseResult(rows: sortedRows, matchedRequiredColumns: matchedColumns)
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
         normalized == "depth_(cm)" || normalized == "depth_cm" || normalized == "depth(cm)" || normalized.hasPrefix("depth")
      {
        depthCmIndex = idx
      } else if cwIndex == nil,
                normalized == "cw_(kg/cm2)" || normalized == "cw(kg/cm2)" || normalized == "cw" || normalized.hasPrefix("cw")
      {
        cwIndex = idx
      } else if twIndex == nil,
                normalized == "tw_(kg/cm2)" || normalized == "tw(kg/cm2)" || normalized == "tw" || normalized.hasPrefix("tw")
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

    guard let dIdx = depthCmIndex, let cIdx = cwIndex else {
      return CPTCSVParseResult(rows: [], matchedRequiredColumns: matchedColumns)
    }

    let dpi = max(equipment.pistonDiameterCm, 0.1)
    let dc = max(equipment.coneDiameterCm, 0.1)
    let ds = max(equipment.frictionSleeveDiameterCm, 0.1)
    let ls = max(equipment.frictionSleeveLengthCm, 0.1)

    let coneAreaRatio = (dpi / dc) * (dpi / dc)
    let sleeveAreaRatio = (dpi * dpi) / (4.0 * ds * ls)

    var parsedByDepth: [Int: CPTRowData] = [:]

    for line in rawLines.dropFirst() {
      let fields = splitCSVRow(line, delimiter: delimiter)
      guard dIdx < fields.count, cIdx < fields.count else { continue }

      guard
        let depthCm = parseDouble(fields[dIdx]),
        let cwKgCm2 = parseDouble(fields[cIdx]),
        depthCm.isFinite,
        cwKgCm2.isFinite,
        depthCm >= 0,
        cwKgCm2 >= 0
      else {
        continue
      }

      let twKgCm2: Double = {
        if let tIdx = twIndex, tIdx < fields.count, let val = parseDouble(fields[tIdx]), val.isFinite {
          return max(val, 0.0)
        }
        return cwKgCm2
      }()

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
    return CPTCSVParseResult(rows: sortedRows, matchedRequiredColumns: matchedColumns)
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
