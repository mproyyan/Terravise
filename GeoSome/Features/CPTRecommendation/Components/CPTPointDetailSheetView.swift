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
      VStack(alignment: .leading, spacing: 18) {
        detailCoordinateSection
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
    .navigationBarBackButtonHidden(true)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(role: .close) {
          if let onCloseTap {
            onCloseTap()
          } else {
            dismiss()
          }
        }
        .accessibilityLabel("Close")
        .accessibilityHint("Returns to CPT data list")
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

  // MARK: - Subviews

  private var detailCoordinateSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Detail Coordinate")
        .font(.headline.weight(.bold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)

      HStack(spacing: 12) {
        // Latitude Box
        VStack(alignment: .leading, spacing: 4) {
          Text("Latitude")
            .font(.caption)
            .foregroundStyle(Color.secondary)

          Text(point.formattedLatitude)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.tertiarySystemGroupedBackground).opacity(0.65))
        )

        // Longitude Box
        VStack(alignment: .leading, spacing: 4) {
          Text("Longitude")
            .font(.caption)
            .foregroundStyle(Color.secondary)

          Text(point.formattedLongitude)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.tertiarySystemGroupedBackground).opacity(0.65))
        )
      }
      .padding(14)
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

  private var cptDataSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("CPT Data")
        .font(.headline.weight(.bold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)

      VStack(spacing: 0) {
        // Table Header
        HStack(spacing: 4) {
          Text("Depth (m)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

          Text("Cone Resistance (MPa)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

          Text("Local Friction (kPa)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

          Text("Pore Pressure (kPa)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)

        // Table Rows Card
        VStack(spacing: 0) {
          ForEach(Array(point.rows.enumerated()), id: \.element.id) { index, row in
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

              Text(String(format: "%.2f", row.porePressure ?? 0.0))
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
