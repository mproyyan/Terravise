import SwiftUI

struct ProjectListSheet: View {
  let projects: [Project]
  var onSelectProject: ((Project) -> Void)?
  var onRenameProject: ((UUID, String) -> Void)?
  var onDeleteProject: ((UUID) -> Void)?

  init(
    projects: [Project],
    onSelectProject: ((Project) -> Void)? = nil,
    onRenameProject: ((UUID, String) -> Void)? = nil,
    onDeleteProject: ((UUID) -> Void)? = nil
  ) {
    self.projects = projects
    self.onSelectProject = onSelectProject
    self.onRenameProject = onRenameProject
    self.onDeleteProject = onDeleteProject
  }

  var body: some View {
    VStack(spacing: 12) {
      // Pinned Header
      Text("All Projects")
        .font(.headline)
//        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .accessibilityAddTraits(.isHeader)

      // Sheet Content
      if projects.isEmpty {
        EmptyProjectStateView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView(.vertical, showsIndicators: false) {
          LazyVGrid(
            columns: Array(
              repeating: GridItem(.flexible(minimum: 0), spacing: 16, alignment: .top),
              count: 6
            ),
            alignment: .center,
            spacing: 16
          ) {
            ForEach(projects) { project in
              ProjectCardView(
                project: project,
                onSelect: { onSelectProject?(project) },
                onRename: { newName in onRenameProject?(project.id, newName) },
                onDelete: { onDeleteProject?(project.id) }
              )
              .id(project.id)
            }
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 8)
          .accessibilityRotor("Projects") {
            ForEach(projects) { project in
              AccessibilityRotorEntry(project.name, id: project.id)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .presentationSizing(FullWidthPresentationSizing())
    .presentationDetents(
      [
        ProjectViewModel.defaultSheetDetent,
        ProjectViewModel.expandedSheetDetent
      ]
    )
    .presentationDragIndicator(.visible)
    .presentationBackground(.background)
    .presentationBackgroundInteraction(.enabled)
    .presentationContentInteraction(.scrolls)
    .interactiveDismissDisabled()
  }
}

struct FullWidthPresentationSizing: PresentationSizing {
  func proposedSize(
    for _: PresentationSizingRoot,
    context _: PresentationSizingContext
  ) -> ProposedViewSize {
    ProposedViewSize(width: .infinity, height: nil)
  }
}

#Preview("Empty State") {
  Color.black.ignoresSafeArea()
    .sheet(isPresented: .constant(true)) {
      ProjectListSheet(projects: [])
    }
}
