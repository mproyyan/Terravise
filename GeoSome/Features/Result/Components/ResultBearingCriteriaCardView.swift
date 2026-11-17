import SwiftUI

struct ResultBearingCriteriaCardView: View {
  var cardWidth: CGFloat
  @Binding var isExpanded: Bool
  @Binding var coneResistanceQc: Double
  @Binding var soilBehaviorIndexIc: Double
  var selectedIcText: String = "N/A"
  @Binding var minLayerThickness: Double
  var onResetCriteria: () -> Void

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    cardWidth: CGFloat = 360,
    isExpanded: Binding<Bool>,
    coneResistanceQc: Binding<Double>,
    soilBehaviorIndexIc: Binding<Double>,
    selectedIcText: String = "N/A",
    minLayerThickness: Binding<Double>,
    onResetCriteria: @escaping () -> Void = {}
  ) {
    self.cardWidth = cardWidth
    self._isExpanded = isExpanded
    self._coneResistanceQc = coneResistanceQc
    self._soilBehaviorIndexIc = soilBehaviorIndexIc
    self.selectedIcText = selectedIcText
    self._minLayerThickness = minLayerThickness
    self.onResetCriteria = onResetCriteria
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      // Header Row: "Identification Criteria" + Collapse/Expand Chevron
      Button(action: {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
          isExpanded.toggle()
        }
      }) {
        HStack {
          Text("Identification Criteria")
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
      .accessibilityLabel("Identification Criteria")
      .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
      .accessibilityHint("Double-tap to toggle criteria slicing controls")

      if isExpanded {
        VStack(alignment: .leading, spacing: 14) {
          // Slicing Control Title
          Text("Slicing Control")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)
            .accessibilityAddTraits(.isHeader)

          // 1. Cone Resistance (qc)
          VStack(alignment: .leading, spacing: 6) {
            Text("Cone Resistance (qc)")
              .font(.subheadline.weight(.medium))
              .foregroundStyle(Color.secondary)

            HStack(spacing: 12) {
              sliderWithTicks(
                value: $coneResistanceQc,
                range: 5.0 ... 30.0,
                step: 0.5,
                accessibilityLabel: "Cone Resistance qc"
              )

              valuePill(text: String(format: "≥ %.1f MPa", coneResistanceQc))
            }
          }

          // 2. Soil Behavior Index (Ic)
          VStack(alignment: .leading, spacing: 6) {
            Text("Soil Behavior Index (Ic)")
              .font(.subheadline.weight(.medium))
              .foregroundStyle(Color.secondary)

            HStack(spacing: 12) {
              sliderWithTicks(
                value: $soilBehaviorIndexIc,
                range: 1.0 ... 3.0,
                step: 0.05,
                accessibilityLabel: "Soil Behavior Index Ic"
              )
              .disabled(selectedIcText == "N/A")

              valuePill(text: selectedIcText == "N/A" ? selectedIcText : "≤ \(selectedIcText)")
            }
          }

          // 3. Minimum Layer Thickness
          VStack(alignment: .leading, spacing: 6) {
            Text("Minimum Layer Thickness")
              .font(.subheadline.weight(.medium))
              .foregroundStyle(Color.secondary)

            HStack(spacing: 12) {
              sliderWithTicks(
                value: $minLayerThickness,
                range: 0.2 ... 3.0,
                step: 0.1,
                accessibilityLabel: "Minimum Layer Thickness"
              )

              valuePill(text: String(format: "≥ %.1f m", minLayerThickness))
            }
          }

          // Reset Criteria Button
          resetCriteriaButton
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, isExpanded ? 18 : 14)
    .frame(width: cardWidth)
    .background(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
  }

  // MARK: - Subviews & Helpers

  private func sliderWithTicks(
    value: Binding<Double>,
    range: ClosedRange<Double>,
    step: Double? = nil,
    accessibilityLabel: String
  ) -> some View {
    ZStack {
      HStack {
        ForEach(0..<5) { index in
          Circle()
            .fill(Color(.systemGray4))
            .frame(width: 4, height: 4)
          if index < 4 {
            Spacer()
          }
        }
      }
      .padding(.horizontal, 6)
      .offset(y: 8)
      .accessibilityHidden(true)

      if let step {
        Slider(value: value, in: range, step: step)
          .tint(.blue)
          .accessibilityLabel(accessibilityLabel)
          .accessibilityValue(String(format: "%.2f", value.wrappedValue))
      } else {
        Slider(value: value, in: range)
          .tint(.blue)
          .accessibilityLabel(accessibilityLabel)
          .accessibilityValue(String(format: "%.2f", value.wrappedValue))
      }
    }
  }

  private func valuePill(text: String) -> some View {
    Text(text)
      .font(.subheadline.weight(.medium))
      .monospacedDigit()
      .foregroundStyle(Color.primary)
      .frame(minWidth: 72)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color(.tertiarySystemFill))
      )
      .accessibilityHidden(true)
  }

  private var resetCriteriaButton: some View {
    Button(action: onResetCriteria) {
      HStack(spacing: 6) {
        Image(systemName: "arrow.counterclockwise")
          .font(.footnote.weight(.semibold))
        Text("Reset Criteria")
          .font(.subheadline.weight(.semibold))
      }
      .foregroundStyle(Color.blue)
      .frame(maxWidth: .infinity)
      .frame(height: 42)
      .background(
        Capsule()
          .fill(Color(.tertiarySystemFill))
      )
    }
    .buttonStyle(.plain)
    .padding(.top, 4)
    .accessibilityLabel("Reset Criteria")
    .accessibilityHint("Resets identification criteria values to their defaults")
  }
}

#Preview {
  ResultBearingCriteriaCardView(
    isExpanded: .constant(true),
    coneResistanceQc: .constant(15.0),
    soilBehaviorIndexIc: .constant(1.80),
    minLayerThickness: .constant(1.0)
  )
  .padding()
  .background(Color(.systemGroupedBackground))
}
