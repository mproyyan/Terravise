import SwiftUI

struct ResultToolbarContent: ToolbarContent {
  var selectedTab: ResultAnalysisTab
  var onSelectTab: (ResultAnalysisTab) -> Void

  @Environment(\.colorSchemeContrast) private var contrast
  @ScaledMetric(relativeTo: .subheadline) private var pillHeight: CGFloat = 36

  var body: some ToolbarContent {
    // Leading: "Back to Recommendation Page" next to native back button
    ToolbarItem(placement: .topBarLeading) {
      HStack(spacing: 4) {
        Text("Back to Recommendation Page")
          .font(.headline)
          .foregroundStyle(Color.primary)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .padding(.vertical, 4)
      .frame(minHeight: 44)
      .layoutPriority(1)
      .accessibilityAddTraits(.isHeader)
      .accessibilityLabel("Back to Recommendation Page")
    }
    .sharedBackgroundVisibility(.hidden)

    // Trailing: Segmented Pill Switcher (3D Layer / Bearing Layer)
    ToolbarItem(placement: .topBarTrailing) {
      HStack(spacing: 4) {
        ForEach(ResultAnalysisTab.allCases) { tab in
          let isSelected = selectedTab == tab
          Button(action: {
            onSelectTab(tab)
          }) {
            HStack(spacing: 6) {
              Image(systemName: tab.iconName)
                .font(.caption.weight(.semibold))
              Text(tab.rawValue)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 16)
            .frame(minHeight: pillHeight)
            .background {
              if isSelected {
                Capsule()
                  .fill(Color(.systemBackground))
                  .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
              }
            }
            .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .frame(minHeight: 44)
          .accessibilityLabel(tab.rawValue)
          .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
      }
      .padding(4)
      .background(
        Capsule()
          .fill(Color(.secondarySystemFill))
      )
      .overlay(
        Capsule()
          .stroke(
            Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
            lineWidth: contrast == .increased ? 1.5 : 1
          )
      )
    }
    .sharedBackgroundVisibility(.hidden)
  }
}
