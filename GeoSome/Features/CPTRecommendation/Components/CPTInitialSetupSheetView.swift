import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CPTInitialSetupSheetView: View {
  @Binding var selectedCPTType: CPTType
  var points: [CPTPointEntry]
  var equipmentParameters: Binding<CPTEquipmentParameters>?
  var onCloseTap: (() -> Void)?
  var onConfirmTap: (() -> Void)?
  var onAddCPTTap: (() -> Void)?
  var onDeletePoint: ((CPTPointEntry.ID) -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

  // Equipment Parameter Inputs (CPTu & CPTm)
  @State private var netAreaRatioText: String = "0,8"
  @State private var pistonDiameterText: String = "3,57"
  @State private var coneDiameterText: String = "3,57"
  @State private var frictionSleeveDiameterText: String = "3,57"
  @State private var frictionSleeveLengthText: String = "13,3"

  init(
    selectedCPTType: Binding<CPTType>,
    points: [CPTPointEntry] = [],
    equipmentParameters: Binding<CPTEquipmentParameters>? = nil,
    onCloseTap: (() -> Void)? = nil,
    onConfirmTap: (() -> Void)? = nil,
    onAddCPTTap: (() -> Void)? = nil,
    onDeletePoint: ((CPTPointEntry.ID) -> Void)? = nil
  ) {
    _selectedCPTType = selectedCPTType
    self.points = points
    self.equipmentParameters = equipmentParameters
    self.onCloseTap = onCloseTap
    self.onConfirmTap = onConfirmTap
    self.onAddCPTTap = onAddCPTTap
    self.onDeletePoint = onDeletePoint
  }

  private var isConfirmEnabled: Bool {
    !points.isEmpty
  }

  private var templateFileURL: URL {
    let fileName = "cpt_template_\(selectedCPTType.nameIdentifier).xlsx"
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    let xlsxData = CPTXLSXCodec.generateTemplate(for: selectedCPTType)
    try? xlsxData.write(to: tempURL)
    return tempURL
  }

  private var currentEquipmentParameters: CPTEquipmentParameters {
    CPTEquipmentParameters(
      netAreaRatio: CPTCSVParser.parseDouble(netAreaRatioText) ?? 0.80,
      pistonDiameterCm: CPTCSVParser.parseDouble(pistonDiameterText) ?? 3.57,
      coneDiameterCm: CPTCSVParser.parseDouble(coneDiameterText) ?? 3.57,
      frictionSleeveDiameterCm: CPTCSVParser.parseDouble(frictionSleeveDiameterText) ?? 3.57,
      frictionSleeveLengthCm: CPTCSVParser.parseDouble(frictionSleeveLengthText) ?? 13.3
    )
  }

  private func syncEquipmentParameters() {
    equipmentParameters?.wrappedValue = currentEquipmentParameters
  }

  var body: some View {
    NavigationStack {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 20) {
          cptTypeSection
          requiredColumnsSection
          cptListSection
          addCPTButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 28)
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .navigationTitle("Upload Data CPT")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(role: .close) {
            onCloseTap?()
          }
          .accessibilityLabel("Cancel")
          .accessibilityHint("Closes CPT setup")
        }

        ToolbarItem(placement: .confirmationAction) {
          Button(role: .confirm) {
            if isConfirmEnabled {
              syncEquipmentParameters()
              onConfirmTap?()
            }
          }
          .keyboardShortcut(nil)
          .disabled(!isConfirmEnabled)
          .accessibilityLabel("Proceed with recommendations")
          .accessibilityHint(
            isConfirmEnabled
              ? "Calculates initial subsurface profile and provides recommendations"
              : "Add at least one CPT point to proceed"
          )
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

  private var displayedPoints: [(offset: Int, element: CPTPointEntry)] {
    Array(points.prefix(3).enumerated())
  }

  private var cptListSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      if !points.isEmpty {
        NavigationLink {
          CPTDataListSheetView(
            points: points,
            isPushed: true,
            onDeletePoint: onDeletePoint
          )
        } label: {
          HStack {
            Text("CPT List")
              .font(.headline.weight(.bold))
              .foregroundStyle(Color.primary)

            Text("(\(points.count) \(points.count == 1 ? "point" : "points"))")
              .font(.caption.weight(.medium))
              .foregroundStyle(Color.secondary)

            Spacer()

            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundStyle(Color.secondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View full CPT List, \(points.count) points")
      } else {
        HStack {
          Text("CPT List")
            .font(.headline.weight(.bold))
            .foregroundStyle(Color.primary)
            .accessibilityAddTraits(.isHeader)

          Spacer()
        }
      }

      if points.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 10) {
            Image(systemName: "tray")
              .font(.title3)
              .foregroundStyle(Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
              Text("No CPT data added yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)

              Text("Add your existing CPT soundings to establish initial coverage.")
                .font(.caption)
                .foregroundStyle(Color.secondary)
            }
          }
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
      } else {
        VStack(spacing: 0) {
          ForEach(displayedPoints, id: \.element.id) { index, point in
            NavigationLink {
              CPTPointDetailSheetView(
                pointTitle: "CPT Point \(index + 1)",
                point: point,
                onDeletePoint: {
                  onDeletePoint?(point.id)
                }
              )
            } label: {
              cptPointRow(index: index, point: point)
            }
            .buttonStyle(.plain)

            if index < displayedPoints.count - 1 {
              Divider().padding(.horizontal, 16)
            }
          }
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
    }
  }

  private func cptPointRow(index: Int, point: CPTPointEntry) -> some View {
    HStack(spacing: 12) {
      // Number badge
      ZStack {
        Circle()
          .fill(Color.orange)
          .frame(width: 28, height: 28)

        Text("\(index + 1)")
          .font(.caption.weight(.bold))
          .foregroundStyle(Color.white)
      }
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text("CPT Point \(index + 1)")
          .font(.caption.weight(.medium))
          .foregroundStyle(Color.secondary)

        Text(point.formattedCoordinate)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Color.primary)

        Text("\(point.file.name) • \(point.rows.count) rows")
          .font(.caption2)
          .foregroundStyle(Color.secondary)
      }

      Spacer()

      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.secondary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .contentShape(Rectangle())
  }

  private var addCPTButton: some View {
    Button(action: {
      syncEquipmentParameters()
      onAddCPTTap?()
    }) {
      HStack(spacing: 8) {
        Image(systemName: "plus.circle.fill")
          .font(.body.weight(.semibold))

        Text("Add CPT Data")
          .font(.body.weight(.semibold))
      }
      .foregroundStyle(Color.blue)
      .frame(maxWidth: .infinity)
      .frame(height: 52)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color.blue.opacity(0.12))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Color.blue.opacity(0.25), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Add CPT Data")
    .accessibilityHint("Opens sheet to enter coordinates and upload CPT file")
  }
}
