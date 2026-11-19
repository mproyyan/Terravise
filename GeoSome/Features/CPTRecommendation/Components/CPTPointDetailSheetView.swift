import CoreLocation
import SwiftUI

struct CPTPointDetailSheetView: View {
  var pointTitle: String
  var point: CPTPointEntry
  var onCloseTap: (() -> Void)?
  var onDeletePoint: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorSchemeContrast) private var contrast
  @State private var isDeleteConfirmationPresented: Bool = false

  init(
    pointTitle: String = "CPT Point 1",
    point: CPTPointEntry,
    onCloseTap: (() -> Void)? = nil,
    onDeletePoint: (() -> Void)? = nil
  ) {
    self.pointTitle = pointTitle
    self.point = point
    self.onCloseTap = onCloseTap
    self.onDeletePoint = onDeletePoint
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 20) {
        detailCoordinateSection
        cptTypeSection
        cptDataSection
        deletePointButton
      }
      .padding(.horizontal, 20)
      .padding(.top, 14)
      .padding(.bottom, 24)
    }
    .scrollBounceBehavior(.basedOnSize)
    .navigationTitle(pointTitle)
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(onCloseTap != nil)
    .toolbar {
      if let onCloseTap {
        ToolbarItem(placement: .cancellationAction) {
          Button(role: .close) {
            onCloseTap()
          }
          .accessibilityLabel("Close")
          .accessibilityHint("Returns to CPT data list")
        }
      }
    }
    .alert("Delete Point?", isPresented: $isDeleteConfirmationPresented) {
      Button("Delete Point", role: .destructive) {
        onDeletePoint?()
        dismiss()
      }
      Button("Cancel", role: .cancel) {
        isDeleteConfirmationPresented = false
      }
    } message: {
      Text("\(pointTitle) will be permanently deleted.\n\nThis action cannot be undone.")
    }
  }

  // MARK: - Section 1: Detail Coordinate (UTM)

  private var detailCoordinateSection: some View {
    CPTCardContainer(title: "Detail Coordinate") {
      CPTDetailRow(title: "Zone", value: point.formattedZone)
      Divider().padding(.horizontal, 16)
      CPTDetailRow(title: "Easting (m)", value: "\(Int(point.utmCoordinate.easting.rounded())) m E")
      Divider().padding(.horizontal, 16)
      CPTDetailRow(title: "Northing (m)", value: "\(Int(point.utmCoordinate.northing.rounded())) m N")
    }
  }

  // MARK: - Section 2: CPT Data Type (Adjusted for each type)

  private var cptTypeSection: some View {
    CPTCardContainer(title: "Type CPT Data") {
      HStack {
        Text(point.type.displayName)
          .font(.body)
          .foregroundStyle(Color.primary)

        Spacer()
      }
      .padding(.horizontal, 16)
      .frame(height: 48)

      switch point.type {
      case .cptu:
        Divider().padding(.horizontal, 16)
        CPTDetailRow(
          title: "Net Area Ratio (a)",
          value: String(format: "%.2f", point.resolvedEquipmentParameters.netAreaRatio)
        )

      case .cptmBicone:
        Divider().padding(.horizontal, 16)
        CPTDetailRow(
          title: "Piston Diameter (Dpi)",
          value: "\(String(format: "%.2f", point.resolvedEquipmentParameters.pistonDiameterCm)) cm"
        )
        Divider().padding(.horizontal, 16)
        CPTDetailRow(
          title: "Cone Diameter (Dc)",
          value: "\(String(format: "%.2f", point.resolvedEquipmentParameters.coneDiameterCm)) cm"
        )
        Divider().padding(.horizontal, 16)
        CPTDetailRow(
          title: "Friction Sleeve Diameter (Ds)",
          value: "\(String(format: "%.2f", point.resolvedEquipmentParameters.frictionSleeveDiameterCm)) cm"
        )
        Divider().padding(.horizontal, 16)
        CPTDetailRow(
          title: "Friction Sleeve Length (Ls)",
          value: "\(String(format: "%.1f", point.resolvedEquipmentParameters.frictionSleeveLengthCm)) cm"
        )

      case .electrical:
        EmptyView()
      }
    }
  }

  // MARK: - Section 3: CPT Data Table

  private var cptDataSection: some View {
    CPTDataTableView(point: point)
  }

  // MARK: - Delete Point Button

  private var deletePointButton: some View {
    Button(action: {
      isDeleteConfirmationPresented = true
    }) {
      HStack(spacing: 8) {
        Image(systemName: "trash")
          .font(.body.weight(.medium))

        Text("Delete Point")
          .font(.body.weight(.semibold))
      }
      .foregroundStyle(Color.red)
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Delete Point")
    .accessibilityHint("Permanently deletes this CPT point")
  }
}

// MARK: - Reusable Components

struct CPTDetailRow: View {
  var title: String
  var value: String
  var titleColor: Color = .primary
  var valueColor: Color = .secondary

  var body: some View {
    HStack(spacing: 12) {
      Text(title)
        .font(.body)
        .foregroundStyle(titleColor)
        .lineLimit(1)

      Spacer(minLength: 8)

      Text(value)
        .font(.body.weight(.medium))
        .foregroundStyle(valueColor)
        .lineLimit(1)
    }
    .padding(.horizontal, 16)
    .frame(height: 48)
  }
}

struct CPTCardContainer<Content: View>: View {
  var title: String? = nil
  @ViewBuilder var content: () -> Content
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let title {
        Text(title)
          .font(.headline.weight(.bold))
          .foregroundStyle(Color.primary)
          .accessibilityAddTraits(.isHeader)
      }

      VStack(spacing: 0) {
        content()
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

struct CPTDataTableView: View {
  var point: CPTPointEntry
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("CPT Data")
          .font(.headline.weight(.bold))
          .foregroundStyle(Color.primary)
          .accessibilityAddTraits(.isHeader)

        Spacer()

        Text("\(point.rows.count) readings")
          .font(.subheadline)
          .foregroundStyle(Color.secondary)
      }

      VStack(spacing: 0) {
        // Table Header
        headerView
          .padding(.horizontal, 14)
          .padding(.vertical, 10)

        // Table Rows Card
        if point.rows.isEmpty {
          Text("No data points recorded.")
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
          VStack(spacing: 0) {
            ForEach(Array(point.rows.enumerated()), id: \.element.id) { index, row in
              rowView(for: row)
                .padding(.horizontal, 14)
                .frame(height: 34)

              if index < point.rows.count - 1 {
                Divider()
                  .padding(.horizontal, 10)
              }
            }
          }
          .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(Color(.tertiarySystemGroupedBackground).opacity(0.45))
          )
          .padding(.horizontal, 8)
          .padding(.bottom, 8)
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

  @ViewBuilder
  private var headerView: some View {
    HStack(spacing: 4) {
      Text("Depth (m)")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Text("qc (MPa)")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Text("fs (kPa)")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      if point.type == .cptu {
        Text("u2 (kPa)")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(Color.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  @ViewBuilder
  private func rowView(for row: CPTRowData) -> some View {
    HStack(spacing: 4) {
      Text(String(format: "%.2f", row.depth))
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Text(String(format: "%.2f", row.coneResistance))
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Text(String(format: "%.2f", row.localFriction))
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, alignment: .leading)

      if point.type == .cptu {
        Text(String(format: "%.2f", row.porePressure ?? 0.0))
          .font(.caption.weight(.medium))
          .foregroundStyle(Color.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

#Preview {
  NavigationStack {
    CPTPointDetailSheetView(
      pointTitle: "CPT Point 1",
      point: CPTPointEntry(
        coordinate: CLLocationCoordinate2D(latitude: -6.175535, longitude: 106.827308),
        file: CPTUploadedFile(name: "CPT1.csv")
      )
    )
  }
}
