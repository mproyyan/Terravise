import SwiftUI

struct ResultLayerSlicingCardView: View {
  @Binding var isExpanded: Bool
  @Binding var slicingXMeters: Double
  @Binding var slicingYMeters: Double
  var minXMeters: Double
  var maxXMeters: Double
  var minYMeters: Double
  var maxYMeters: Double
  var onResetView: () -> Void

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      // Header Row: "Layer & Slicing" + Collapse/Expand Chevron
      Button(action: {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
          isExpanded.toggle()
        }
      }) {
        HStack {
          Text("Layer & Slicing")
            .font(.headline.weight(.bold))
            .foregroundStyle(Color.primary)

          Spacer()

          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.secondary)
            .frame(minWidth: 28, minHeight: 28)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(minHeight: 36)
      .accessibilityLabel("Layer and Slicing")
      .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
      .accessibilityHint("Double-tap to toggle slicing controls")

      if isExpanded {
        VStack(alignment: .leading, spacing: 12) {
          Text("Slicing Control")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)
            .accessibilityAddTraits(.isHeader)

          // Slicing X Control
          VStack(alignment: .leading, spacing: 6) {
            Text("Slicing X")
              .font(.caption.weight(.semibold))
              .foregroundStyle(Color.primary)

            HStack(spacing: 10) {
              Slider(
                value: $slicingXMeters,
                in: minXMeters ... max(maxXMeters, minXMeters + 0.1)
              )
              .tint(.blue)
              .accessibilityLabel("Slicing X")
              .accessibilityValue(String(format: "%.1f meters", slicingXMeters))

              meterValuePill(value: slicingXMeters)
            }
          }

          // Slicing Y Control
          VStack(alignment: .leading, spacing: 6) {
            Text("Slicing Y")
              .font(.caption.weight(.semibold))
              .foregroundStyle(Color.primary)

            HStack(spacing: 10) {
              Slider(
                value: $slicingYMeters,
                in: minYMeters ... max(maxYMeters, minYMeters + 0.1)
              )
              .tint(.blue)
              .accessibilityLabel("Slicing Y")
              .accessibilityValue(String(format: "%.1f meters", slicingYMeters))

              meterValuePill(value: slicingYMeters)
            }
          }

          // Reset View Button
          Button(action: onResetView) {
            HStack(spacing: 6) {
              Image(systemName: "arrow.counterclockwise")
                .font(.footnote.weight(.semibold))
              Text("Reset View")
                .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.blue)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
              Capsule()
                .fill(Color(.tertiarySystemFill))
            )
          }
          .buttonStyle(.plain)
          .padding(.top, 2)
          .accessibilityLabel("Reset View")
          .accessibilityHint("Resets 3D camera orientation and cross-section slicing sliders")
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
    }
    .padding(16)
    .frame(width: 310)
    .background(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(.regularMaterial)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.10),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
    .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 6)
  }

  private func meterValuePill(value: Double) -> some View {
    Text(String(format: "%.1f m", value))
      .font(.caption.weight(.semibold))
      .monospacedDigit()
      .foregroundStyle(Color.primary)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        Capsule()
          .fill(Color(.tertiarySystemFill))
      )
      .accessibilityHidden(true)
  }
}
