import SwiftUI

struct ResultBearingLayerSheetView: View {
  var shallowestDepthText: String
  var deepestDepthText: String
  var variationDepthText: String
  var coneResistanceText: String
  var soilBehaviorIndexText: String
  var minLayerThicknessText: String
  var relativeUncertaintyText: String
  var highUncertaintyAreaPercentText: String
  var highUncertaintyDescription: String

  @Environment(\.colorSchemeContrast) private var contrast

  init(
    shallowestDepthText: String = "2.7 m",
    deepestDepthText: String = "4.9 m",
    variationDepthText: String = "2.2 m",
    coneResistanceText: String = "≥ 15.0 MPa",
    soilBehaviorIndexText: String = "≤ 1.80",
    minLayerThicknessText: String = "≥ 1.0 m",
    relativeUncertaintyText: String = "± 12%",
    highUncertaintyAreaPercentText: String = "10%",
    highUncertaintyDescription: String =
      "High uncertainty is concentrated in the southern sector, where CPT coverage is limited."
  ) {
    self.shallowestDepthText = shallowestDepthText
    self.deepestDepthText = deepestDepthText
    self.variationDepthText = variationDepthText
    self.coneResistanceText = coneResistanceText
    self.soilBehaviorIndexText = soilBehaviorIndexText
    self.minLayerThicknessText = minLayerThicknessText
    self.relativeUncertaintyText = relativeUncertaintyText
    self.highUncertaintyAreaPercentText = highUncertaintyAreaPercentText
    self.highUncertaintyDescription = highUncertaintyDescription
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 20) {
        // Sheet Header Title & Subtitle
        VStack(alignment: .leading, spacing: 4) {
          Text("Bearing Layer")
            .font(.title2.weight(.bold))
            .foregroundStyle(Color.primary)
            .accessibilityAddTraits(.isHeader)

          Text("Predicted bearing-layer depth across the investigation area")
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        // 1. Depth Summary Section
        depthSummarySection

        // 2. Identification Criteria Section
        identificationCriteriaSection

        // 3. Prediction Uncertainty Section
        predictionUncertaintySection
      }
      .padding(.horizontal, 18)
      .padding(.top, 22)
      .padding(.bottom, 28)
    }
    .background(Color(.systemGroupedBackground))
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
          .font(.subheadline)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
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
        .font(.subheadline)
        .foregroundStyle(Color.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      Text(value)
        .font(.title3.weight(.bold))
        .foregroundStyle(Color.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 14)
    .background(cardBackground)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title): \(value)")
  }

  // MARK: - 2. Identification Criteria

  private var identificationCriteriaSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Identification Criteria")
          .font(.headline.weight(.bold))
          .foregroundStyle(Color.primary)
          .accessibilityAddTraits(.isHeader)

        Text("Criteria used to identify potential bearing layers.")
          .font(.subheadline)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: 10) {
        criteriaRowCard(title: "Cone Resistance (qc)", value: coneResistanceText)
        criteriaRowCard(title: "Soil Behavior Index (Ic)", value: soilBehaviorIndexText)
        criteriaRowCard(title: "Minimum Layer Thickness", value: minLayerThicknessText)
      }
    }
  }

  private func criteriaRowCard(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(Color.secondary)

      Text(value)
        .font(.headline.weight(.bold))
        .foregroundStyle(Color.primary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(cardBackground)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title): \(value)")
  }

  // MARK: - 3. Prediction Uncertainty

  private var predictionUncertaintySection: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Prediction Uncertainty")
          .font(.headline.weight(.bold))
          .foregroundStyle(Color.primary)
          .accessibilityAddTraits(.isHeader)

        Text("Shows uncertainty in predicted bearing layer depths.")
          .font(.subheadline)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      // Relative Prediction Uncertainty Card
      VStack(alignment: .leading, spacing: 4) {
        Text(relativeUncertaintyText)
          .font(.title3.weight(.bold))
          .foregroundStyle(Color.primary)

        Text("Relative prediction uncertainty")
          .font(.caption)
          .foregroundStyle(Color.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .background(cardBackground)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Relative prediction uncertainty: \(relativeUncertaintyText)")

      // High Uncertainty Area Card
      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("High Uncertainty Area")
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.primary)

          Text(highUncertaintyAreaPercentText)
            .font(.title3.weight(.bold))
            .foregroundStyle(Color.primary)

          Text("of total investigation area")
            .font(.caption)
            .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(red: 0.94, green: 0.94, blue: 0.97))
        )

        Text(highUncertaintyDescription)
          .font(.caption)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .background(cardBackground)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        "High Uncertainty Area: \(highUncertaintyAreaPercentText) of total investigation area. \(highUncertaintyDescription)"
      )
    }
  }

  // MARK: - Card Styling

  private var cardBackground: some View {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
      .fill(Color(.secondarySystemGroupedBackground))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(
            Color.primary.opacity(contrast == .increased ? 0.25 : 0.05),
            lineWidth: 1
          )
      )
      .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
  }
}

#Preview {
  ResultBearingLayerSheetView()
    .frame(width: 340)
}
