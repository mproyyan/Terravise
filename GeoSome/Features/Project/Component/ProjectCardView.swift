import Foundation
import MapKit
import SwiftUI

struct ProjectCardView: View {
  let project: Project
  let formattedLastEdited: String
  private let onSelect: (() -> Void)?
  private let onRename: ((String) -> Void)?
  private let onDelete: (() -> Void)?

  @State private var activePrompt: ProjectCardPrompt?
  @State private var isPromptPresented = false
  @State private var renameDraft = ""

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
  @ScaledMetric(relativeTo: .body) private var thumbnailHeight: CGFloat = 88

  init(
    project: Project,
    formattedLastEdited: String? = nil,
    onSelect: (() -> Void)? = nil,
    onRename: ((String) -> Void)? = nil,
    onDelete: (() -> Void)? = nil
  ) {
    self.project = project
    self.formattedLastEdited = formattedLastEdited ?? ProjectViewModel.formatLastEdited(project.lastEdited)
    self.onSelect = onSelect
    self.onRename = onRename
    self.onDelete = onDelete
  }

  private var pointCountSummary: String {
    let count = project.boundaryPoints.count
    return "\(count) \(count == 1 ? "point" : "points")"
  }

  var body: some View {
    Button(action: {
      onSelect?()
    }) {
      VStack(alignment: .leading, spacing: 0) {
        thumbnailView
        detailsView
      }
      .frame(maxWidth: .infinity)
      .frame(minHeight: 144, alignment: .top)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(
            Color.primary.opacity(contrast == .increased ? 0.4 : 0.12),
            lineWidth: contrast == .increased ? 1.5 : 1
          )
      )
      .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(project.name)
    .accessibilityValue("\(pointCountSummary), \(formattedLastEdited)")
    .accessibilityHint("Opens this project")
    .accessibilityInputLabels([project.name, "Open \(project.name)"])
    .contextMenu {
      Button(action: presentRenamePrompt) {
        Label("Rename", systemImage: "pencil")
      }

      Button(role: .destructive, action: presentDeletePrompt) {
        Label("Delete Project", systemImage: "trash")
      }
    }
    .alert(activePrompt?.title ?? "Project", isPresented: $isPromptPresented) {
      switch activePrompt {
      case .rename:
        TextField("Project Name", text: $renameDraft)
          .textInputAutocapitalization(.words)

        Button("Cancel", role: .cancel, action: dismissPrompt)
        Button("Rename", role: .confirm, action: confirmRename)
          .keyboardShortcut(.defaultAction)
          .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)


      case .delete:
        Button("Cancel", role: .cancel, action: dismissPrompt)
        Button("Delete", role: .destructive, action: confirmDelete)

      case nil:
        Button("OK", role: .cancel, action: dismissPrompt)
      }
    } message: {
      Text(activePrompt?.message ?? "")
    }
  }

  private func presentRenamePrompt() {
    renameDraft = project.name
    activePrompt = .rename
    isPromptPresented = true
  }

  private func presentDeletePrompt() {
    activePrompt = .delete
    isPromptPresented = true
  }

  private func confirmRename() {
    onRename?(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines))
    dismissPrompt()
  }

  private func confirmDelete() {
    onDelete?()
    dismissPrompt()
  }

  private func dismissPrompt() {
    isPromptPresented = false
    activePrompt = nil
  }

  private enum ProjectCardPrompt {
    case rename
    case delete

    var title: String {
      switch self {
      case .rename: "Rename Project"
      case .delete: "Delete Project?"
      }
    }

    var message: String {
      switch self {
      case .rename: "Enter a new name for your project."
      case .delete: "This action cannot be undone. All saved investigation data for this project will be permanently deleted."
      }
    }
  }

  private var thumbnailView: some View {
    Map(
      position: .constant(.region(project.boundaryRegion)),
      interactionModes: []
    ) {
      if project.boundaryCoordinates.count >= 3 {
        MapPolygon(coordinates: project.boundaryCoordinates)
          .foregroundStyle(.blue.opacity(contrast == .increased ? 0.35 : 0.22))
          .stroke(.blue, lineWidth: contrast == .increased ? 3 : 2)
      } else if project.boundaryCoordinates.count == 2 {
        MapPolyline(coordinates: project.boundaryCoordinates)
          .stroke(
            .blue,
            style: StrokeStyle(
              lineWidth: contrast == .increased ? 3 : 2,
              lineCap: .round,
              lineJoin: .round,
              dash: [6, 4]
            )
          )
      }
    }
    .mapStyle(.standard(elevation: .realistic))
    .mapControlVisibility(.hidden)
    .allowsHitTesting(false)
    .frame(height: thumbnailHeight)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .padding(4)
    .accessibilityHidden(true)
  }

  private var detailsView: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(project.name)
        .font(.footnote.weight(.bold))
        .foregroundStyle(.primary)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        .fixedSize(horizontal: false, vertical: true)

      Text(formattedLastEdited)
        .font(.caption2)
        .foregroundStyle(contrast == .increased ? .primary : .secondary)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        .fixedSize(horizontal: false, vertical: true)

      if differentiateWithoutColor {
        Label(pointCountSummary, systemImage: "mappin.and.ellipse")
          .font(.caption2.weight(.medium))
          .foregroundStyle(contrast == .increased ? .primary : .secondary)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
  }
}

#Preview {
  ProjectCardView(
    project: Project(
      name: "Project name",
      boundaryPoints: [
        BoundaryPoint(latitude: -6.2402, longitude: 106.8295),
        BoundaryPoint(latitude: -6.2398, longitude: 106.8328),
        BoundaryPoint(latitude: -6.2426, longitude: 106.8334)
      ]
    )
  )
  .padding()
}
