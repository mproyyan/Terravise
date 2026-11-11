import MapKit
import SwiftUI

struct CPTRecommendationView: View {
  var projectId: Project.ID?
  @Environment(AppRouter.self) private var router
  @Environment(ProjectViewModel.self) private var projectViewModel: ProjectViewModel?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var viewModel: CPTRecommendationViewModel
  @State private var captionCenter = AccessibilityCaptionCenter.shared

  init(
    projectId: Project.ID? = nil,
    project: Project? = nil,
    viewModel: CPTRecommendationViewModel? = nil
  ) {
    self.projectId = projectId
    if let viewModel {
      _viewModel = State(initialValue: viewModel)
    } else {
      _viewModel = State(initialValue: CPTRecommendationViewModel(project: project))
    }
  }

  private var isCurrentDestination: Bool {
    if case .projectDetail = router.currentRoute {
      return true
    }
    return false
  }

  private var activeSheetBinding: Binding<ActiveCPTSheet?> {
    Binding(
      get: {
        guard isCurrentDestination, viewModel.isSheetPresented else { return nil }
        if viewModel.isUploadSheetPresented {
          return .uploadData
        }
        if viewModel.isCPTListPresented {
          return .cptDataList
        }
        return viewModel.hasUploadedCPTData ? .recommendedPoint : .emptyState
      },
      set: { newValue in
        switch newValue {
        case .emptyState:
          viewModel.isUploadSheetPresented = false
          viewModel.isCPTListPresented = false
          viewModel.isSheetPresented = true
        case .uploadData:
          viewModel.isUploadSheetPresented = true
          viewModel.isCPTListPresented = false
          viewModel.isSheetPresented = true
        case .recommendedPoint:
          viewModel.isUploadSheetPresented = false
          viewModel.isCPTListPresented = false
          viewModel.isSheetPresented = true
        case .cptDataList:
          viewModel.isUploadSheetPresented = false
          viewModel.isCPTListPresented = true
          viewModel.isSheetPresented = true
        case nil:
          if viewModel.isUploadSheetPresented || viewModel.isCPTListPresented {
            viewModel.isUploadSheetPresented = false
            viewModel.isCPTListPresented = false
            viewModel.isSheetPresented = false
            Task { @MainActor in
              try? await Task.sleep(for: .milliseconds(100))
              if isCurrentDestination {
                viewModel.presentInitialSheet()
              }
            }
          } else {
            viewModel.isSheetPresented = false
          }
        }
      }
    )
  }

  var body: some View {
    @Bindable var viewModel = viewModel

    ZStack {
      // Fullscreen Map Content Layer with Boundary + Uploaded CPT Points + Recommended Point Annotation
      CPTMapContentLayer(
        cameraPosition: $viewModel.cameraPosition,
        coordinates: viewModel.coordinates,
        isSatelliteStyle: viewModel.isSatelliteStyle,
        recommendedCoordinate: viewModel.recommendedCoordinateOnMap,
        cptPoints: viewModel.cptPoints,
        pendingUploadCoordinate: viewModel.pendingUploadCoordinate,
        onMapTap: { coordinate in
          viewModel.handleMapTap(at: coordinate)
        }
      )
      .ignoresSafeArea()
    }
    // Top Caption Banner for Accessibility
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
    // Bottom-Trailing: Map Controls (Layer toggle & Boundary focus)
    .overlay(alignment: .bottomTrailing) {
      CPTMapControlsView(
        isSatelliteStyle: viewModel.isSatelliteStyle,
        onToggleMapLayer: {
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            viewModel.toggleMapLayer()
          }
        },
        onFocusBoundary: {
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            viewModel.focusBoundary()
          }
        }
      )
      .padding(.trailing, 20)
      .padding(.bottom, 28)
    }
    // Native Sheet with .presentationPlacement(.leading)
    .sheet(item: activeSheetBinding) { destination in
      switch destination {
      case .emptyState:
        CPTEmptyStateSheetView(
          onUploadTap: {
            viewModel.uploadCPTData()
          }
        )
        .presentationPlacement(.leading)
        .presentationDetents(
          [
            CPTRecommendationViewModel.collapsedSheetDetent,
            CPTRecommendationViewModel.defaultSheetDetent,
            CPTRecommendationViewModel.populatedSheetDetent,
            .medium,
            .large
          ],
          selection: $viewModel.selectedSheetDetent
        )
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled()

      case .recommendedPoint:
        CPTRecommendedPointSheetView(
          recommendation: viewModel.recommendation,
          cptPointsCount: max(viewModel.cptPoints.count, 1),
          onUploadTap: {
            viewModel.uploadCPTData()
          },
          onSeeSupportingDataTap: {
            viewModel.seeSupportingData()
          },
          onCPTDataListTap: {
            viewModel.openCPTDataList()
          }
        )
        .presentationPlacement(.leading)
        .presentationDetents(
          [
            CPTRecommendationViewModel.collapsedSheetDetent,
            CPTRecommendationViewModel.populatedSheetDetent,
            CPTRecommendationViewModel.recommendationSheetDetent,
            .large
          ],
          selection: $viewModel.selectedSheetDetent
        )
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled()

      case .uploadData:
        CPTUploadDataSheetView(
          selectedCPTType: $viewModel.selectedCPTType,
          coordinatesText: $viewModel.uploadCoordinatesText,
          uploadedFile: $viewModel.uploadedCPTFile,
          parsedRows: $viewModel.uploadParsedRows,
          onCloseTap: {
            viewModel.dismissUploadSheet()
          },
          onSubmitTap: {
            viewModel.submitCPTUpload()
          }
        )
        .presentationPlacement(.leading)
        .presentationDetents(
          [
            .medium,
            CPTRecommendationViewModel.uploadSheetDetent,
            .large
          ],
          selection: $viewModel.selectedSheetDetent
        )
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .presentationContentInteraction(.scrolls)

      case .cptDataList:
        CPTDataListSheetView(
          points: viewModel.cptPoints,
          onCloseTap: {
            viewModel.dismissCPTDataList()
          },
          onDeletePoint: { id in
            viewModel.deleteCPTPoint(id: id)
          }
        )
        .presentationPlacement(.leading)
        .presentationDetents(
          [
            CPTRecommendationViewModel.cptDataListSheetDetent,
            .large
          ]
        )
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .presentationContentInteraction(.scrolls)
      }
    }
    .toolbar {
      CPTRecommendationToolbarContent(
        projectName: viewModel.project.name,
        onEditAreaTap: {
          viewModel.editArea()
          viewModel.dismissSheet()
          router.navigate(to: .editBoundary(id: viewModel.project.id))
        },
        onViewAnalysis3DTap: {
          viewModel.viewAnalysis3D()
        }
      )
    }
    .toolbarRole(.editor)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    .ignoresSafeArea(.keyboard)
    .task {
      viewModel.projectViewModel = projectViewModel
      if let projectId {
        viewModel.resolveProject(with: projectId, from: projectViewModel)
      } else if let selected = projectViewModel?.selectedProject {
        viewModel.updateProject(selected)
      }

      try? await Task.sleep(for: .milliseconds(450))
      if !Task.isCancelled, isCurrentDestination {
        viewModel.presentInitialSheet()
      }
    }
    .onDisappear {
      viewModel.dismissSheet()
    }
  }
}

#Preview {
  NavigationStack {
    CPTRecommendationView()
  }
  .environment(AppRouter())
  .environment(ProjectViewModel())
}
