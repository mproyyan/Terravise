import SwiftUI
import UniformTypeIdentifiers

struct CPTUploadDataSheetView: View {
  @Binding var selectedCPTType: CPTType
  @Binding var zoneText: String
  @Binding var eastingText: String
  @Binding var northingText: String
  @Binding var uploadedFile: CPTUploadedFile?
  @Binding var parsedRows: [CPTRowData]
  @Binding var validationError: String?
  var equipmentParameters: Binding<CPTEquipmentParameters>?
  var showCPTTypeSelection: Bool = false
  var onCloseTap: (() -> Void)?
  var onSubmitTap: (() -> Void)?
  var onDownloadTemplate: (() -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
  @State private var isDocumentPickerPresented: Bool = false
  @State private var isDropTargetActive: Bool = false
  @State private var isShareTemplatePresented: Bool = false
  @State private var lastLoadedCSVText: String?
  @State private var importError: String?

  // Equipment Parameter Inputs (CPTu & CPTm)
  @State private var netAreaRatioText: String = "0,8"
  @State private var pistonDiameterText: String = "3,57"
  @State private var coneDiameterText: String = "3,57"
  @State private var frictionSleeveDiameterText: String = "3,57"
  @State private var frictionSleeveLengthText: String = "13,3"

  init(
    selectedCPTType: Binding<CPTType>,
    zoneText: Binding<String>,
    eastingText: Binding<String>,
    northingText: Binding<String>,
    uploadedFile: Binding<CPTUploadedFile?>,
    parsedRows: Binding<[CPTRowData]> = .constant([]),
    validationError: Binding<String?> = .constant(nil),
    equipmentParameters: Binding<CPTEquipmentParameters>? = nil,
    showCPTTypeSelection: Bool = false,
    onCloseTap: (() -> Void)? = nil,
    onSubmitTap: (() -> Void)? = nil,
    onDownloadTemplate: (() -> Void)? = nil
  ) {
    _selectedCPTType = selectedCPTType
    _zoneText = zoneText
    _eastingText = eastingText
    _northingText = northingText
    _uploadedFile = uploadedFile
    _parsedRows = parsedRows
    _validationError = validationError
    self.equipmentParameters = equipmentParameters
    self.showCPTTypeSelection = showCPTTypeSelection
    self.onCloseTap = onCloseTap
    self.onSubmitTap = onSubmitTap
    self.onDownloadTemplate = onDownloadTemplate
  }

  private var allRequiredColumnsMatched: Bool {
    guard let file = uploadedFile else { return false }
    return selectedCPTType.requiredColumns.allSatisfy { file.isColumnMatched($0) }
  }

  private var isSubmitEnabled: Bool {
    guard let file = uploadedFile else { return false }
    let hasCoords = !zoneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !eastingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !northingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return hasCoords && !parsedRows.isEmpty && file.rowCount == parsedRows.count && allRequiredColumnsMatched && importError == nil
  }

  private var isFileUploaded: Bool {
    uploadedFile != nil
  }

  private var templateFileURL: URL {
    let fileName = "cpt_template_\(selectedCPTType.nameIdentifier).xlsx"
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    let xlsxData = CPTXLSXCodec.generateTemplate(for: selectedCPTType)
    try? xlsxData.write(to: tempURL)
    return tempURL
  }

  private var currentEquipmentParameters: CPTEquipmentParameters {
    if showCPTTypeSelection {
      return CPTEquipmentParameters(
        netAreaRatio: CPTCSVParser.parseDouble(netAreaRatioText) ?? 0.80,
        pistonDiameterCm: CPTCSVParser.parseDouble(pistonDiameterText) ?? 3.57,
        coneDiameterCm: CPTCSVParser.parseDouble(coneDiameterText) ?? 3.57,
        frictionSleeveDiameterCm: CPTCSVParser.parseDouble(frictionSleeveDiameterText) ?? 3.57,
        frictionSleeveLengthCm: CPTCSVParser.parseDouble(frictionSleeveLengthText) ?? 13.3
      )
    }
    return equipmentParameters?.wrappedValue ?? CPTEquipmentParameters()
  }

  var body: some View {
    NavigationStack {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 20) {
          if showCPTTypeSelection {
            cptTypeSection
            requiredColumnsSection
          }
          coordinatesSection
          cptFileSection
          if isFileUploaded {
            requiredColumnsCard
          }
          if let validationError {
            Text(validationError).font(.caption).foregroundStyle(.red)
          } else if !isSubmitEnabled && importError == nil {
            Text("Enter the coordinates and select a valid CPT CSV file to proceed.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
      }
      .scrollBounceBehavior(.basedOnSize)
      .onChange(of: zoneText) { _, _ in validationError = nil }
      .onChange(of: eastingText) { _, _ in validationError = nil }
      .onChange(of: northingText) { _, _ in validationError = nil }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .navigationTitle("Upload Data CPT")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        // Leading: Native Close (X) button matching BoundaryEditCoordinateSheetView
        ToolbarItem(placement: .cancellationAction) {
          Button(role: .close) {
            onCloseTap?()
          }
          .accessibilityLabel("Cancel")
          .accessibilityHint("Closes the CPT upload sheet")
        }

        // Trailing: Native Confirm (Checkmark) button matching BoundaryEditCoordinateSheetView
        ToolbarItem(placement: .confirmationAction) {
          Button(role: .confirm) {
            if isSubmitEnabled {
              equipmentParameters?.wrappedValue = currentEquipmentParameters
              onSubmitTap?()
            }
          }
          .keyboardShortcut(nil)
          .disabled(!isSubmitEnabled)
          .accessibilityLabel("Submit CPT Data")
          .accessibilityHint(
            isSubmitEnabled
              ? "Saves and uploads the CPT data"
              : "Enter coordinates and select a file to enable upload"
          )
        }
      }
      .fileImporter(
        isPresented: $isDocumentPickerPresented,
        allowedContentTypes: [
          .commaSeparatedText,
          UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,
          .data
        ],
        allowsMultipleSelection: false
      ) { result in
        switch result {
        case let .success(urls):
          guard let url = urls.first else { return }
          let hasAccess = url.startAccessingSecurityScopedResource()
          defer {
            if hasAccess {
              url.stopAccessingSecurityScopedResource()
            }
          }
          handleFile(url: url)
        case let .failure(error):
          importError = "File tidak dapat dibuka: \(error.localizedDescription)"
        }
      }
    }
  }

  // MARK: - Sections

  private var cptTypeSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Type Data CPT")
        .font(.headline.weight(.bold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)

      HStack {
        Text("CPT Type")
          .font(.body)
          .foregroundStyle(Color.primary)

        Spacer()

        Menu {
          ForEach(CPTType.allCases) { type in
            Button(action: {
              selectedCPTType = type
              if let file = uploadedFile, let lastText = lastLoadedCSVText {
                let reparse = CPTCSVParser.parse(text: lastText, cptType: type, equipment: currentEquipmentParameters)
                parsedRows = reparse.rows
                uploadedFile = CPTUploadedFile(
                  id: file.id,
                  name: file.name,
                  byteSize: file.byteSize,
                  rowCount: reparse.rows.count,
                  matchedColumns: reparse.matchedRequiredColumns
                )
                if let err = reparse.error {
                  importError = err
                } else {
                  importError = nil
                }
              }
            }) {
              HStack {
                Text(type.displayName)
                if selectedCPTType == type {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
        } label: {
          HStack(spacing: 4) {
            Text(selectedCPTType.displayName)
              .font(.body)
              .foregroundStyle(Color.secondary)

            Image(systemName: "chevron.up.chevron.down")
              .font(.caption.weight(.semibold))
              .foregroundStyle(Color.secondary)
          }
          .padding(.vertical, 8)
          .padding(.leading, 8)
        }
      }
      .padding(.horizontal, 16)
      .frame(height: 52)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color(.secondarySystemGroupedBackground))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(
            Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
            lineWidth: contrast == .increased ? 1.5 : 1
          )
      )

      if selectedCPTType == .cptu {
        cptuEquipmentCard
      } else if selectedCPTType == .cptmBicone {
        cptmBiconeEquipmentCard
      }
    }
  }

  private var requiredColumnsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Required Columns")
        .font(.headline.weight(.bold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)

      VStack(alignment: .leading, spacing: 12) {
        Text("Make sure you have these columns in your file:\n**\(selectedCPTType.requiredColumns.joined(separator: ", "))**")
          .font(.subheadline)
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)

        Text("or follow this template:")
          .font(.subheadline)
          .foregroundStyle(Color.secondary)

        ShareLink(
          item: templateFileURL
        ) {
          HStack(spacing: 6) {
            Image(systemName: "square.and.arrow.down")
              .font(.subheadline.weight(.semibold))

            Text("Download Template")
              .font(.subheadline.weight(.semibold))
          }
          .foregroundStyle(Color.blue)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(Color.blue.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color(.secondarySystemGroupedBackground))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(
            Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
            lineWidth: contrast == .increased ? 1.5 : 1
          )
      )
    }
  }

  private var cptuEquipmentCard: some View {
    equipmentParameterRow(
      title: "Net Area Ratio (a)",
      placeholder: "0,8",
      text: $netAreaRatioText
    )
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
  }

  private var cptmBiconeEquipmentCard: some View {
    VStack(spacing: 0) {
      equipmentParameterRow(
        title: "Piston Diameter (Dpi)",
        placeholder: "3,57",
        text: $pistonDiameterText
      )

      Divider().padding(.horizontal, 16)

      equipmentParameterRow(
        title: "Cone Diameter (Dc)",
        placeholder: "3,57",
        text: $coneDiameterText
      )

      Divider().padding(.horizontal, 16)

      equipmentParameterRow(
        title: "Friction Sleeve Diameter (Ds)",
        placeholder: "3,57",
        text: $frictionSleeveDiameterText
      )

      Divider().padding(.horizontal, 16)

      equipmentParameterRow(
        title: "Friction Sleeve Length (Ls)",
        placeholder: "13,3",
        text: $frictionSleeveLengthText
      )
    }
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
  }

  private func equipmentParameterRow(
    title: String,
    placeholder: String,
    text: Binding<String>
  ) -> some View {
    HStack(spacing: 12) {
      Text(title)
        .font(.body)
        .foregroundStyle(Color.primary)
        .lineLimit(1)

      Spacer(minLength: 8)

      TextField(placeholder, text: text)
        #if canImport(UIKit)
        .keyboardType(.decimalPad)
        #endif
        .font(.body)
        .foregroundStyle(Color.secondary)
        .multilineTextAlignment(.trailing)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .frame(maxWidth: 110)
    }
    .padding(.horizontal, 16)
    .frame(height: 52)
  }

  private var coordinatesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Coordinates")
        .font(.headline.weight(.bold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)

      VStack(spacing: 0) {
        coordinateRow(
          title: "Zone",
          placeholder: "48S",
          text: $zoneText,
          keyboardType: .default,
          autocapitalization: .characters
        )

        Divider().padding(.horizontal, 16)

        coordinateRow(
          title: "Easting (m)",
          placeholder: "702634",
          text: $eastingText,
          keyboardType: .decimalPad
        )

        Divider().padding(.horizontal, 16)

        coordinateRow(
          title: "Northing (m)",
          placeholder: "9309747",
          text: $northingText,
          keyboardType: .decimalPad
        )
      }
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color(.secondarySystemGroupedBackground))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(
            Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
            lineWidth: contrast == .increased ? 1.5 : 1
          )
      )
      .accessibilityHint("Enter coordinates manually or tap inside the boundary area on the map")

      Text("Tap inside the boundary area on the map to set coordinates.")
        .font(.caption)
        .foregroundStyle(Color.secondary)
    }
  }

  private func coordinateRow(
    title: String,
    placeholder: String,
    text: Binding<String>,
    keyboardType: UIKeyboardType = .decimalPad,
    autocapitalization: TextInputAutocapitalization = .never
  ) -> some View {
    HStack(spacing: 12) {
      Text(title)
        .font(.body)
        .foregroundStyle(Color.primary)
        .lineLimit(1)

      Spacer(minLength: 8)

      TextField(placeholder, text: text)
        #if canImport(UIKit)
        .keyboardType(keyboardType)
        #endif
        .font(.body)
        .foregroundStyle(Color.secondary)
        .multilineTextAlignment(.trailing)
        .autocorrectionDisabled()
        .textInputAutocapitalization(autocapitalization)
        .frame(maxWidth: 130)
    }
    .padding(.horizontal, 16)
    .frame(height: 52)
  }

  private var requiredColumnsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header Status Text
      HStack(spacing: 8) {
        Image(systemName: allRequiredColumnsMatched ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(allRequiredColumnsMatched ? Color.green : Color.orange)

        Text(allRequiredColumnsMatched ? "All required columns are complete" : "Some required columns are missing")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.primary)

        Spacer()
      }

      // Column List
      VStack(spacing: 0) {
        ForEach(Array(selectedCPTType.requiredColumns.enumerated()), id: \.offset) { index, column in
          let isMatched = uploadedFile?.isColumnMatched(column) == true
          HStack {
            Text(column)
              .font(.subheadline.weight(.medium))
              .foregroundStyle(Color.primary)

            Spacer()

            if isMatched {
              HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                  .font(.caption.weight(.bold))

                Text("Match")
                  .font(.subheadline.weight(.medium))
              }
              .foregroundStyle(Color.green)
            } else {
              HStack(spacing: 4) {
                Image(systemName: "minus.circle.fill")
                  .font(.caption.weight(.bold))

                Text("Missing")
                  .font(.subheadline.weight(.medium))
              }
              .foregroundStyle(Color.orange)
            }
          }
          .padding(.horizontal, 14)
          .frame(height: 44)

          if index < selectedCPTType.requiredColumns.count - 1 {
            Divider()
              .padding(.horizontal, 14)
          }
        }
      }
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color(.tertiarySystemGroupedBackground).opacity(0.55))
      )
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
  }

  private var cptFileSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("CPT File")
        .font(.headline.weight(.bold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)

      if let importError {
        Text(importError)
          .font(.footnote)
          .foregroundStyle(.red)
      }

      if let file = uploadedFile {
        // State B: File Selected
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(file.name)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Color.primary)
              .lineLimit(1)

            Text("\(file.formattedSize) · \(file.rowCount) rows")
              .font(.caption)
              .foregroundStyle(Color.secondary)
          }

          Spacer()

          Button(action: {
            uploadedFile = nil
            parsedRows = []
            lastLoadedCSVText = nil
            importError = nil
          }) {
            Image(systemName: "trash")
              .font(.body.weight(.medium))
              .foregroundStyle(Color.red)
              .frame(minWidth: 44, minHeight: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Remove file")
          .accessibilityHint("Removes the selected CPT file")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(
              isDropTargetActive
                ? Color.blue
                : Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
              lineWidth: isDropTargetActive ? 2 : 1
            )
        )
        .dropDestination(for: URL.self) { urls, _ in
          guard let url = urls.first else { return false }
          handleFile(url: url)
          return true
        } isTargeted: { targeted in
          isDropTargetActive = targeted
        }
      } else {
        // State A: No File Selected with Drag & Drop
        VStack(spacing: 10) {
          Image(systemName: "doc")
            .font(.system(size: 36, weight: .light))
            .foregroundStyle(Color.secondary.opacity(0.8))

          Text("No file selected")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)


          Button(action: {
            isDocumentPickerPresented = true
          }) {
            Text("Select file")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Color.blue)
              .padding(.horizontal, 20)
              .padding(.vertical, 8)
              .background(Color.blue.opacity(0.12), in: Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Select file")
          .accessibilityHint("Opens document picker to choose a CPT data file")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(
              isDropTargetActive
                ? Color.blue
                : Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
              style: StrokeStyle(
                lineWidth: isDropTargetActive ? 2 : 1,
                dash: isDropTargetActive ? [6, 4] : []
              )
            )
        )
        .dropDestination(for: URL.self) { urls, _ in
          guard let url = urls.first else { return false }
          handleFile(url: url)
          return true
        } isTargeted: { targeted in
          isDropTargetActive = targeted
        }
      }
    }
  }

  // MARK: - Helpers

  private func handleFile(url: URL) {
    uploadedFile = nil
    parsedRows = []
    lastLoadedCSVText = nil
    importError = nil
    let ext = url.pathExtension.lowercased()
    guard ext == "csv" || ext == "xlsx" else {
      importError = "Format .\(ext) belum didukung. Ekspor data sebagai CSV atau Excel (.xlsx)."
      return
    }
    let name = url.lastPathComponent
    var byteSize: Int64 = 24 * 1024
    if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
       let fileSize = resourceValues.fileSize
    {
      byteSize = Int64(fileSize)
    }

    guard let rawData = try? Data(contentsOf: url) else {
      importError = "File tidak dapat dibaca."
      return
    }

    let csvText: String?
    if ext == "xlsx" {
      csvText = CPTXLSXCodec.extractCSVText(from: rawData)
    } else {
      csvText = String(data: rawData, encoding: .utf8) ?? String(data: rawData, encoding: .isoLatin1)
    }

    guard let csvText else {
      importError = ext == "xlsx"
        ? "File Excel (.xlsx) tidak dapat dibaca atau formatnya tidak didukung."
        : "File CSV tidak dapat dibaca sebagai teks."
      return
    }

    lastLoadedCSVText = csvText
    let parseResult = CPTCSVParser.parse(
      text: csvText,
      cptType: selectedCPTType,
      equipment: currentEquipmentParameters
    )
    if parseResult.error == nil, !parseResult.rows.isEmpty {
      parsedRows = parseResult.rows
      uploadedFile = CPTUploadedFile(
        name: name,
        byteSize: byteSize,
        rowCount: parseResult.rows.count,
        matchedColumns: parseResult.matchedRequiredColumns
      )
      return
    }
    importError = parseResult.error ?? (ext == "xlsx" ? "File Excel tidak memiliki data CPT yang valid." : "CSV tidak memiliki data CPT yang valid.")
  }

  private func revalidateCSVIfNeeded(for cptType: CPTType) {
    guard let currentFile = uploadedFile else { return }
    if currentFile.isDemo {
      uploadedFile?.matchedColumns = cptType.requiredColumns
      return
    }
    if let csvText = lastLoadedCSVText {
      let parseResult = CPTCSVParser.parse(
        text: csvText,
        cptType: cptType,
        equipment: currentEquipmentParameters
      )
      parsedRows = parseResult.rows
      importError = parseResult.error
      uploadedFile = CPTUploadedFile(
        name: currentFile.name,
        byteSize: currentFile.byteSize,
        rowCount: parseResult.rows.count,
        matchedColumns: parseResult.matchedRequiredColumns
      )
    } else {
      uploadedFile = CPTUploadedFile(
        name: currentFile.name,
        byteSize: currentFile.byteSize,
        rowCount: currentFile.rowCount,
        matchedColumns: cptType.requiredColumns
      )
    }
  }
}

#Preview("Electrical CPT") {
  @Previewable @State var type: CPTType = .electrical
  @Previewable @State var zone = "48S"
  @Previewable @State var easting = "702634"
  @Previewable @State var northing = "9309747"
  @Previewable @State var file: CPTUploadedFile? = nil

  CPTUploadDataSheetView(
    selectedCPTType: $type,
    zoneText: $zone,
    eastingText: $easting,
    northingText: $northing,
    uploadedFile: $file
  )
}

#Preview("CPTu") {
  @Previewable @State var type: CPTType = .cptu
  @Previewable @State var zone = "48S"
  @Previewable @State var easting = "702634"
  @Previewable @State var northing = "9309747"
  @Previewable @State var file: CPTUploadedFile? = nil

  CPTUploadDataSheetView(
    selectedCPTType: $type,
    zoneText: $zone,
    eastingText: $easting,
    northingText: $northing,
    uploadedFile: $file
  )
}

#Preview("CPTm Bicone") {
  @Previewable @State var type: CPTType = .cptmBicone
  @Previewable @State var zone = "48S"
  @Previewable @State var easting = "702634"
  @Previewable @State var northing = "9309747"
  @Previewable @State var file: CPTUploadedFile? = nil

  CPTUploadDataSheetView(
    selectedCPTType: $type,
    zoneText: $zone,
    eastingText: $easting,
    northingText: $northing,
    uploadedFile: $file
  )
}

#Preview("Subsequent Upload") {
  @Previewable @State var type: CPTType = .electrical
  @Previewable @State var zone = "48S"
  @Previewable @State var easting = "702634"
  @Previewable @State var northing = "9309747"
  @Previewable @State var file: CPTUploadedFile? = nil

  CPTUploadDataSheetView(
    selectedCPTType: $type,
    zoneText: $zone,
    eastingText: $easting,
    northingText: $northing,
    uploadedFile: $file,
    showCPTTypeSelection: true
  )
}
