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

  static let stopSheetDetent: PresentationDetent = .height(286)

  static func isStopped(_ recommendation: CPTRecommendationResult) -> Bool {
    guard let decision = recommendation.stratigraphicDecision else { return false }
    // Consume the active Practical STOP dispatch; legacy sufficiency flags are not evidence.
    return StratigraphicStop.dispatch(decision) { Optional<Bool>.none }.stop
  }

  private var isStopped: Bool { Self.isStopped(recommendation) }

  private var isRecommendationActive: Bool {
    recommendation.hasRecommendation && !isStopped
  }

  var body: some View {
    if isStopped {
      sheetContent
        .frame(idealWidth: 445, maxWidth: 445)
        .background(SheetWidthConfigurator(width: 445))
        .presentationSizing(OneThirdScreenSheetSizing(width: 445))
    } else {
      sheetContent
    }
  }

  private var sheetContent: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: isStopped ? 16 : 18) {
        if isStopped || isRecommendationActive {
          VStack(alignment: .leading, spacing: isStopped ? 10 : 18) {
            Text("Recommended Point")
              .font(isStopped ? .title3.weight(.bold) : .title2.weight(.bold))
              .foregroundStyle(Color.primary)
              .accessibilityAddTraits(.isHeader)

            topRecommendationCard
          }
        }

        // Current Ground Certainty Metric Card
        if isRecommendationActive { metricsSection }

        // Action Buttons: View Analysis 3D and/or Upload Data CPT
        actionButtonsSection

        // "Why this point?" Section
        if isRecommendationActive { whyThisPointSection }

        // Reasons & Supporting Data Card
        if isRecommendationActive { reasonsCard }

        // Bottom Navigation Card: CPT Data entered
        cptDataListCard
          .padding(.top, isStopped ? 8 : 0)
      }
      .padding(.horizontal, isStopped ? 14 : 20)
      .padding(.top, isStopped ? 24 : 16)
      .padding(.bottom, isStopped ? 14 : 24)
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: - Subviews

  private var topRecommendationCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      if isStopped {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "checkmark.circle.fill")
            .font(.body)
            .foregroundStyle(Color.green)
            .padding(.top, 1)
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 3) {
            Text("CPT coverage is sufficient")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Color.primary)

            Text("Current CPT data meets the assessment requirements.")
              .font(.footnote)
              .foregroundStyle(Color.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
      } else if isRecommendationActive {
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
    .padding(.horizontal, 16)
    .padding(.vertical, isStopped ? 18 : 16)
    .background(
      RoundedRectangle(cornerRadius: isStopped ? 22 : 18, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .overlay(
      RoundedRectangle(cornerRadius: isStopped ? 22 : 18, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : (isStopped ? 0 : 0.08)),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
  }

  private var actionButtonsSection: some View {
    Button(action: {
      onUploadTap?()
    }) {
      HStack(spacing: 8) {
        Image(systemName: "square.and.arrow.up")
          .font(isStopped ? .subheadline.weight(.semibold) : .body.weight(.semibold))

        Text("Upload CPT Data")
          .font(isStopped ? .subheadline.weight(.semibold) : .body.weight(.semibold))
      }
      .foregroundStyle(Color.white)
      .frame(maxWidth: .infinity)
      .frame(height: isStopped ? 48 : 50)
      .background(Color.blue, in: Capsule())
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
    // Single Ground Certainty Metric Card
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Current Ground Certainty")
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
        .accessibilityLabel("Current Ground Certainty Information")
        .popover(isPresented: $isConfidenceTooltipPresented) {
          VStack(alignment: .leading, spacing: 0) {
            Text("Shows how well the ground is understood here. A lower percentage indicates an untested blind spot, making this location a priority to test.")
              .font(.subheadline)
              .foregroundStyle(Color.secondary)
              .lineSpacing(4)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.horizontal, 18)
          .padding(.vertical, 16)
          .frame(width: 320)
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
        Text("\(Text("CPT Data").fontWeight(.semibold)) · \(cptPointsCount) entered")
          .font(.subheadline)
          .foregroundStyle(Color.primary)

        Spacer()

        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Color.secondary)
      }
      .padding(.horizontal, 16)
      .frame(height: 52)
      .background(
        RoundedRectangle(cornerRadius: isStopped ? 26 : 16, style: .continuous)
          .fill(Color(.secondarySystemGroupedBackground))
      )
      .overlay(
        RoundedRectangle(cornerRadius: isStopped ? 26 : 16, style: .continuous)
          .stroke(
            Color.primary.opacity(contrast == .increased ? 0.35 : (isStopped ? 0 : 0.08)),
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
