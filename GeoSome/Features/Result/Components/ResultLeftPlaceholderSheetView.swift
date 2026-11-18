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

struct LegendMapItem: Identifiable, Sendable {
  let id = UUID()
  let name: String
  let color: Color
}

struct ResultLeftPlaceholderSheetView: View {
  var groundConditionsSummary: String
  var concerns: [GeotechnicalConcernItem]
  var isSubsurfaceConditionsEmpty: Bool
  var isGeotechnicalConcernsEmpty: Bool
  var selectedConcernID: String?
  var onSelectConcern: ((GeotechnicalConcernItem) -> Void)?
  var legendItems: [LegendMapItem]
  var predictionUncertaintyPercent: Int
  var cptPointsCount: Int

  @Environment(\.colorSchemeContrast) private var contrast

  static let defaultLegendItems: [LegendMapItem] = [
    LegendMapItem(
      name: "Sensitive fine-grained soil",
      color: Color(red: 203 / 255, green: 55 / 255, blue: 43 / 255)
    ),
    LegendMapItem(
      name: "Clay - organic soil",
      color: Color(red: 169 / 255, green: 104 / 255, blue: 62 / 255)
    ),
    LegendMapItem(
      name: "Clays: clay to silly clay",
      color: Color(red: 84 / 255, green: 82 / 255, blue: 103 / 255)
    ),
    LegendMapItem(
      name: "Silt mixtures: clayey silt & silty clay",
      color: Color(red: 89 / 255, green: 133 / 255, blue: 120 / 255)
    ),
    LegendMapItem(
      name: "Sand mixtures: silty sand to sandy silt",
      color: Color(red: 132 / 255, green: 191 / 255, blue: 149 / 255)
    ),
    LegendMapItem(
      name: "Sands: clean sands to silty sands",
      color: Color(red: 187 / 255, green: 157 / 255, blue: 96 / 255)
    ),
    LegendMapItem(
      name: "Dense sand to gravelly sand",
      color: Color(red: 230 / 255, green: 153 / 255, blue: 77 / 255)
    ),
    LegendMapItem(
      name: "Stiff sand to clayey sand",
      color: Color(red: 156 / 255, green: 146 / 255, blue: 139 / 255)
    ),
    LegendMapItem(
      name: "Stiff fine grained",
      color: Color(red: 231 / 255, green: 221 / 255, blue: 218 / 255)
    )
  ]

  init(
    groundConditionsSummary: String =
      "The site generally exhibits alternating layers of clay-dominant and sand-like soil behavior. Subsurface conditions vary across the investigation area, with deeper competent strata predicted toward the southern sector.",
    concerns: [GeotechnicalConcernItem] = ResultAnalysisViewModel.defaultConcerns,
    isSubsurfaceConditionsEmpty: Bool = false,
    isGeotechnicalConcernsEmpty: Bool = false,
    selectedConcernID: String? = nil,
    onSelectConcern: ((GeotechnicalConcernItem) -> Void)? = nil,
    legendItems: [LegendMapItem] = Self.defaultLegendItems,
    predictionUncertaintyPercent: Int = 12,
    cptPointsCount: Int = 12
  ) {
    self.groundConditionsSummary = groundConditionsSummary
    self.concerns = concerns
    self.isSubsurfaceConditionsEmpty = isSubsurfaceConditionsEmpty
    self.isGeotechnicalConcernsEmpty = isGeotechnicalConcernsEmpty
    self.selectedConcernID = selectedConcernID
    self.onSelectConcern = onSelectConcern
    self.legendItems = legendItems
    self.predictionUncertaintyPercent = predictionUncertaintyPercent
    self.cptPointsCount = cptPointsCount
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
        }

        // 3. Legend Map Section
        legendMapSectionHeader

        legendMapCard

        // 4. Model Reliability Section
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
        HStack(alignment: .top, spacing: 8) {
          Text(concern.title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(isSelected ? Color.blue : Color.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

          Spacer(minLength: 4)

          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18))
            .foregroundStyle(isSelected ? Color.blue : Color(.systemGray3))
            .accessibilityHidden(true)
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
      .padding(isSelected ? 10 : 0)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(isSelected ? Color.blue.opacity(0.08) : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(concern.title)
    .accessibilityValue(
      ([isSelected ? "Selected" : "Not selected", concern.implication] + concern.locationAndDepthLines)
        .joined(separator: ", ")
    )
    .accessibilityHint("Double-tap to toggle 3D highlight for this concern")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var legendMapSectionHeader: some View {
    Text("Legend Map")
      .font(.headline.weight(.bold))
      .foregroundStyle(Color.primary)
      .padding(.top, 2)
      .accessibilityAddTraits(.isHeader)
  }

  private var legendMapCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(legendItems) { item in
        legendRow(for: item)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(cardBackground)
    .overlay(cardStroke)
  }

  private func legendRow(for item: LegendMapItem) -> some View {
    HStack(spacing: 12) {
      Circle()
        .fill(item.color)
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)

      Text(item.name)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(item.name)
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
