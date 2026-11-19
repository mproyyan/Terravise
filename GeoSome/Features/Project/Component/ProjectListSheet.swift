import SwiftUI

struct ProjectListSheet: View {
  let projects: [Project]
  var onSelectProject: ((Project) -> Void)?

  init(
    projects: [Project],
    onSelectProject: ((Project) -> Void)? = nil
  ) {
    self.projects = projects
    self.onSelectProject = onSelectProject
  }

  var body: some View {
    VStack(spacing: 12) {
      // Pinned Header
      Text("All Projects")
        .font(.headline)
        .foregroundStyle(.primary)
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
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
              ForEach(projects) { project in
                ProjectCardView(project: project) {
                  onSelectProject?(project)
                }
                .id(project.id)
              }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
          }
          .frame(minHeight: 156, alignment: .topLeading)
          .padding(.top, 4)
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
