import SwiftUI

struct ResultLayerSlicingCardView: View {
  var cardWidth: CGFloat
  @Binding var isExpanded: Bool
  @Binding var isHardSoilVisible: Bool
  var concerns: [GeotechnicalConcernItem]
  var isGeotechnicalConcernsEmpty: Bool
  var selectedConcernID: String?
  var onSelectConcern: ((GeotechnicalConcernItem) -> Void)?
  @Binding var slicingXMeters: Double
  @Binding var slicingYMeters: Double
  var minXMeters: Double
  var maxXMeters: Double
  var minYMeters: Double
  var maxYMeters: Double
  var onResetView: () -> Void

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    cardWidth: CGFloat = 360,
    isExpanded: Binding<Bool>,
    isHardSoilVisible: Binding<Bool> = .constant(true),
    concerns: [GeotechnicalConcernItem] = ResultAnalysisViewModel.defaultConcerns,
    isGeotechnicalConcernsEmpty: Bool = false,
    selectedConcernID: String? = ResultAnalysisViewModel.defaultConcerns.first?.id,
    onSelectConcern: ((GeotechnicalConcernItem) -> Void)? = nil,
    slicingXMeters: Binding<Double>,
    slicingYMeters: Binding<Double>,
    minXMeters: Double = 2.0,
    maxXMeters: Double = 25.0,
    minYMeters: Double = 2.0,
    maxYMeters: Double = 25.0,
    onResetView: @escaping () -> Void = {}
  ) {
    self.cardWidth = cardWidth
    self._isExpanded = isExpanded
    self._isHardSoilVisible = isHardSoilVisible
    self.concerns = concerns
    self.isGeotechnicalConcernsEmpty = isGeotechnicalConcernsEmpty
    self.selectedConcernID = selectedConcernID
    self.onSelectConcern = onSelectConcern
    self._slicingXMeters = slicingXMeters
    self._slicingYMeters = slicingYMeters
    self.minXMeters = minXMeters
    self.maxXMeters = maxXMeters
    self.minYMeters = minYMeters
    self.maxYMeters = maxYMeters
    self.onResetView = onResetView
  }

  private var shouldShowConcerns: Bool {
    !isGeotechnicalConcernsEmpty && !concerns.isEmpty
  }

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
        VStack(alignment: .leading, spacing: 14) {
          // 1. Layer Section
          layerSection

          Divider()

          // 2. Potential Geotechnical Concerns Section (omitted if empty)
          if shouldShowConcerns {
            concernsSection

            Divider()
          }

          // 3. Slicing Control Section
          slicingControlSection

          // 4. Reset View Button
          resetViewButton
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
    .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 4)
  }

  // MARK: - Layer Section

  private var layerSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Layer")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)

      HStack {
        Text("Hard Soil")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Color.secondary)

        Spacer()

        Toggle("", isOn: $isHardSoilVisible)
          .labelsHidden()
          .tint(.green)
          .accessibilityLabel("Hard Soil Layer")
      }
    }
  }

  // MARK: - Potential Geotechnical Concerns Section

  private var concernsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Potential Geotechnical Concerns")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)

      VStack(spacing: 8) {
        ForEach(concerns) { concern in
          concernButton(for: concern)
        }
      }
    }
  }

  private func concernButton(for concern: GeotechnicalConcernItem) -> some View {
    let isSelected = selectedConcernID == concern.id

    return Button(action: {
      onSelectConcern?(concern)
    }) {
      HStack(alignment: .center, spacing: 12) {
        Text(concern.title)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(isSelected ? Color.blue : Color.secondary)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: 8)

        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 20))
            .foregroundStyle(Color.white, Color.blue)
            .symbolRenderingMode(.palette)
            .accessibilityHidden(true)
        } else {
          Image(systemName: "circle")
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(Color(.systemGray4))
            .accessibilityHidden(true)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(isSelected ? Color.blue.opacity(0.06) : Color(.secondarySystemGroupedBackground))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(
            isSelected ? Color.blue : Color.primary.opacity(contrast == .increased ? 0.35 : 0.12),
            lineWidth: isSelected ? 1.5 : 1
          )
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(concern.title)
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
    .accessibilityHint("Double-tap to toggle highlight for this concern")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  // MARK: - Slicing Control Section

  private var slicingControlSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Slicing Control")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)

      // Slicing X Control
      VStack(alignment: .leading, spacing: 6) {
        Text("Slicing X")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Color.secondary)

        HStack(spacing: 10) {
          sliderWithTicks(
            value: $slicingXMeters,
            range: minXMeters ... max(maxXMeters, minXMeters + 0.1),
            accessibilityLabel: "Slicing X"
          )

          meterValuePill(value: slicingXMeters)
        }
      }

      // Slicing Y Control
      VStack(alignment: .leading, spacing: 6) {
        Text("Slicing Y")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Color.secondary)

        HStack(spacing: 10) {
          sliderWithTicks(
            value: $slicingYMeters,
            range: minYMeters ... max(maxYMeters, minYMeters + 0.1),
            accessibilityLabel: "Slicing Y"
          )

          meterValuePill(value: slicingYMeters)
        }
      }
    }
  }

  private func sliderWithTicks(
    value: Binding<Double>,
    range: ClosedRange<Double>,
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

      Slider(value: value, in: range)
        .tint(.blue)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(String(format: "%.1f meters", value.wrappedValue))
    }
  }

  private var resetViewButton: some View {
    Button(action: onResetView) {
      HStack(spacing: 6) {
        Image(systemName: "arrow.counterclockwise")
          .font(.footnote.weight(.semibold))
        Text("Reset View")
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
    .accessibilityLabel("Reset View")
    .accessibilityHint("Resets 3D camera orientation and cross-section slicing sliders")
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

#Preview("Expanded with Concerns") {
  ResultLayerSlicingCardView(
    isExpanded: .constant(true),
    isHardSoilVisible: .constant(true),
    concerns: ResultAnalysisViewModel.defaultConcerns,
    selectedConcernID: ResultAnalysisViewModel.defaultConcerns.first?.id,
    slicingXMeters: .constant(12.7),
    slicingYMeters: .constant(12.7)
  )
  .padding()
  .background(Color(.systemGroupedBackground))
}

#Preview("No Concerns (Section Gone)") {
  ResultLayerSlicingCardView(
    isExpanded: .constant(true),
    isHardSoilVisible: .constant(true),
    concerns: [],
    slicingXMeters: .constant(12.7),
    slicingYMeters: .constant(12.7)
  )
  .padding()
  .background(Color(.systemGroupedBackground))
}
