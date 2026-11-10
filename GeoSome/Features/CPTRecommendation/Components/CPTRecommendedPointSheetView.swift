import CoreLocation
import SwiftUI

struct CPTRecommendedPointSheetView: View {
  var recommendation: CPTRecommendationResult
  var cptPointsCount: Int
  var onUploadTap: (() -> Void)?
  var onRMSEInfoTap: (() -> Void)?
  var onConfidenceInfoTap: (() -> Void)?
  var onSeeSupportingDataTap: (() -> Void)?
  var onCPTDataListTap: (() -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

  init(
    recommendation: CPTRecommendationResult = CPTRecommendationResult(),
    cptPointsCount: Int = 1,
    onUploadTap: (() -> Void)? = nil,
    onRMSEInfoTap: (() -> Void)? = nil,
    onConfidenceInfoTap: (() -> Void)? = nil,
    onSeeSupportingDataTap: (() -> Void)? = nil,
    onCPTDataListTap: (() -> Void)? = nil
  ) {
    self.recommendation = recommendation
    self.cptPointsCount = cptPointsCount
    self.onUploadTap = onUploadTap
    self.onRMSEInfoTap = onRMSEInfoTap
    self.onConfidenceInfoTap = onConfidenceInfoTap
    self.onSeeSupportingDataTap = onSeeSupportingDataTap
    self.onCPTDataListTap = onCPTDataListTap
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 18) {
        // Sheet Title
        Text(recommendation.isSufficient ? "Sufficiency Reached" : "Recommended Point")
          .font(.title2.weight(.bold))
          .foregroundStyle(Color.primary)
          .accessibilityAddTraits(.isHeader)

        // Top Card: Recommendation Coordinate & Run CPT Warning (or Sufficiency Banner)
        topRecommendationCard

        // Primary Action: Upload Data CPT
        uploadButton

        // "Why this point?" Section
        whyThisPointSection

        // Metrics: RMSE and Confidence Level
        metricsSection

        // Reasons & Supporting Data Card
        reasonsCard

        // Bottom Navigation Card: CPT Data entered
        cptDataListCard
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)
      .padding(.bottom, 24)
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: - Subviews

  private var topRecommendationCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      if recommendation.isSufficient {
        // Row 1: Green Checkmark Icon + Sufficient Status
        HStack(spacing: 12) {
          ZStack {
            Circle()
              .fill(Color.green)
              .frame(width: 34, height: 34)

            Image(systemName: "checkmark")
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(.white)
          }
          .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 2) {
            Text("CPT Investigation Status")
              .font(.caption.weight(.medium))
              .foregroundStyle(Color.secondary)

            Text("Sufficient — No More CPT Needed")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(Color.primary)
          }

          Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("CPT Investigation Status: Sufficient, no more CPT needed")

        Divider()

        // Row 2: Sufficiency Banner
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 20))
            .foregroundStyle(Color.green)
            .padding(.top, 2)
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 4) {
            Text("Stopping criterion reached (\(recommendation.consecutiveSufficientCount)/3)")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(Color.primary)

            Text("3D subsurface reconstruction has met the ≥98% sufficiency threshold across 3 consecutive CPT evaluations.")
              .font(.caption)
              .foregroundStyle(Color.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stopping criterion reached. 3D subsurface reconstruction has met the sufficiency threshold.")
      } else {
        // Row 1: Green X/Cross Icon + Coordinate
        HStack(spacing: 12) {
          ZStack {
            Circle()
              .fill(Color.green)
              .frame(width: 34, height: 34)

            Image(systemName: "xmark")
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(.white)
          }
          .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 2) {
            Text("CPT Point Recommendation")
              .font(.caption.weight(.medium))
              .foregroundStyle(Color.secondary)

            Text(recommendation.formattedCoordinate)
              .font(.subheadline.weight(.bold))
              .foregroundStyle(Color.primary)
          }

          Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("CPT Point Recommendation at \(recommendation.formattedCoordinate)")

        Divider()

        // Row 2: Warning Banner
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 20))
            .foregroundStyle(Color.orange)
            .padding(.top, 2)
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 4) {
            Text("Run a CPT at this point")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(Color.primary)

            Text("Nearby CPT data is limited, so the local soil profile is uncertain.")
              .font(.caption)
              .foregroundStyle(Color.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: Run a CPT at this point. Nearby CPT data is limited, so the local soil profile is uncertain.")
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
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
  }

  private var uploadButton: some View {
    Button(action: {
      onUploadTap?()
    }) {
      HStack(spacing: 8) {
        Image(systemName: "square.and.arrow.up")
          .font(.body.weight(.semibold))

        Text("Upload Data CPT")
          .font(.body.weight(.semibold))
      }
      .foregroundStyle(Color.white)
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .background(Color.blue, in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Upload Data CPT")
    .accessibilityHint("Opens sheet to upload additional CPT data")
  }

  private var whyThisPointSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Why this point?")
        .font(.headline.weight(.bold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)

      Text("The model looks for three signs that a new CPT could add useful information: areas with little nearby data, soil layers that may change with depth, and soil that may differ from nearby locations.")
        .font(.subheadline)
        .foregroundStyle(Color.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var metricsSection: some View {
    HStack(spacing: 12) {
      // RMSE Metric Card
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(String(format: "%.4f", recommendation.rmse))
            .font(.title2.weight(.bold))
            .foregroundStyle(Color.primary)

          Spacer()

          Button(action: {
            onRMSEInfoTap?()
          }) {
            Image(systemName: "info.circle")
              .font(.subheadline)
              .foregroundStyle(Color.secondary)
              .frame(minWidth: 28, minHeight: 28)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("RMSE Information")
        }

        Text("RMSE")
          .font(.caption.weight(.medium))
          .foregroundStyle(Color.secondary)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
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

      // Confidence Level Metric Card
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("\(recommendation.confidenceLevel)%")
            .font(.title2.weight(.bold))
            .foregroundStyle(Color.primary)

          Spacer()

          Button(action: {
            onConfidenceInfoTap?()
          }) {
            Image(systemName: "info.circle")
              .font(.subheadline)
              .foregroundStyle(Color.secondary)
              .frame(minWidth: 28, minHeight: 28)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Confidence Level Information")
        }

        Text("Confidence Level")
          .font(.caption.weight(.medium))
          .foregroundStyle(Color.secondary)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
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

  private var reasonsCard: some View {
    let nearbyCountText = recommendation.nearbyCountWithin4m == 0
      ? "none within 4 m"
      : "\(recommendation.nearbyCountWithin4m) within 4 m"

    return VStack(alignment: .leading, spacing: 14) {
      // Reason 1
      VStack(alignment: .leading, spacing: 4) {
        Text("Fills a data gap")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Color.primary)

        Text("\(recommendation.spotName) is \(String(format: "%.1f", recommendation.nearestCPTDistance)) m from the nearest CPT, with \(nearbyCountText). There is less nearby data to describe the ground in this area.")
          .font(.caption)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Divider()

      // Reason 2
      VStack(alignment: .leading, spacing: 4) {
        Text("Soil layers may change with depth")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Color.primary)

        Text("The model predicts **\(recommendation.shallowSoilType)** near the surface and **\(recommendation.deepSoilType)** deeper down. A CPT can check where that change occurs.")
          .font(.caption)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Divider()

      // Reason 3
      VStack(alignment: .leading, spacing: 4) {
        Text("Soil may differ from nearby areas")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Color.primary)

        Text("The predicted soil profile at **\(recommendation.spotName)** differs (ΔIc \(String(format: "%.2f", recommendation.lateralIcDifference))) from the average nearby profile within 4 m. \(recommendation.spotName) may be close to a boundary between soil zones.")
          .font(.caption)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Divider()

      // Action row: See Supporting Data
      Button(action: {
        onSeeSupportingDataTap?()
      }) {
        HStack(spacing: 8) {
          Image(systemName: "info.circle")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.blue)

          Text("See Supporting Data")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.blue)

          Spacer()

          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.secondary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("See Supporting Data")
      .accessibilityHint("Opens supporting data analysis for recommended point")
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
  }

  private var cptDataListCard: some View {
    Button(action: {
      onCPTDataListTap?()
    }) {
      HStack {
        Text("CPT Data • \(cptPointsCount) entered")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Color.primary)

        Spacer()

        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Color.secondary)
      }
      .padding(.horizontal, 16)
      .frame(height: 52)
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
    .buttonStyle(.plain)
    .accessibilityLabel("CPT Data, \(cptPointsCount) entered")
    .accessibilityHint("Opens list of entered CPT data")
  }
}

#Preview {
  CPTRecommendedPointSheetView(
    recommendation: CPTRecommendationResult(),
    cptPointsCount: 1
  )
  .padding()
  .background(Color(.systemGroupedBackground))
}
