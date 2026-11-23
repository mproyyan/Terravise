import SwiftUI

struct ResultBearingCriteriaCardView: View {
  var cardWidth: CGFloat
  @Binding var isExpanded: Bool
  @Binding var isMapOverlayVisible: Bool
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
    isMapOverlayVisible: Binding<Bool> = .constant(false),
    coneResistanceQc: Binding<Double>,
    soilBehaviorIndexIc: Binding<Double>,
    selectedIcText: String = "N/A",
    minLayerThickness: Binding<Double>,
    onResetCriteria: @escaping () -> Void = {}
  ) {
    self.cardWidth = cardWidth
    self._isExpanded = isExpanded
    self._isMapOverlayVisible = isMapOverlayVisible
    self._coneResistanceQc = coneResistanceQc
    self._soilBehaviorIndexIc = soilBehaviorIndexIc
    self.selectedIcText = selectedIcText
    self._minLayerThickness = minLayerThickness
    self.onResetCriteria = onResetCriteria
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      // Header Row: "Controls" + Collapse/Expand Chevron
      Button(action: {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
          isExpanded.toggle()
        }
      }) {
        HStack {
          Text("Controls")
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
          // Layer Section: Map Overlay Toggle
          VStack(alignment: .leading, spacing: 8) {
            Text("Layer")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(Color.primary)
              .accessibilityAddTraits(.isHeader)

            HStack {
              Text("Map Overlay")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.secondary)

              Spacer()

              Toggle("", isOn: $isMapOverlayVisible)
                .labelsHidden()
                .tint(.green)
                .accessibilityLabel("Map Overlay")
            }
          }

          Divider()

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

              TypableValuePill(
                prefix: "≥",
                unit: "MPa",
                value: $coneResistanceQc,
                range: 5.0 ... 30.0,
                format: "%.1f"
              )
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

              TypableValuePill(
                prefix: "≤",
                unit: "",
                value: $soilBehaviorIndexIc,
                range: 1.0 ... 3.0,
                format: "%.2f",
                isDisabled: selectedIcText == "N/A",
                disabledText: selectedIcText
              )
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

              TypableValuePill(
                prefix: "≥",
                unit: "m",
                value: $minLayerThickness,
                range: 0.2 ... 3.0,
                format: "%.1f"
              )
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

  private var resetCriteriaButton: some View {
    Button(action: onResetCriteria) {
      HStack(spacing: 6) {
        Image(systemName: "arrow.counterclockwise")
          .font(.footnote.weight(.semibold))
        Text("Reset Criteria")
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

// MARK: - Typable Value Pill

private struct TypableValuePill: View {
  var prefix: String = ""
  var unit: String = ""
  @Binding var value: Double
  var range: ClosedRange<Double>
  var format: String
  var isDisabled: Bool = false
  var disabledText: String? = nil

  @State private var text: String
  @FocusState private var isFocused: Bool
  @Environment(\.colorSchemeContrast) private var contrast

  init(
    prefix: String = "",
    unit: String = "",
    value: Binding<Double>,
    range: ClosedRange<Double>,
    format: String,
    isDisabled: Bool = false,
    disabledText: String? = nil
  ) {
    self.prefix = prefix
    self.unit = unit
    self._value = value
    self.range = range
    self.format = format
    self.isDisabled = isDisabled
    self.disabledText = disabledText
    self._text = State(initialValue: String(format: format, value.wrappedValue))
  }

  var body: some View {
    HStack(spacing: 3) {
      if isDisabled, let disabledText {
        Text(disabledText)
          .font(.subheadline.weight(.medium))
          .monospacedDigit()
          .foregroundStyle(Color.secondary)
      } else {
        if !prefix.isEmpty {
          Text(prefix)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.secondary)
        }

        TextField("", text: $text)
          .font(.subheadline.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(Color.primary)
          .multilineTextAlignment(.trailing)
          #if canImport(UIKit)
          .keyboardType(.decimalPad)
          #endif
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .focused($isFocused)
          .frame(minWidth: format.contains(".2") ? 36 : 28)
          .onChange(of: text) { _, newText in
            guard isFocused else { return }
            let sanitized = newText.replacingOccurrences(of: ",", with: ".")
            if let parsed = Double(sanitized) {
              let clamped = min(max(parsed, range.lowerBound), range.upperBound)
              value = clamped
            }
          }
          .onSubmit {
            commitText()
            isFocused = false
          }

        if !unit.isEmpty {
          Text(unit)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.secondary)
        }
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(minWidth: 86)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(.tertiarySystemFill))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(
          isFocused ? Color.blue : Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
          lineWidth: isFocused ? 1.5 : (contrast == .increased ? 1.5 : 1)
        )
    )
    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .onTapGesture {
      if !isDisabled {
        isFocused = true
      }
    }
    .animation(.easeInOut(duration: 0.15), value: isFocused)
    .onChange(of: value) { _, newValue in
      if !isFocused {
        text = String(format: format, newValue)
      }
    }
    .onChange(of: isFocused) { _, focused in
      if !focused {
        commitText()
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") {
          commitText()
          isFocused = false
        }
        .font(.subheadline.weight(.semibold))
      }
    }
    .disabled(isDisabled)
    .accessibilityElement(children: .combine)
  }

  private func commitText() {
    let sanitized = text.replacingOccurrences(of: ",", with: ".")
    if let parsed = Double(sanitized) {
      let clamped = min(max(parsed, range.lowerBound), range.upperBound)
      value = clamped
      text = String(format: format, clamped)
    } else {
      text = String(format: format, value)
    }
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
