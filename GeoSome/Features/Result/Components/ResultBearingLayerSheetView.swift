import SwiftUI

struct ResultBearingLayerSheetView: View {
  var shallowestDepthText: String
  var deepestDepthText: String
  var variationDepthText: String
  var relativeUncertaintyText: String?
  var highUncertaintyAreaPercentText: String
  var highUncertaintyDescription: String?
  var hasBearingLayer: Bool = true
  var isCollapsed: Bool = false
  @Environment(\.colorSchemeContrast) private var contrast

  init(
    shallowestDepthText: String = "—",
    deepestDepthText: String = "—",
    variationDepthText: String = "—",
    relativeUncertaintyText: String? = nil,
    highUncertaintyAreaPercentText: String = "—",
    highUncertaintyDescription: String? = nil,
    hasBearingLayer: Bool = true,
    isCollapsed: Bool = false
  ) {
    self.shallowestDepthText = shallowestDepthText
    self.deepestDepthText = deepestDepthText
    self.variationDepthText = variationDepthText
    self.relativeUncertaintyText = relativeUncertaintyText
    self.highUncertaintyAreaPercentText = highUncertaintyAreaPercentText
    self.highUncertaintyDescription = highUncertaintyDescription
    self.hasBearingLayer = hasBearingLayer
    self.isCollapsed = isCollapsed
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 18) {
        // Sheet Header Title & Subtitle
        VStack(alignment: .leading, spacing: 4) {
          Text("Bearing Layer")
            .font(.title2.weight(.bold))
            .foregroundStyle(Color.primary)
            .accessibilityAddTraits(.isHeader)

          if !isCollapsed {
            Text("Predicted bearing-layer depth across the investigation area")
              .font(.footnote)
              .foregroundStyle(Color.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        if !isCollapsed {
          // 1. Depth Summary Section
          depthSummarySection

          // 2. Prediction Uncertainty Section
          predictionUncertaintySection
        }
      }
      .padding(.horizontal, 18)
      .padding(.top, 14)
      .padding(.bottom, isCollapsed ? 14 : 28)
    }
    .scrollDisabled(isCollapsed)
    .scrollBounceBehavior(.basedOnSize)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityLabel("Bearing Layer sheet")
  }

  // MARK: - 1. Depth Summary

  private var depthSummarySection: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Depth Summary")
          .font(.headline.weight(.bold))
          .foregroundStyle(Color.primary)
          .accessibilityAddTraits(.isHeader)

        Text("Overview of predicted bearing layer depths across the site.")
          .font(.footnote)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if !hasBearingLayer {
        HStack(spacing: 8) {
          Image(systemName: "info.circle.fill")
            .foregroundStyle(.orange)
          Text("No soil strata meet current criteria.")
            .font(.footnote)
            .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.orange.opacity(0.12))
        )
      }

      HStack(spacing: 10) {
        depthStatCard(title: "Shallowest", value: shallowestDepthText)
        depthStatCard(title: "Deepest", value: deepestDepthText)
        depthStatCard(title: "Variation", value: variationDepthText)
      }
    }
  }

  private func depthStatCard(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Color.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      Text(value)
        .font(.title2.weight(.bold))
        .foregroundStyle(Color.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 16)
    .background(cardBackground)
    .overlay(cardStroke)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title): \(value)")
  }

  // MARK: - 2. Prediction Uncertainty

  private var predictionUncertaintySection: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Prediction Uncertainty")
          .font(.headline.weight(.bold))
          .foregroundStyle(Color.primary)
          .accessibilityAddTraits(.isHeader)

        Text("Shows uncertainty in bearing-layer identification.")
          .font(.footnote)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      // The bound value is identification uncertainty, not a relative depth error.
      VStack(alignment: .leading, spacing: 4) {
        Text(relativeUncertaintyText ?? "—")
          .font(.title2.weight(.bold))
          .foregroundStyle(Color.primary)

        Text("Bearing-layer identification uncertainty")
          .font(.footnote)
          .foregroundStyle(Color.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(cardBackground)
      .overlay(cardStroke)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Prediction Uncertainty: \(relativeUncertaintyText ?? "—")")

      // High Uncertainty Area Card
      VStack(alignment: .leading, spacing: 4) {
        Text(highUncertaintyAreaPercentText)
          .font(.title2.weight(.bold))
          .foregroundStyle(Color.primary)

        Text("High uncertainty area of total investigation area")
          .font(.footnote)
          .foregroundStyle(Color.secondary)

        if let highUncertaintyDescription {
          Text(highUncertaintyDescription)
            .font(.footnote)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(cardBackground)
      .overlay(cardStroke)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        "High Uncertainty Area: \(highUncertaintyAreaPercentText). \(highUncertaintyDescription ?? "")"
      )
    }
  }

  // MARK: - Card Styling

  private var cardBackground: some View {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
      .fill(Color(.secondarySystemGroupedBackground))
  }

  private var cardStroke: some View {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
      .stroke(
        Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
        lineWidth: contrast == .increased ? 1.5 : 1
      )
  }
}

#Preview {
  ResultBearingLayerSheetView()
}
