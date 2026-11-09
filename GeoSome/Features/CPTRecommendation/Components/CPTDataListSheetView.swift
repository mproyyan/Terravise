import SwiftUI

struct CPTDataListSheetView: View {
  var points: [CPTPointEntry]
  var onCloseTap: (() -> Void)?
  var onDeletePoint: ((CPTPointEntry.ID) -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast

  init(
    points: [CPTPointEntry] = [],
    onCloseTap: (() -> Void)? = nil,
    onDeletePoint: ((CPTPointEntry.ID) -> Void)? = nil
  ) {
    self.points = points
    self.onCloseTap = onCloseTap
    self.onDeletePoint = onDeletePoint
  }

  var body: some View {
    NavigationStack {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 12) {
          ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
            NavigationLink {
              CPTPointDetailSheetView(
                pointTitle: "CPT Point \(index + 1)",
                point: point,
                onDeletePoint: {
                  onDeletePoint?(point.id)
                }
              )
            } label: {
              pointCard(point: point, index: index)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 24)
      }
      .scrollBounceBehavior(.basedOnSize)
      .navigationTitle("Data CPT")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(role: .close) {
            onCloseTap?()
          }
          .accessibilityLabel("Close")
          .accessibilityHint("Closes CPT data list")
        }
      }
    }
  }

  private func pointCard(point: CPTPointEntry, index: Int) -> some View {
    HStack(spacing: 12) {
      // Orange Numbered Circle
      ZStack {
        Circle()
          .fill(Color.orange)
          .frame(width: 26, height: 26)

        Text("\(index + 1)")
          .font(.caption.weight(.bold))
          .foregroundStyle(Color.white)
      }
      .accessibilityHidden(true)

      // Point Info
      VStack(alignment: .leading, spacing: 2) {
        Text("CPT Point \(index + 1)")
          .font(.caption.weight(.medium))
          .foregroundStyle(Color.secondary)

        Text(point.formattedCoordinate)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Color.primary)
      }

      Spacer()

      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.secondary)
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
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("CPT Point \(index + 1), coordinates \(point.formattedCoordinate)")
    .accessibilityHint("Double tap to view detailed CPT data")
  }
}

#Preview {
  CPTDataListSheetView(
    points: [
      CPTPointEntry(
        coordinate: .init(latitude: -6.215432, longitude: 106.845321),
        file: .init(name: "CPT1.csv")
      ),
      CPTPointEntry(
        coordinate: .init(latitude: -6.217553, longitude: 106.849876),
        file: .init(name: "CPT2.csv")
      )
    ]
  )
}
