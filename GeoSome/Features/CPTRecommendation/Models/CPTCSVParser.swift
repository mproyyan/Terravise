import Foundation

struct CPTCSVParseResult: Sendable {
  let rows: [CPTRowData]
  let matchedRequiredColumns: [String]
}

enum CPTCSVParser {
  static func parse(url: URL, cptType: CPTType) -> CPTCSVParseResult {
    guard let rawText = (try? String(contentsOf: url, encoding: .utf8))
      ?? (try? String(contentsOf: url, encoding: .ascii))
    else {
      return CPTCSVParseResult(rows: [], matchedRequiredColumns: [])
    }
    return parse(text: rawText, cptType: cptType)
  }

  static func parse(text: String, cptType: CPTType) -> CPTCSVParseResult {
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
        explicitIc: explicitIc
      )
    }

    let sortedRows = parsedByDepth.values.sorted { $0.depth < $1.depth }
    return CPTCSVParseResult(rows: sortedRows, matchedRequiredColumns: matchedColumns)
  }

  private static func parseDouble(_ raw: String) -> Double? {
    let trimmed = raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\"", with: "")
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
