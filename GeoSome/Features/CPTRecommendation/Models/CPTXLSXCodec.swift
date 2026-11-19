import Foundation
import zlib

enum CPTXLSXCodec {
  // MARK: - Template Generator (produces a valid .xlsx file with headers)

  static func generateTemplate(for cptType: CPTType) -> Data {
    let headers = cptType.requiredColumns

    // Build row 1 with inlineStr cells
    var rowCellsXML = ""
    for (i, h) in headers.enumerated() {
      let colLetter = columnLetter(for: i)
      let escapedHeader = xmlEscape(h)
      rowCellsXML += "<c r=\"\(colLetter)1\" t=\"inlineStr\"><is><t>\(escapedHeader)</t></is></c>"
    }

    let sheetXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <sheetData>
        <row r="1">\(rowCellsXML)</row>
      </sheetData>
    </worksheet>
    """

    let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    </Types>
    """

    let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    let workbookRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    </Relationships>
    """

    let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets>
        <sheet name="Sheet1" sheetId="1" r:id="rId1"/>
      </sheets>
    </workbook>
    """

    let files: [(name: String, data: Data)] = [
      ("[Content_Types].xml", Data(contentTypesXML.utf8)),
      ("_rels/.rels", Data(rootRelsXML.utf8)),
      ("xl/_rels/workbook.xml.rels", Data(workbookRelsXML.utf8)),
      ("xl/workbook.xml", Data(workbookXML.utf8)),
      ("xl/worksheets/sheet1.xml", Data(sheetXML.utf8))
    ]

    return makeZip(files: files)
  }

  // MARK: - XLSX Extractor (extracts CSV text from an .xlsx file)

  static func extractCSVText(from data: Data) -> String? {
    // 1. If data doesn't start with PK magic, check if it's already plain text (CSV)
    guard data.count >= 4, data[0] == 0x50, data[1] == 0x4B, data[2] == 0x03, data[3] == 0x04 else {
      return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
    }

    // 2. Unzip files from the container
    let unzipped = unzipEntries(from: data)

    // Check for shared strings
    var sharedStrings: [String] = []
    if let ssData = unzipped["xl/sharedStrings.xml"],
       let ssText = String(data: ssData, encoding: .utf8) {
      sharedStrings = parseSharedStrings(from: ssText)
    }

    // Find sheet1.xml (or any first sheet)
    var sheetData = unzipped["xl/worksheets/sheet1.xml"]
    if sheetData == nil {
      for (name, d) in unzipped where name.contains("sheet") && name.hasSuffix(".xml") {
        sheetData = d
        break
      }
    }

    guard let sheetData, let sheetXML = String(data: sheetData, encoding: .utf8) else {
      return nil
    }

    return parseSheetToCSV(sheetXML: sheetXML, sharedStrings: sharedStrings)
  }

  // MARK: - Private ZIP Writer (Method 0: STORED)

  private static func makeZip(files: [(name: String, data: Data)]) -> Data {
    var localHeaders = Data()
    var centralDirectory = Data()
    var offset: UInt32 = 0

    for file in files {
      let nameBytes = Data(file.name.utf8)
      let size = UInt32(file.data.count)
      let crc = file.data.withUnsafeBytes { raw in
        UInt32(crc32(0, raw.bindMemory(to: Bytef.self).baseAddress, uInt(file.data.count)))
      }

      // Local Header (30 bytes + name + data)
      var lh = Data()
      lh.appendUInt32(0x04034B50) // signature
      lh.appendUInt16(20)         // version needed (2.0)
      lh.appendUInt16(0)          // general purpose bit flag
      lh.appendUInt16(0)          // compression method (0 = stored)
      lh.appendUInt16(0)          // last mod file time
      lh.appendUInt16(0)          // last mod file date
      lh.appendUInt32(crc)        // crc-32
      lh.appendUInt32(size)       // compressed size
      lh.appendUInt32(size)       // uncompressed size
      lh.appendUInt16(UInt16(nameBytes.count)) // file name length
      lh.appendUInt16(0)          // extra field length
      lh.append(nameBytes)
      lh.append(file.data)

      // Central Directory Entry (46 bytes + name)
      var cd = Data()
      cd.appendUInt32(0x02014B50) // signature
      cd.appendUInt16(20)         // version made by
      cd.appendUInt16(20)         // version needed
      cd.appendUInt16(0)          // general purpose bit flag
      cd.appendUInt16(0)          // compression method
      cd.appendUInt16(0)          // last mod time
      cd.appendUInt16(0)          // last mod date
      cd.appendUInt32(crc)        // crc-32
      cd.appendUInt32(size)       // compressed size
      cd.appendUInt32(size)       // uncompressed size
      cd.appendUInt16(UInt16(nameBytes.count)) // file name length
      cd.appendUInt16(0)          // extra field length
      cd.appendUInt16(0)          // file comment length
      cd.appendUInt16(0)          // disk number start
      cd.appendUInt16(0)          // internal file attributes
      cd.appendUInt32(0)          // external file attributes
      cd.appendUInt32(offset)     // relative offset of local header
      cd.append(nameBytes)

      offset += UInt32(lh.count)
      localHeaders.append(lh)
      centralDirectory.append(cd)
    }

    let cdOffset = UInt32(localHeaders.count)
    let cdSize = UInt32(centralDirectory.count)
    let totalEntries = UInt16(files.count)

    // End of Central Directory Record (22 bytes)
    var eocd = Data()
    eocd.appendUInt32(0x06054B50) // signature
    eocd.appendUInt16(0)          // number of this disk
    eocd.appendUInt16(0)          // disk with central directory
    eocd.appendUInt16(totalEntries) // total entries this disk
    eocd.appendUInt16(totalEntries) // total entries
    eocd.appendUInt32(cdSize)     // size of central directory
    eocd.appendUInt32(cdOffset)   // offset of central directory
    eocd.appendUInt16(0)          // comment length

    var result = Data()
    result.append(localHeaders)
    result.append(centralDirectory)
    result.append(eocd)
    return result
  }

  // MARK: - Private ZIP Reader

  private static func unzipEntries(from data: Data) -> [String: Data] {
    var result: [String: Data] = [:]
    var offset = 0

    while offset + 30 <= data.count {
      let sig = data.loadUInt32(at: offset)
      guard sig == 0x04034B50 else { break }

      let method = data.loadUInt16(at: offset + 8)
      let compressedSize = Int(data.loadUInt32(at: offset + 18))
      let uncompressedSize = Int(data.loadUInt32(at: offset + 22))
      let nameLen = Int(data.loadUInt16(at: offset + 26))
      let extraLen = Int(data.loadUInt16(at: offset + 28))

      let nameStart = offset + 30
      let nameEnd = nameStart + nameLen
      guard nameEnd <= data.count else { break }

      let nameData = data.subdata(in: nameStart..<nameEnd)
      let name = String(decoding: nameData, as: UTF8.self)

      let dataStart = nameEnd + extraLen
      let dataEnd = dataStart + compressedSize
      guard dataEnd <= data.count else { break }

      let rawData = data.subdata(in: dataStart..<dataEnd)

      if method == 0 {
        result[name] = rawData
      } else if method == 8 {
        if let decomp = decompressDeflate(rawData, uncompressedSize: uncompressedSize) {
          result[name] = decomp
        }
      }

      offset = dataEnd
    }

    return result
  }

  private static func decompressDeflate(_ compressed: Data, uncompressedSize: Int) -> Data? {
    var decompressed = Data(count: max(uncompressedSize, 4096))
    var stream = z_stream()
    let initStatus = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
    guard initStatus == Z_OK else { return nil }
    defer { inflateEnd(&stream) }

    compressed.withUnsafeBytes { rawIn in
      stream.next_in = UnsafeMutablePointer<Bytef>(mutating: rawIn.bindMemory(to: Bytef.self).baseAddress)
      stream.avail_in = uInt(compressed.count)

      decompressed.withUnsafeMutableBytes { rawOut in
        stream.next_out = rawOut.bindMemory(to: Bytef.self).baseAddress
        stream.avail_out = uInt(decompressed.count)
        _ = inflate(&stream, Z_FINISH)
      }
    }

    let actualCount = Int(stream.total_out)
    guard actualCount > 0 else { return nil }
    decompressed.count = actualCount
    return decompressed
  }

  // MARK: - Private XML Sheet Parser to CSV

  private static func parseSharedStrings(from xml: String) -> [String] {
    var result: [String] = []
    let siPattern = try? NSRegularExpression(pattern: "<si>(.*?)</si>", options: [.dotMatchesLineSeparators])
    let tPattern = try? NSRegularExpression(pattern: "<t[^>]*>(.*?)</t>", options: [.dotMatchesLineSeparators])

    guard let siPattern, let tPattern else { return result }
    let nsXML = xml as NSString
    let siMatches = siPattern.matches(in: xml, range: NSRange(location: 0, length: nsXML.length))

    for si in siMatches {
      let siSub = nsXML.substring(with: si.range(at: 1))
      let nsSub = siSub as NSString
      let tMatches = tPattern.matches(in: siSub, range: NSRange(location: 0, length: nsSub.length))
      let combined = tMatches.map { nsSub.substring(with: $0.range(at: 1)) }.joined()
      result.append(xmlUnescape(combined))
    }

    return result
  }

  private static func parseSheetToCSV(sheetXML: String, sharedStrings: [String]) -> String {
    let rowRegex = try? NSRegularExpression(pattern: "<row[^>]*>(.*?)</row>", options: [.dotMatchesLineSeparators])
    let cellRegex = try? NSRegularExpression(pattern: "<c\\s+([^>]*)>(.*?)</c>", options: [.dotMatchesLineSeparators])

    guard let rowRegex, let cellRegex else { return "" }
    let nsSheet = sheetXML as NSString
    let rowMatches = rowRegex.matches(in: sheetXML, range: NSRange(location: 0, length: nsSheet.length))

    var csvLines: [String] = []

    for rMatch in rowMatches {
      let rowContent = nsSheet.substring(with: rMatch.range(at: 1))
      let nsRow = rowContent as NSString
      let cMatches = cellRegex.matches(in: rowContent, range: NSRange(location: 0, length: nsRow.length))

      var rowValues: [(colIndex: Int, value: String)] = []

      for cMatch in cMatches {
        let attrStr = nsRow.substring(with: cMatch.range(at: 1))
        let bodyStr = nsRow.substring(with: cMatch.range(at: 2))

        let colIdx = parseColumnIndex(from: attrStr)
        let isString = attrStr.contains("t=\"s\"")
        let isInlineStr = attrStr.contains("t=\"inlineStr\"")

        var val = ""
        if isString {
          if let vMatch = bodyStr.range(of: "<v>(.*?)</v>", options: .regularExpression) {
            let numStr = bodyStr[vMatch].replacingOccurrences(of: "<v>", with: "").replacingOccurrences(of: "</v>", with: "")
            if let idx = Int(numStr), idx >= 0 && idx < sharedStrings.count {
              val = sharedStrings[idx]
            }
          }
        } else if isInlineStr || bodyStr.contains("<t>") {
          if let tMatch = bodyStr.range(of: "<t[^>]*>(.*?)</t>", options: .regularExpression) {
            let rawT = bodyStr[tMatch]
              .replacingOccurrences(of: "^<t[^>]*>", with: "", options: .regularExpression)
              .replacingOccurrences(of: "</t>$", with: "", options: .regularExpression)
            val = xmlUnescape(rawT)
          }
        } else if let vMatch = bodyStr.range(of: "<v>(.*?)</v>", options: .regularExpression) {
          val = bodyStr[vMatch].replacingOccurrences(of: "<v>", with: "").replacingOccurrences(of: "</v>", with: "")
        }

        rowValues.append((colIndex: colIdx, value: val))
      }

      guard !rowValues.isEmpty else { continue }
      rowValues.sort { $0.colIndex < $1.colIndex }

      // Fill in any gaps between columns
      var cols: [String] = []
      var currentIdx = 0
      for item in rowValues {
        while currentIdx < item.colIndex {
          cols.append("")
          currentIdx += 1
        }
        cols.append(item.value)
        currentIdx += 1
      }

      let csvRow = cols.map { escapeCSVField($0) }.joined(separator: ",")
      csvLines.append(csvRow)
    }

    return csvLines.joined(separator: "\n")
  }

  private static func parseColumnIndex(from attr: String) -> Int {
    guard let range = attr.range(of: "r=\"([A-Z]+)[0-9]+\"", options: .regularExpression) else { return 0 }
    let ref = String(attr[range]).replacingOccurrences(of: "r=\"", with: "").replacingOccurrences(of: "\"", with: "")
    let letters = ref.filter { $0.isLetter }
    var sum = 0
    for char in letters.uppercased() {
      if let ascii = char.asciiValue {
        sum = sum * 26 + Int(ascii - 64)
      }
    }
    return max(sum - 1, 0)
  }

  private static func columnLetter(for index: Int) -> String {
    let scalar = UnicodeScalar(65 + index)!
    return String(Character(scalar))
  }

  private static func xmlEscape(_ str: String) -> String {
    str.replacingOccurrences(of: "&", with: "&amp;")
       .replacingOccurrences(of: "<", with: "&lt;")
       .replacingOccurrences(of: ">", with: "&gt;")
       .replacingOccurrences(of: "\"", with: "&quot;")
  }

  private static func xmlUnescape(_ str: String) -> String {
    str.replacingOccurrences(of: "&lt;", with: "<")
       .replacingOccurrences(of: "&gt;", with: ">")
       .replacingOccurrences(of: "&quot;", with: "\"")
       .replacingOccurrences(of: "&amp;", with: "&")
  }

  private static func escapeCSVField(_ field: String) -> String {
    if field.contains(",") || field.contains("\"") || field.contains("\n") {
      let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
      return "\"\(escaped)\""
    }
    return field
  }
}

private extension Data {
  mutating func appendUInt16(_ value: UInt16) {
    var v = value.littleEndian
    Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
  }

  mutating func appendUInt32(_ value: UInt32) {
    var v = value.littleEndian
    Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
  }

  func loadUInt16(at offset: Int) -> UInt16 {
    withUnsafeBytes { raw in
      raw.load(fromByteOffset: offset, as: UInt16.self).littleEndian
    }
  }

  func loadUInt32(at offset: Int) -> UInt32 {
    withUnsafeBytes { raw in
      raw.load(fromByteOffset: offset, as: UInt32.self).littleEndian
    }
  }
}
