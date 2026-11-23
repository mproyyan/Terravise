import SwiftUI

/// Read-only presentation; no STOP/DQN action or model inference lives here.
struct StratigraphicCharacterizationView: View {
  let assessment: StratigraphicCharacterization

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Observed stratigraphic characterization")
        .font(.headline)
        .accessibilityAddTraits(.isHeader)

      Text(assessment.observedCharacterizationStatus.rawValue)
        .font(.subheadline.weight(.semibold))
        .accessibilityIdentifier("observed-characterization-status")

      Text(assessment.explanation)
        .font(.caption)
        .foregroundStyle(.secondary)

      ForEach(assessment.reasonDescriptions, id: \.self) { reason in
        Text("• \(reason)")
          .font(.caption)
          .fixedSize(horizontal: false, vertical: true)
      }

      Divider()

      Text("Unobserved geology risk: \(assessment.unobservedGeologyRisk.rawValue)")
        .font(.caption.weight(.semibold))
        .accessibilityIdentifier("unobserved-geology-risk")

      Text("Undetected geological units may remain. This is not a geological safety certification.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Text("Informational readout of the active stratigraphic decision. A valid STOP ends automatic CPT recommendations; this label does not independently trigger STOP.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    .accessibilityElement(children: .contain)
  }
}
