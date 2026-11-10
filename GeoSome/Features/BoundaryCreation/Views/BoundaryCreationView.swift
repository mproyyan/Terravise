import MapKit
import SwiftUI

struct BoundaryCreationView: View {
  private enum ActiveBoundarySheet: Identifiable {
    case coordinateList
    case addCoordinate
    case editCoordinate(BoundaryPoint)

    var id: String {
      switch self {
      case .coordinateList:
        "coordinateList"
      case .addCoordinate:
        "addCoordinate"
      case let .editCoordinate(point):
        "editCoordinate-\(point.id.uuidString)"
      }
    }
  }

  var editingProjectId: Project.ID?
  @Environment(AppRouter.self) private var router
  @Environment(ProjectViewModel.self) private var projectViewModel: ProjectViewModel?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var viewModel: BoundaryCreationViewModel
  @State private var captionCenter = AccessibilityCaptionCenter.shared

  init(
    editingProjectId: Project.ID? = nil,
    viewModel: BoundaryCreationViewModel? = nil
  ) {
    self.editingProjectId = editingProjectId
    _viewModel = State(initialValue: viewModel ?? BoundaryCreationViewModel())
  }

  private var isCurrentDestination: Bool {
    switch router.currentRoute {
    case .boundaryCreation, .editBoundary:
      return true
    default:
      return false
    }
  }

  private var projectNameBinding: Binding<String> {
    Binding(
      get: { viewModel.projectName },
      set: { viewModel.setProjectName($0) }
    )
  }

  private var activeSheetBinding: Binding<ActiveBoundarySheet?> {
    Binding(
      get: {
        guard isCurrentDestination, viewModel.activeSheet == .boundaryCoordinate else {
          return nil
        }
        if let editingPoint = viewModel.editingPoint {
          return .editCoordinate(editingPoint)
        }
        if viewModel.isAddCoordinateSheetPresented {
          return .addCoordinate
        }
        return .coordinateList
      },
      set: { newValue in
        switch newValue {
        case .coordinateList:
          viewModel.isAddCoordinateSheetPresented = false
          viewModel.editingPoint = nil
          viewModel.activeSheet = .boundaryCoordinate
        case .addCoordinate:
          viewModel.isAddCoordinateSheetPresented = true
        case let .editCoordinate(point):
          viewModel.editingPoint = point
        case nil:
          if viewModel.editingPoint != nil {
            viewModel.dismissEditCoordinateSheet()
            viewModel.activeSheet = nil
            Task { @MainActor in
              try? await Task.sleep(for: .milliseconds(100))
              if isCurrentDestination {
                viewModel.presentCoordinateSheet()
              }
            }
          } else if viewModel.isAddCoordinateSheetPresented {
            viewModel.dismissAddCoordinateSheet()
            viewModel.activeSheet = nil
            Task { @MainActor in
              try? await Task.sleep(for: .milliseconds(100))
              if isCurrentDestination {
                viewModel.presentCoordinateSheet()
              }
            }
          } else {
            viewModel.activeSheet = nil
          }
        }
      }
    )
  }

  var body: some View {
    @Bindable var viewModel = viewModel

    BoundaryMapContentLayer(
      cameraPosition: $viewModel.cameraPosition,
      points: viewModel.points,
      isSatelliteStyle: viewModel.isSatelliteStyle,
      onMapTap: { coordinate in
        viewModel.handleMapTap(at: coordinate)
      },
      onBeginMovePoint: {
        viewModel.beginPointDrag()
      },
      onMovePoint: { id, newCoordinate in
        viewModel.updatePointCoordinate(id: id, to: newCoordinate)
      },
      onSelectPoint: { point in
        viewModel.selectPointForEditing(point)
      },
      onDeletePoint: { id in
        viewModel.deletePoint(id: id)
      }
    )
    .overlay(alignment: .top) {
      if let caption = captionCenter.currentCaption {
        AccessibilityCaptionBannerView(
          caption: caption,
          onDismiss: { captionCenter.dismissCaption() }
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
      }
    }
    .overlay(alignment: .bottomTrailing) {
      BoundaryMapControlsView(
        isSatelliteStyle: viewModel.isSatelliteStyle,
        onToggleMapLayer: {
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            viewModel.toggleMapLayer()
          }
        },
        onFocusLocation: {
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            viewModel.focusLocation()
          }
        }
      )
      .padding(.trailing, 20)
      .padding(.bottom, 28)
    }
    .sheet(item: activeSheetBinding) { destination in
      switch destination {
      case .coordinateList:
        BoundaryCoordinateSheetView(
          isTooltipVisible: $viewModel.isTooltipVisible,
          points: viewModel.points,
          boundaryPointsText: viewModel.boundaryPointsSummaryText,
          areaPrimaryText: viewModel.areaSquareMetersText,
          areaSecondaryText: viewModel.areaHectaresText,
          onHelpTap: {
            viewModel.toggleTooltip()
          },
          onAddCoordinateTap: {
            viewModel.addCoordinate()
          },
          onSelectPoint: { point in
            viewModel.selectPointForEditing(point)
          },
          onDeletePoint: { id in
            viewModel.deletePoint(id: id)
          }
        )
        .presentationPlacement(.leading)
        .presentationDetents(
          [
            BoundaryCreationViewModel.collapsedSheetDetent,
            BoundaryCreationViewModel.defaultSheetDetent,
            BoundaryCreationViewModel.populatedSheetDetent,
            .medium,
            .large
          ],
          selection: $viewModel.selectedSheetDetent
        )
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled()

      case .addCoordinate:
        BoundaryAddCoordinateSheetView(
          coordinateText: $viewModel.coordinateInputText,
          isDiscardConfirmationPresented: $viewModel.isDiscardConfirmationPresented,
          isInvalidCoordinateAlertPresented: $viewModel.isInvalidCoordinateAlertPresented,
          canSubmit: viewModel.canSubmitCoordinate,
          onCloseTap: {
            viewModel.requestDismissAddCoordinateSheet()
          },
          onDiscardConfirm: {
            viewModel.confirmDiscardCoordinateInput()
          },
          onSubmitTap: {
            viewModel.submitCoordinate()
          }
        )
        .presentationPlacement(.leading)
        .presentationDetents(
          [
            BoundaryCreationViewModel.defaultSheetDetent,
            .medium,
            .large
          ]
        )
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .interactiveDismissDisabled(viewModel.hasUnsavedCoordinateInput)

      case let .editCoordinate(point):
        BoundaryEditCoordinateSheetView(
          pointTitle: viewModel.title(for: point),
          latitudeText: $viewModel.editLatitudeText,
          longitudeText: $viewModel.editLongitudeText,
          isDeleteConfirmationPresented: $viewModel.isDeletePointAlertPresented,
          isDiscardConfirmationPresented: $viewModel.isEditDiscardConfirmationPresented,
          isInvalidCoordinateAlertPresented: $viewModel.isEditInvalidCoordinateAlertPresented,
          canSubmit: viewModel.canSubmitEditedCoordinate,
          onCloseTap: {
            viewModel.requestDismissEditCoordinateSheet()
          },
          onDiscardConfirm: {
            viewModel.confirmDiscardEditCoordinateChanges()
          },
          onSubmitTap: {
            viewModel.submitEditedCoordinate()
          },
          onDeleteTap: {
            viewModel.requestDeleteEditingPoint()
          },
          onDeleteConfirm: {
            viewModel.confirmDeleteEditingPoint()
          }
        )
        .presentationPlacement(.leading)
        .presentationDetents(
          [
            BoundaryCreationViewModel.editSheetDetent,
            .medium,
            .large
          ]
        )
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .interactiveDismissDisabled(viewModel.hasUnsavedEditCoordinateChanges)
      }
    }
    .task {
      if let editingProjectId,
         let foundProject = projectViewModel?.projects.first(where: { $0.id == editingProjectId })
      {
        viewModel.loadExistingProject(foundProject)
      }
      try? await Task.sleep(for: .milliseconds(450))
      if !Task.isCancelled, isCurrentDestination {
        viewModel.presentCoordinateSheet()
      }
    }
    .onDisappear {
      viewModel.dismissCoordinateSheet()
    }
    .toolbar {
      BoundaryToolbarContent(
        projectName: projectNameBinding,
        canUndo: viewModel.canUndo,
        canRedo: viewModel.canRedo,
        canCreateProject: viewModel.canCreateProject,
        onBeginEditingName: {
          viewModel.beginEditingProjectName()
        },
        onFinishEditingName: {
          viewModel.finishEditingProjectName()
        },
        onResetAnchorTap: {
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            viewModel.resetAnchor()
          }
        },
        onUndoTap: {
          viewModel.undo()
        },
        onRedoTap: {
          viewModel.redo()
        },
        onCreateProjectTap: {
          guard let savedProject = viewModel.createProject() else { return }
          if editingProjectId != nil {
            projectViewModel?.updateProject(savedProject)
          } else {
            projectViewModel?.addProject(savedProject)
          }
          projectViewModel?.selectProject(savedProject)
          AccessibilityCaptionCenter.shared.announce(
            "\(editingProjectId != nil ? "Updated" : "Created") project \(savedProject.name) with \(savedProject.boundaryPoints.count) boundary points."
          )
          viewModel.dismissCoordinateSheet()
          router.replacePath(with: .projectDetail(id: savedProject.id))
        }
      )
    }
    .toolbarRole(.editor)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    .ignoresSafeArea(.keyboard)
  }
}

#Preview {
  NavigationStack {
    BoundaryCreationView()
  }
  .environment(AppRouter(initialPath: [.boundaryCreation]))
  .environment(ProjectViewModel())
}
