import SwiftUI

struct CPTRecommendationToolbarContent: ToolbarContent {
  var projectName: String
  var onEditAreaTap: (() -> Void)?
  var onViewAnalysis3DTap: (() -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast
  @ScaledMetric(relativeTo: .subheadline) private var controlHeight: CGFloat = 36

  init(
    projectName: String,
    onEditAreaTap: (() -> Void)? = nil,
    onViewAnalysis3DTap: (() -> Void)? = nil
  ) {
    self.projectName = projectName
    self.onEditAreaTap = onEditAreaTap
    self.onViewAnalysis3DTap = onViewAnalysis3DTap
  }

  private var displayProjectName: String {
    projectName.isEmpty ? "Project name" : projectName
  }

  var body: some ToolbarContent {
    // Leading: Read-only Project Name (next to native back button, full text without truncation)
    ToolbarItem(placement: .topBarLeading) {
      HStack(spacing: 4) {
        Text(displayProjectName)
          .font(.headline)
          .foregroundStyle(Color.primary)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .padding(.vertical, 4)
      .frame(minHeight: 44)
      .layoutPriority(1)
      .accessibilityAddTraits(.isHeader)
      .accessibilityLabel("Project: \(displayProjectName)")
    }
    .sharedBackgroundVisibility(.hidden)

    // Trailing: Edit Area and View Analysis 3D
    ToolbarItemGroup(placement: .topBarTrailing) {
      HStack(spacing: 8) {
        // Edit Area Button
        Button(action: {
          onEditAreaTap?()
        }) {
          HStack(spacing: 4) {
            Text("Edit Area")
              .font(.subheadline.weight(.medium))
          }
          .foregroundStyle(Color.primary)
          .padding(.horizontal, 14)
          .frame(minHeight: controlHeight)
          .clipShape(Capsule())
          .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
        }
        .frame(minWidth: 44, minHeight: 44)
        .buttonStyle(.glass(.regular))
        .buttonBorderShape(.automatic)
        .accessibilityLabel("Edit Area")
        .accessibilityHint("Edits the boundary area for this project")
        .accessibilityInputLabels(["Edit Area", "Edit Boundary", "Area"])

        // View Analysis 3D Button
        Button(action: {
          onViewAnalysis3DTap?()
        }) {
          HStack(spacing: 5) {
            Text("View Analysis 3D")
              .font(.subheadline.weight(.semibold))
          }
          .foregroundStyle(Color.white)
          .padding(.horizontal, 16)
          .frame(minHeight: controlHeight)
          .clipShape(Capsule())
          .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 1)
        }
        .frame(minWidth: 44, minHeight: 44)
        .buttonStyle(.glass(.regular.tint(.blue)))
        .buttonBorderShape(.automatic)
        .accessibilityLabel("View Analysis 3D")
        .accessibilityHint("Opens the 3D analysis view for this site")
        .accessibilityInputLabels(["View Analysis 3D", "Analysis 3D", "3D View"])
      }
    }
    .sharedBackgroundVisibility(.hidden)
  }
}
