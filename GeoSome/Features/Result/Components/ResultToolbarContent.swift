import SwiftUI

struct ResultToolbarContent: ToolbarContent {
  var selectedTab: ResultAnalysisTab
  var onSelectTab: (ResultAnalysisTab) -> Void

  private var tabBinding: Binding<ResultAnalysisTab> {
    Binding(
      get: { selectedTab },
      set: { onSelectTab($0) }
    )
  }

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

    // Trailing: Native iOS Segmented Picker
    ToolbarItem(placement: .topBarTrailing) {
      Picker("Layer View Mode", selection: tabBinding) {
        ForEach(ResultAnalysisTab.allCases) { tab in
          Text(tab.rawValue)
            .tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 330)
    }
    .sharedBackgroundVisibility(.hidden)
  }
}
