import SwiftUI

struct ResultBearingCompareDataSheetView: View {
  var items: [ComparedBearingPointItem]
  var onRemoveItem: (ComparedBearingPointItem) -> Void
  var onClose: () -> Void

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    NavigationStack {
      ScrollView(.vertical, showsIndicators: false) {
        if items.isEmpty {
          VStack(spacing: 8) {
            Text("No Comparison Points")
              .font(.headline)
              .foregroundStyle(Color.secondary)
            Text("Tap the bearing layer and choose 'Add to Compare' to add points.")
              .font(.subheadline)
              .foregroundStyle(Color.secondary)
              .multilineTextAlignment(.center)
          }
          .padding(.vertical, 40)
          .padding(.horizontal, 24)
          .frame(maxWidth: .infinity)
        } else {
          VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
              comparisonRow(item: item)

              if index < items.count - 1 {
                Divider()
                  .padding(.vertical, 12)
              }
            }
          }
          .padding(16)
          .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .fill(Color(.secondarySystemGroupedBackground))
          )
          .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .stroke(
                Color.primary.opacity(contrast == .increased ? 0.25 : 0.05),
                lineWidth: 1
              )
          )
          .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
          .padding(.horizontal, 18)
          .padding(.top, 14)
          .padding(.bottom, 24)
        }
      }
      .scrollBounceBehavior(.basedOnSize)
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Compare Data")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(role: .close) {
            onClose()
          }
          .accessibilityLabel("Close")
          .accessibilityHint("Closes compare data and clears saved points")
        }
      }
    }
  }

  private func comparisonRow(item: ComparedBearingPointItem) -> some View {
    HStack(alignment: .center, spacing: 14) {
      // Blue Badge (e.g. "B-1")
      ZStack {
        Circle()
          .fill(Color.blue)
          .frame(width: 32, height: 32)

        Text(item.label)
          .font(.caption2.weight(.bold))
          .foregroundStyle(.white)
      }
      .accessibilityHidden(true)

      // Info Column
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.primary)

        Text(item.depthText)
          .font(.title3.weight(.bold))
          .foregroundStyle(Color.primary)

        HStack(spacing: 16) {
          VStack(alignment: .leading, spacing: 1) {
            Text("Northing (N)")
              .font(.caption2)
              .foregroundStyle(Color.secondary)
            Text(item.northingText)
              .font(.caption2.weight(.medium))
              .foregroundStyle(Color.secondary)
          }

          VStack(alignment: .leading, spacing: 1) {
            Text("Easting (E)")
              .font(.caption2)
              .foregroundStyle(Color.secondary)
            Text(item.eastingText)
              .font(.caption2.weight(.medium))
              .foregroundStyle(Color.secondary)
          }
        }
      }

      Spacer()

      // Red Delete Button
      Button(action: {
        onRemoveItem(item)
      }) {
        Image(systemName: "minus.circle.fill")
          .font(.title3)
          .foregroundStyle(Color.red)
          .frame(width: 32, height: 32)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Remove \(item.label)")
      .accessibilityHint("Removes \(item.title) from comparison list")
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(item.label): \(item.title), depth \(item.depthText), Northing \(item.northingText), Easting \(item.eastingText)")
  }
}

#Preview {
  ResultBearingCompareDataSheetView(
    items: [
      ComparedBearingPointItem(
        id: UUID(),
        label: "B-1",
        title: "Bearing Layer - 01",
        depthText: "4.72 m",
        depthValueM: 4.72,
        northingText: "9,312,450 m",
        eastingText: "699,250 m",
        gridX: 4,
        gridZ: 2,
        worldX: 0,
        worldZ: 0
      ),
      ComparedBearingPointItem(
        id: UUID(),
        label: "B-2",
        title: "Bearing Layer - 02",
        depthText: "4.72 m",
        depthValueM: 4.72,
        northingText: "9,312,450 m",
        eastingText: "699,250 m",
        gridX: 7,
        gridZ: 1,
        worldX: 3,
        worldZ: -1
      )
    ],
    onRemoveItem: { _ in },
    onClose: { }
  )
  .frame(width: 360)
}
