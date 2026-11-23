import SwiftUI

struct BoundaryToolbarContent: ToolbarContent {
  @Binding var projectName: String
  var canUndo: Bool
  var canRedo: Bool
  var canCreateProject: Bool
  var isEditingExistingProject: Bool
  var onBeginEditingName: (() -> Void)?
  var onFinishEditingName: (() -> Void)?
  var onResetAnchorTap: (() -> Void)?
  var onUndoTap: (() -> Void)?
  var onRedoTap: (() -> Void)?
  var onCreateProjectTap: (() -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
  @ScaledMetric(relativeTo: .subheadline) private var controlHeight: CGFloat = 36

  init(
    projectName: Binding<String>,
    canUndo: Bool = false,
    canRedo: Bool = false,
    canCreateProject: Bool = true,
    isEditingExistingProject: Bool = false,
    onBeginEditingName: (() -> Void)? = nil,
    onFinishEditingName: (() -> Void)? = nil,
    onResetAnchorTap: (() -> Void)? = nil,
    onUndoTap: (() -> Void)? = nil,
    onRedoTap: (() -> Void)? = nil,
    onCreateProjectTap: (() -> Void)? = nil
  ) {
    _projectName = projectName
    self.canUndo = canUndo
    self.canRedo = canRedo
    self.canCreateProject = canCreateProject
    self.isEditingExistingProject = isEditingExistingProject
    self.onBeginEditingName = onBeginEditingName
    self.onFinishEditingName = onFinishEditingName
    self.onResetAnchorTap = onResetAnchorTap
    self.onUndoTap = onUndoTap
    self.onRedoTap = onRedoTap
    self.onCreateProjectTap = onCreateProjectTap
  }

  private var disabledOpacity: Double {
    contrast == .increased ? 0.55 : 0.4
  }

  var body: some ToolbarContent {
    // Leading: Editable Project Name (next to native back button)
    ToolbarItem(placement: .topBarLeading) {
      BoundaryProjectNameView(
        projectName: $projectName,
        onBeginEditing: onBeginEditingName,
        onFinishEditing: onFinishEditingName
      )
    }
    .sharedBackgroundVisibility(.hidden)

    // Trailing: Reset Anchor, Undo, Redo, Create Project
    ToolbarItemGroup(placement: .topBarTrailing) {
      HStack(spacing: 8) {
        // Reset Anchor
        Button(action: {
          onResetAnchorTap?()
        }) {
          HStack(spacing: 4) {
            if differentiateWithoutColor {
              Image(systemName: "arrow.counterclockwise")
                .font(.caption.weight(.semibold))
            }
            Text("Reset Anchor")
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
        .accessibilityLabel("Reset Anchor")
        .accessibilityHint("Clears all boundary points from the map")
        .accessibilityInputLabels(["Reset Anchor", "Reset", "Clear Points"])

        // Undo
        Button(action: {
          onUndoTap?()
        }) {
          Image(systemName: "arrow.uturn.backward")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.primary.opacity(canUndo ? 1.0 : disabledOpacity))
            .frame(minWidth: controlHeight, minHeight: controlHeight)
            .clipShape(Circle())
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
        }
        .frame(minWidth: 44, minHeight: 44)
        .disabled(!canUndo)
        .buttonStyle(.glass(.regular))
        .buttonBorderShape(.automatic)
        .accessibilityLabel("Undo")
        .accessibilityHint("Undoes the last change")

        // Redo
        Button(action: {
          onRedoTap?()
        }) {
          Image(systemName: "arrow.uturn.forward")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.primary.opacity(canRedo ? 1.0 : disabledOpacity))
            .frame(minWidth: controlHeight, minHeight: controlHeight)
            .clipShape(Circle())
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
        }
        .frame(minWidth: 44, minHeight: 44)
        .disabled(!canRedo)
        .buttonStyle(.glass(.regular))
        .buttonBorderShape(.automatic)
        .accessibilityLabel("Redo")
        .accessibilityHint("Redoes the previously undone change")

        // Create Project
        Button(action: {
          if canCreateProject {
            onCreateProjectTap?()
          }
        }) {
          HStack(spacing: 5) {
            if canCreateProject {
              Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.bold))
            } else if differentiateWithoutColor {
              Image(systemName: "exclamationmark.circle")
                .font(.caption.weight(.semibold))
            }
            Text(isEditingExistingProject ? "Save Changes" : "Create Project")
              .font(.subheadline.weight(.semibold))
          }
          .foregroundStyle(canCreateProject ? Color.white : Color.primary.opacity(disabledOpacity))
          .padding(.horizontal, 16)
          .frame(minHeight: controlHeight)
          .clipShape(Capsule())
          .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 1)
        }
        .frame(minWidth: 44, minHeight: 44)
        .disabled(!canCreateProject)
        .buttonStyle(.glass(canCreateProject ? .regular.tint(.blue) : .regular))
        .buttonBorderShape(.automatic)
        .accessibilityLabel(isEditingExistingProject ? "Save Changes" : "Create Project")
        .accessibilityValue(canCreateProject ? "Ready" : "Requires at least 3 boundary points")
        .accessibilityHint(
          canCreateProject
            ? (isEditingExistingProject ? "Saves the changes to the project boundary" : "Saves the project with the current boundary points")
            : "Add at least 3 boundary points to enable saving"
        )
        .accessibilityInputLabels(
          isEditingExistingProject
            ? ["Save Changes", "Save", "Save Project"]
            : ["Create Project", "Create", "Save Project"]
        )
      }
    }
    .sharedBackgroundVisibility(.hidden)
  }
}

struct BoundaryProjectNameView: View {
  @Binding var projectName: String
  var onBeginEditing: (() -> Void)?
  var onFinishEditing: (() -> Void)?
  @State private var isEditing: Bool = false
  @FocusState private var isFocused: Bool
  @AccessibilityFocusState private var isNameButtonAccessibilityFocused: Bool

  init(
    projectName: Binding<String>,
    onBeginEditing: (() -> Void)? = nil,
    onFinishEditing: (() -> Void)? = nil
  ) {
    _projectName = projectName
    self.onBeginEditing = onBeginEditing
    self.onFinishEditing = onFinishEditing
  }

  private var displayProjectName: String {
    projectName.isEmpty ? "Project name" : projectName
  }

  var body: some View {
    HStack(spacing: 6) {
      if isEditing {
        TextField("Project name", text: $projectName)
          .font(.headline)
          .foregroundStyle(Color.primary)
          .focused($isFocused)
          .onSubmit {
            isEditing = false
            onFinishEditing?()
            isNameButtonAccessibilityFocused = true
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .frame(minWidth: 140, maxWidth: 240)
          .accessibilityLabel("Project name")

        Button(action: {
          isEditing = false
          onFinishEditing?()
          isNameButtonAccessibilityFocused = true
        }) {
          Image(systemName: "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(Color.blue)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Save project name")
        .accessibilityHint("Finishes editing the project name")
      } else {
        Button(action: {
          onBeginEditing?()
          isEditing = true
          isFocused = true
        }) {
          HStack(spacing: 6) {
            Text(displayProjectName)
              .font(.headline)
              .foregroundStyle(Color.primary)

            Image(systemName: "pencil")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Color.primary)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .fixedSize()
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
        .frame(minHeight: 44)
        .accessibilityFocused($isNameButtonAccessibilityFocused)
        .accessibilityLabel("Project name")
        .accessibilityValue(displayProjectName)
        .accessibilityHint("Edits the project name")
        .accessibilityInputLabels(["Project name", "Edit project name", displayProjectName])
      }
    }
    .onChange(of: isFocused) { _, focused in
      if !focused, isEditing {
        isEditing = false
        onFinishEditing?()
      }
    }
  }
}
