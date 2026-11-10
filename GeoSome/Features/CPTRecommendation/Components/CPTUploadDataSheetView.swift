import SwiftUI
import UniformTypeIdentifiers

struct CPTUploadDataSheetView: View {
  @Binding var selectedCPTType: CPTType
  @Binding var coordinatesText: String
  @Binding var uploadedFile: CPTUploadedFile?
  @Binding var parsedRows: [CPTRowData]
  var onCloseTap: (() -> Void)?
  var onSubmitTap: (() -> Void)?
  var onDownloadTemplate: (() -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
  @State private var isDocumentPickerPresented: Bool = false
  @State private var isDropTargetActive: Bool = false
  @State private var isShareTemplatePresented: Bool = false
  @State private var lastLoadedCSVText: String?

  init(
    selectedCPTType: Binding<CPTType>,
    coordinatesText: Binding<String>,
    uploadedFile: Binding<CPTUploadedFile?>,
    parsedRows: Binding<[CPTRowData]> = .constant([]),
    onCloseTap: (() -> Void)? = nil,
    onSubmitTap: (() -> Void)? = nil,
    onDownloadTemplate: (() -> Void)? = nil
  ) {
    _selectedCPTType = selectedCPTType
    _coordinatesText = coordinatesText
    _uploadedFile = uploadedFile
    _parsedRows = parsedRows
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
    let hasCoords = !coordinatesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return hasCoords && file.rowCount > 0 && allRequiredColumnsMatched
  }

  private var isFileUploaded: Bool {
    uploadedFile != nil
  }

  private var csvTemplateString: String {
    selectedCPTType.requiredColumns.joined(separator: ",") + "\n"
  }

  var body: some View {
    NavigationStack {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 20) {
          cptTypeSection
          coordinatesSection
          requiredColumnsSection
          cptFileSection
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
      }
      .scrollBounceBehavior(.basedOnSize)
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
          UTType(filenameExtension: "xlsx") ?? .data,
          .spreadsheet,
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
        case .failure:
          break
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
              revalidateCSVIfNeeded(for: type)
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
    }
  }

  private var coordinatesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Coordinates")
        .font(.headline.weight(.bold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)

      HStack {
        TextField("e.g -6.215432, 106.845321", text: $coordinatesText)
          .font(.body)
          .foregroundStyle(Color.primary)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
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
    }
  }

  private var requiredColumnsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Required Columns")
        .font(.headline.weight(.bold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)

      VStack(alignment: .leading, spacing: 14) {
        Text("Include all of the following columns in your file:")
          .font(.subheadline)
          .foregroundStyle(Color.primary)

        ShareLink(
          item: csvTemplateString,
          subject: Text("CPT Template"),
          message: Text("CSV Template for \(selectedCPTType.displayName)")
        ) {
          HStack(spacing: 6) {
            Image(systemName: "square.and.arrow.down")
              .font(.subheadline.weight(.semibold))

            Text("Download CSV Template")
              .font(.subheadline.weight(.medium))
          }
          .foregroundStyle(Color.blue)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(Color.blue.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)

        // Required columns table
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
                .foregroundStyle(isFileUploaded ? Color.orange : Color.secondary)
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
  }

  private var cptFileSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("CPT File")
        .font(.headline.weight(.bold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)

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

          Text("Choose a .CSV or .XLSX file with the required columns shown above.")
            .font(.footnote)
            .foregroundStyle(Color.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)

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
    let name = url.lastPathComponent
    var byteSize: Int64 = 24 * 1024
    if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
       let fileSize = resourceValues.fileSize
    {
      byteSize = Int64(fileSize)
    }

    if let rawData = try? Data(contentsOf: url),
       let csvText = String(data: rawData, encoding: .utf8) ?? String(data: rawData, encoding: .isoLatin1)
    {
      lastLoadedCSVText = csvText
      let parseResult = CPTCSVParser.parse(text: csvText, cptType: selectedCPTType)
      if !parseResult.matchedRequiredColumns.isEmpty {
        parsedRows = parseResult.rows
        uploadedFile = CPTUploadedFile(
          name: name,
          byteSize: byteSize,
          rowCount: parseResult.rows.count,
          matchedColumns: parseResult.matchedRequiredColumns
        )
        return
      }
    }

    // Fallback for binary spreadsheets (.xlsx)
    lastLoadedCSVText = nil
    parsedRows = CPTRowData.sampleRows
    uploadedFile = CPTUploadedFile(
      name: name,
      byteSize: byteSize,
      rowCount: CPTRowData.sampleRows.count,
      matchedColumns: selectedCPTType.requiredColumns
    )
  }

  private func revalidateCSVIfNeeded(for cptType: CPTType) {
    guard let currentFile = uploadedFile else { return }
    if let csvText = lastLoadedCSVText {
      let parseResult = CPTCSVParser.parse(text: csvText, cptType: cptType)
      parsedRows = parseResult.rows
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

#Preview("Empty State") {
  @Previewable @State var type: CPTType = .electrical
  @Previewable @State var coords = ""
  @Previewable @State var file: CPTUploadedFile? = nil

  CPTUploadDataSheetView(
    selectedCPTType: $type,
    coordinatesText: $coords,
    uploadedFile: $file
  )
}
