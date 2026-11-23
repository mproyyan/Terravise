import SwiftUI

struct ProjectListSheet: View {
  let projects: [Project]
  var onSelectProject: ((Project) -> Void)?
  var onRenameProject: ((Project, String) -> Void)?
  var onDeleteProject: ((Project) -> Void)?

  @State private var projectToRename: Project?
  @State private var isRenameAlertPresented: Bool = false
  @State private var renameDraftName: String = ""

  @State private var projectToDelete: Project?
  @State private var isDeleteAlertPresented: Bool = false
  @ScaledMetric(relativeTo: .body) private var cardColumnWidth: CGFloat = 156

  private var gridColumns: [GridItem] {
    [
      GridItem(
        .adaptive(minimum: cardColumnWidth, maximum: 260),
        spacing: 14,
        alignment: .top
      )
    ]
  }

  init(
    projects: [Project],
    onSelectProject: ((Project) -> Void)? = nil,
    onRenameProject: ((Project, String) -> Void)? = nil,
    onDeleteProject: ((Project) -> Void)? = nil
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
          LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 14) {
            ForEach(projects) { project in
              ProjectCardView(
                project: project,
                action: {
                  onSelectProject?(project)
                },
                onRename: {
                  projectToRename = project
                  renameDraftName = project.name
                  isRenameAlertPresented = true
                },
                onDelete: {
                  projectToDelete = project
                  isDeleteAlertPresented = true
                }
              )
              .id(project.id)
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 8)
          .padding(.bottom, 24)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .accessibilityRotor("Projects") {
            ForEach(projects) { project in
              AccessibilityRotorEntry(project.name, id: project.id)
            }
          }
        }
      }
    }
    .alert(
      "Rename Project",
      isPresented: $isRenameAlertPresented,
      presenting: projectToRename
    ) { project in
      TextField("Project name", text: $renameDraftName)
      Button("Save") {
        let trimmed = renameDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          onRenameProject?(project, trimmed)
        }
        projectToRename = nil
      }
      Button("Cancel", role: .cancel) {
        projectToRename = nil
      }
    } message: { _ in
      Text("Enter a new name for this project.")
    }
    .alert(
      "Delete Project?",
      isPresented: $isDeleteAlertPresented,
      presenting: projectToDelete
    ) { project in
      Button("Delete", role: .destructive) {
        onDeleteProject?(project)
        projectToDelete = nil
      }
      Button("Cancel", role: .cancel) {
        projectToDelete = nil
      }
    } message: { project in
      Text("\"\(project.name)\" will be permanently deleted.\n\nThis action cannot be undone.")
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
