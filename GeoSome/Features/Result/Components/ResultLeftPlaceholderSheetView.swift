import SwiftUI
import UIKit

struct OneThirdScreenSheetSizing: PresentationSizing {
  var width: CGFloat

  func proposedSize(
    for root: PresentationSizingRoot,
    context: PresentationSizingContext
  ) -> ProposedViewSize {
    let fittingSize = root.sizeThatFits(ProposedViewSize(width: width, height: nil))
    return ProposedViewSize(width: width, height: fittingSize.height)
  }
}

struct SheetWidthConfigurator: UIViewControllerRepresentable {
  var width: CGFloat

  func makeUIViewController(context: Context) -> UIViewController {
    let controller = SheetWidthController()
    controller.targetWidth = width
    return controller
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    if let controller = uiViewController as? SheetWidthController {
      controller.targetWidth = width
      controller.applySheetWidth()
    }
  }

  private final class SheetWidthController: UIViewController {
    var targetWidth: CGFloat = 360

    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      applySheetWidth()
    }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      applySheetWidth()
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      applySheetWidth()
    }

    func applySheetWidth() {
      guard targetWidth > 0 else { return }

      var current: UIViewController? = self
      while let vc = current {
        if vc.preferredContentSize.width != targetWidth {
          vc.preferredContentSize = CGSize(
            width: targetWidth,
            height: vc.preferredContentSize.height
          )
        }
        if let sheet = vc.sheetPresentationController {
          sheet.prefersPageSizing = false
          sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
          let presented = sheet.presentedViewController
          if presented.preferredContentSize.width != targetWidth {
            presented.preferredContentSize = CGSize(
              width: targetWidth,
              height: presented.preferredContentSize.height
            )
          }
          break
        }
        current = vc.parent
      }
    }
  }
}

struct ResultLeftPlaceholderSheetView: View {
  var groundConditionsSummary: String
  var concerns: [GeotechnicalConcernItem]
  var isSubsurfaceConditionsEmpty: Bool
  var isGeotechnicalConcernsEmpty: Bool
  var selectedConcernID: String?
  var predictionUncertaintyPercent: Int
  var cptPointsCount: Int
  var onSelectConcern: ((GeotechnicalConcernItem) -> Void)?
  var onClearHighlight: (() -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast

  init(
    groundConditionsSummary: String =
      "The site generally exhibits alternating layers of clay-dominant and sand-like soil behavior. Subsurface conditions vary across the investigation area, with deeper competent strata predicted toward the southern sector.",
    concerns: [GeotechnicalConcernItem] = ResultAnalysisViewModel.defaultConcerns,
    isSubsurfaceConditionsEmpty: Bool = false,
    isGeotechnicalConcernsEmpty: Bool = false,
    selectedConcernID: String? = ResultAnalysisViewModel.defaultConcerns.first?.id,
    predictionUncertaintyPercent: Int = 12,
    cptPointsCount: Int = 12,
    onSelectConcern: ((GeotechnicalConcernItem) -> Void)? = nil,
    onClearHighlight: (() -> Void)? = nil
  ) {
    self.groundConditionsSummary = groundConditionsSummary
    self.concerns = concerns
    self.isSubsurfaceConditionsEmpty = isSubsurfaceConditionsEmpty
    self.isGeotechnicalConcernsEmpty = isGeotechnicalConcernsEmpty
    self.selectedConcernID = selectedConcernID
    self.predictionUncertaintyPercent = predictionUncertaintyPercent
    self.cptPointsCount = cptPointsCount
    self.onSelectConcern = onSelectConcern
    self.onClearHighlight = onClearHighlight
  }

  private var shouldShowSubsurfaceEmpty: Bool {
    isSubsurfaceConditionsEmpty || groundConditionsSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var shouldShowConcernsEmpty: Bool {
    isGeotechnicalConcernsEmpty || concerns.isEmpty
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 18) {
        // Sheet Header Title
        Text("Subsurface Conditions")
          .font(.title2.weight(.bold))
          .foregroundStyle(Color.primary)
          .accessibilityAddTraits(.isHeader)

        // 1. Ground Conditions Card (or Empty State)
        if shouldShowSubsurfaceEmpty {
          subsurfaceConditionsEmptyCard
        } else {
          groundConditionsCard
        }

        // 2. Potential Geotechnical Concerns Section
        concernsSectionHeader

        if shouldShowConcernsEmpty {
          geotechnicalConcernsEmptyCard
        } else {
          concernsListCard

          // Clear Highlight Pill Button (only when concerns are present)
          clearHighlightButton
        }

        // 3. Model Reliability Section
        Text("Model Reliability")
          .font(.headline.weight(.bold))
          .foregroundStyle(Color.primary)
          .padding(.top, 2)
          .accessibilityAddTraits(.isHeader)

        predictionUncertaintyCard

        dataCoverageCard
      }
      .padding(.horizontal, 18)
      .padding(.top, 20)
      .padding(.bottom, 28)
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityLabel("Subsurface Conditions sheet")
  }

  // MARK: - Subviews

  private var subsurfaceConditionsEmptyCard: some View {
    VStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(Color.orange.opacity(0.15))
          .frame(width: 52, height: 52)

        ZStack(alignment: .bottomTrailing) {
          Image(systemName: "square.3.layers.3d.down.right")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(Color.orange)

          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.orange)
            .offset(x: 3, y: 3)
        }
      }
      .accessibilityHidden(true)

      VStack(spacing: 4) {
        Text("More CPT data needed")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Color.primary)

        Text("Add CPT data to view the subsurface profile.")
          .font(.footnote)
          .foregroundStyle(Color.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 22)
    .padding(.horizontal, 16)
    .background(cardBackground)
    .overlay(cardStroke)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("More CPT data needed. Add CPT data to view the subsurface profile.")
  }

  private var groundConditionsCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Ground Conditions")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Color.primary)

      Text(groundConditionsSummary)
        .font(.footnote)
        .foregroundStyle(Color.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(cardBackground)
    .overlay(cardStroke)
    .accessibilityElement(children: .combine)
  }

  private var concernsSectionHeader: some View {
    HStack(spacing: 8) {
      if !shouldShowConcernsEmpty {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.orange)
          .accessibilityHidden(true)
      }

      Text("Potential Geotechnical Concerns")
        .font(.headline.weight(.bold))
        .foregroundStyle(Color.primary)
    }
    .padding(.top, 2)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }

  private var geotechnicalConcernsEmptyCard: some View {
    VStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(Color.green.opacity(0.15))
          .frame(width: 52, height: 52)

        Image(systemName: "checkmark")
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(Color.green)
      }
      .accessibilityHidden(true)

      VStack(spacing: 4) {
        Text("All clear for now")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Color.primary)

        Text("Current findings meet the assessment criteria.")
          .font(.footnote)
          .foregroundStyle(Color.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 22)
    .padding(.horizontal, 16)
    .background(cardBackground)
    .overlay(cardStroke)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("All clear for now. Current findings meet the assessment criteria.")
  }

  private var concernsListCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(Array(concerns.enumerated()), id: \.element.id) { index, concern in
        concernRow(for: concern)

        if index < concerns.count - 1 {
          Divider()
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(cardBackground)
    .overlay(cardStroke)
  }

  private func concernRow(for concern: GeotechnicalConcernItem) -> some View {
    let isSelected = selectedConcernID == concern.id

    return Button(action: {
      onSelectConcern?(concern)
    }) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 12) {
          Text(concern.title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

          Spacer(minLength: 4)

          if isSelected {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 22))
              .symbolRenderingMode(.palette)
              .foregroundStyle(Color.white, Color.blue)
              .accessibilityHidden(true)
          } else {
            Image(systemName: "circle")
              .font(.system(size: 22, weight: .regular))
              .foregroundStyle(Color(.systemGray3))
              .accessibilityHidden(true)
          }
        }

        Text(concern.implication)
          .font(.footnote)
          .foregroundStyle(Color.secondary)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 2) {
          ForEach(concern.locationAndDepthLines, id: \.self) { line in
            Text(line)
              .font(.footnote)
              .foregroundStyle(Color.secondary)
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(concern.title)
    .accessibilityValue(
      ([isSelected ? "Selected" : "Not selected", concern.implication] + concern.locationAndDepthLines)
        .joined(separator: ", ")
    )
    .accessibilityHint("Double-tap to toggle highlight for this geotechnical concern")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var clearHighlightButton: some View {
    Button(action: {
      onClearHighlight?()
    }) {
      HStack(spacing: 6) {
        Image(systemName: "xmark")
          .font(.footnote.weight(.semibold))

        Text("Clear Highlight")
          .font(.subheadline.weight(.medium))
      }
      .foregroundStyle(Color.blue)
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .background(
        Capsule()
          .fill(Color(.tertiarySystemFill))
      )
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Clear Highlight")
    .accessibilityHint("Clears the active geotechnical concern highlight")
  }

  private var predictionUncertaintyCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Prediction Uncertainty")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.secondary)

      Text("\(predictionUncertaintyPercent) %")
        .font(.title2.weight(.bold))
        .foregroundStyle(Color.primary)

      Text("Indicates how uncertain the model's predictions are across the site.")
        .font(.footnote)
        .foregroundStyle(Color.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(cardBackground)
    .overlay(cardStroke)
    .accessibilityElement(children: .combine)
  }

  private var dataCoverageCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Data Coverage")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.secondary)

      Text("\(cptPointsCount) CPT Points")
        .font(.title2.weight(.bold))
        .foregroundStyle(Color.primary)

      Text("Shows the extent of actual CPT data supporting the reconstructed model.")
        .font(.footnote)
        .foregroundStyle(Color.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(cardBackground)
    .overlay(cardStroke)
    .accessibilityElement(children: .combine)
  }

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

#Preview("Populated") {
  ResultLeftPlaceholderSheetView()
    .frame(width: 360)
    .background(Color(.systemGroupedBackground))
}

#Preview("Empty State") {
  ResultLeftPlaceholderSheetView(
    isSubsurfaceConditionsEmpty: true,
    isGeotechnicalConcernsEmpty: true
  )
  .frame(width: 360)
  .background(Color(.systemGroupedBackground))
}
