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
  @State private var isConfidenceTooltipPresented = false

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
      VStack(alignment: .leading, spacing: 16) {
        // Sheet Title
        Text(sheetTitle)
          .font(.title2.weight(.bold))
          .foregroundStyle(Color.primary)
          .accessibilityAddTraits(.isHeader)

        if recommendation.isSufficient {
          // Sufficient State matching target design
          sufficientCoverageCard

          uploadButton

          cptDataListCard
        } else {
          // Top Card: Recommendation Coordinate & Run CPT Warning
          if recommendation.hasRecommendation {
            topRecommendationCard
          } else {
            Text("Tidak ada kandidat DQN yang tersedia untuk kriteria jarak dan area saat ini, atau model tidak dapat dijalankan.")
              .foregroundStyle(.secondary)
          }

          // Spot Confidence Metric Card
          metricsSection

          // Primary Action: Upload CPT Data
          uploadButton

          // "Why this point?" Section
          if recommendation.hasRecommendation {
            whyThisPointSection
          }

          // Reasons & Supporting Data Card
          if recommendation.hasRecommendation {
            reasonsCard
          }

          // Bottom Navigation Card: CPT Data entered
          cptDataListCard
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)
      .padding(.bottom, 24)
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var sheetTitle: String {
    if recommendation.isSufficient || recommendation.hasRecommendation {
      return "Recommended Point"
    } else {
      return "Rekomendasi belum tersedia"
    }
  }

  private var sufficientCoverageCard: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 24, weight: .bold))
        .foregroundStyle(Color.green)
        .padding(.top, 1)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text("CPT coverage is sufficient")
          .font(.headline.weight(.bold))
          .foregroundStyle(Color.primary)

        Text("Current CPT data meets the assessment requirements.")
          .font(.subheadline)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
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
    .accessibilityElement(children: .combine)
    .accessibilityLabel("CPT coverage is sufficient. Current CPT data meets the assessment requirements.")
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

        Text("Upload CPT Data")
          .font(.body.weight(.semibold))
      }
      .foregroundStyle(Color.white)
      .frame(maxWidth: .infinity)
      .frame(height: 52)
      .background(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(Color.blue)
      )
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Upload CPT Data")
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
    // Single Spot Confidence Metric Card
    VStack(alignment: .leading, spacing: 6) {
      HStack {
          Text("Recommendation Confidence")
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.secondary)


        Spacer()

        Button(action: {
          isConfidenceTooltipPresented.toggle()
          onConfidenceInfoTap?()
        }) {
          Image(systemName: "info.circle")
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Spot Confidence Information")
        .popover(isPresented: $isConfidenceTooltipPresented) {
          Text("How confident the AI is that this is the best spot to test next to reduce blind spots.")
            .font(.subheadline)
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: 260)
            .presentationCompactAdaptation(.popover)
        }
      }
        Text("\(recommendation.confidenceLevel)%")
          .font(.title2.weight(.bold))
          .foregroundStyle(Color.primary)
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

  private var reasonsCard: some View {
    let spotName = CPTRecommendationResult.normalizeSpotName(recommendation.spotName)
    let distText = String(format: "%.1f", recommendation.nearestCPTDistance)
    let deltaIcText = String(format: "%.2f", recommendation.lateralIcDifference)
    let nearbyCountText = recommendation.nearbyCountWithin4m == 0
      ? "none within 4 m"
      : "\(recommendation.nearbyCountWithin4m) within 4 m"

    return VStack(alignment: .leading, spacing: 14) {
      // Reason 1: Spatial Coverage (3-Tier)
      VStack(alignment: .leading, spacing: 4) {
        if recommendation.nearestCPTDistance >= 15.0 && recommendation.nearbyCountWithin4m == 0 {
          Text("Closes a major coverage gap")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)

          Text("**\(spotName)** lies **\(distText) m** from the nearest sounding in an untested sector of the site (\(nearbyCountText)). Sampling here prevents long-distance extrapolation across this zone.")
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else if recommendation.nearbyCountWithin4m == 0 && recommendation.nearestCPTDistance >= 4.0 {
          Text("Fills a local data gap")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)

          Text("**\(spotName)** is **\(distText) m** from the closest CPT with \(nearbyCountText), adding direct control where current interpolation relies on surrounding points.")
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Text("Refines a high-variability zone")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)

          Text("Although **\(spotName)** is **\(distText) m** from an existing CPT (\(nearbyCountText)), the model prioritizes tighter spacing here to pin down local soil changes.")
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Divider()

      // Reason 2: Vertical Stratigraphy
      VStack(alignment: .leading, spacing: 4) {
        if recommendation.shallowSoilType.caseInsensitiveCompare(recommendation.deepSoilType) != .orderedSame {
          Text("Pinpoints a vertical layer transition")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)

          Text("The reconstruction indicates **\(recommendation.shallowSoilType)** in the upper profile transitioning to **\(recommendation.deepSoilType)** at depth. A sounding at **\(spotName)** verifies the exact depth of this interface.")
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Text("Confirms deep layer continuity")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)

          Text("The model predicts a consistent **\(recommendation.shallowSoilType)** profile from surface to depth. Testing **\(spotName)** confirms vertical consistency and exact layer thickness.")
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Divider()

      // Reason 3: Lateral Transition (3-Tier)
      VStack(alignment: .leading, spacing: 4) {
        if recommendation.lateralIcDifference >= 0.20 {
          Text("Maps a sharp lateral soil boundary")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)

          Text("The predicted profile at **\(spotName)** shifts significantly (ΔIc \(deltaIcText)) compared to adjacent cells within 4 m, suggesting a lateral boundary or pinching lens.")
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else if recommendation.lateralIcDifference >= 0.05 {
          Text("Tracks a gradual lateral transition")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)

          Text("Soil behavior at **\(spotName)** differs moderately (ΔIc \(deltaIcText)) from the surrounding 4 m average, helping trace how strata dip or grade across the site.")
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Text("Anchors uncertainty in a broad zone")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)

          Text("Nearby cells show a similar predicted profile (ΔIc \(deltaIcText)), but **\(spotName)** sits where local uncertainty is elevated—anchoring the reconstruction for this sector.")
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
          .font(.headline.weight(.bold))
          .foregroundStyle(Color.primary)

        Spacer()

        Image(systemName: "chevron.right")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.secondary)
      }
      .padding(.horizontal, 16)
      .frame(height: 54)
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
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("CPT Data, \(cptPointsCount) entered")
    .accessibilityHint("Opens list of entered CPT data")
  }
}

#Preview("Sufficient Coverage") {
  CPTRecommendedPointSheetView(
    recommendation: CPTRecommendationResult(
      consecutiveSufficientCount: 3,
      isSufficient: true
    ),
    cptPointsCount: 1
  )
  .padding()
  .background(Color(.systemGroupedBackground))
}

#Preview("Recommendation") {
  CPTRecommendedPointSheetView(
    recommendation: CPTRecommendationResult(),
    cptPointsCount: 1
  )
  .padding()
  .background(Color(.systemGroupedBackground))
}
