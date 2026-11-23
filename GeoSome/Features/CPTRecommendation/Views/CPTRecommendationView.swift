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

  private var sheetPresentedBinding: Binding<Bool> {
    Binding(
      get: {
        isCurrentDestination && viewModel.isSheetPresented
      },
      set: { newValue in
        if !newValue {
          if viewModel.isUploadSheetPresented {
            viewModel.dismissUploadSheet()
          } else if viewModel.isCPTListPresented {
            viewModel.dismissCPTDataList()
          } else if viewModel.isInitialSetupPresented {
            viewModel.dismissInitialSetupSheet()
          } else {
            viewModel.isSheetPresented = false
          }
        } else {
          viewModel.isSheetPresented = true
        }
      }
    )
  }

  private var activeSheetDestination: ActiveCPTSheet {
    if viewModel.isUploadSheetPresented {
      return .uploadData
    }
    if viewModel.isCPTListPresented {
      return .cptDataList
    }
    if !viewModel.hasUploadedCPTData && viewModel.isInitialSetupPresented {
      return .initialSetup
    }
    return viewModel.hasUploadedCPTData ? .recommendedPoint : .emptyState
  }

  private var isPracticalStop: Bool {
    CPTRecommendedPointSheetView.isStopped(viewModel.recommendation)
  }

  // Map only the recommended STOP presentation; existing upload/list detents stay intact.
  private var activeSheetDetentBinding: Binding<PresentationDetent> {
    Binding(
      get: {
        if activeSheetDestination == .recommendedPoint, isPracticalStop,
           viewModel.selectedSheetDetent == CPTRecommendationViewModel.sufficientSheetDetent {
          return CPTRecommendedPointSheetView.stopSheetDetent
        }
        return viewModel.selectedSheetDetent
      },
      set: { detent in
        viewModel.selectedSheetDetent = detent == CPTRecommendedPointSheetView.stopSheetDetent
          ? CPTRecommendationViewModel.sufficientSheetDetent : detent
      }
    )
  }

  private var activeSheetDetents: Set<PresentationDetent> {
    switch activeSheetDestination {
    case .emptyState:
      return [
        CPTRecommendationViewModel.collapsedSheetDetent,
        CPTRecommendationViewModel.defaultSheetDetent,
        viewModel.recommendation.isSufficient
          ? CPTRecommendationViewModel.sufficientSheetDetent
          : CPTRecommendationViewModel.populatedSheetDetent,
        .medium,
        .large
      ]
    case .initialSetup:
      return [
        CPTRecommendationViewModel.cptDataListSheetDetent,
        .large
      ]
    case .recommendedPoint:
      return [
        CPTRecommendationViewModel.collapsedSheetDetent,
        CPTRecommendationViewModel.populatedSheetDetent,
        isPracticalStop ? CPTRecommendedPointSheetView.stopSheetDetent : CPTRecommendationViewModel.sufficientSheetDetent,
        CPTRecommendationViewModel.recommendationSheetDetent,
        .large
      ]
    case .uploadData:
      return [
        .medium,
        CPTRecommendationViewModel.uploadSheetDetent,
        .large
      ]
    case .cptDataList:
      return [
        CPTRecommendationViewModel.cptDataListSheetDetent,
        .large
      ]
    }
  }

  private var isInteractiveSheetDismissDisabled: Bool {
    switch activeSheetDestination {
    case .emptyState, .recommendedPoint:
      return true
    case .initialSetup, .uploadData, .cptDataList:
      return false
    }
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
    .sheet(isPresented: sheetPresentedBinding) {
      Group {
        switch activeSheetDestination {
        case .emptyState:
          CPTEmptyStateSheetView(
            onUploadTap: {
              viewModel.presentInitialSetupSheet()
            }
          )

        case .initialSetup:
          CPTInitialSetupSheetView(
            selectedCPTType: $viewModel.selectedCPTType,
            points: viewModel.cptPoints,
            equipmentParameters: $viewModel.uploadEquipmentParameters,
            onCloseTap: {
              viewModel.dismissInitialSetupSheet()
            },
            onConfirmTap: {
              viewModel.finalizeInitialCPTSetup()
            },
            onAddCPTTap: {
              viewModel.presentUploadSheet()
            },
            onDeletePoint: { id in
              viewModel.deleteInitialCPTPoint(id: id)
            }
          )

        case .recommendedPoint:
          CPTRecommendedPointSheetView(
            recommendation: viewModel.recommendation,
            cptPointsCount: viewModel.cptPoints.count,
            onUploadTap: {
              viewModel.uploadCPTData()
            },
            onCPTDataListTap: {
              viewModel.openCPTDataList()
            }
          )

        case .uploadData:
          CPTUploadDataSheetView(
            selectedCPTType: $viewModel.selectedCPTType,
            zoneText: $viewModel.uploadZoneText,
            eastingText: $viewModel.uploadEastingText,
            northingText: $viewModel.uploadNorthingText,
            uploadedFile: $viewModel.uploadedCPTFile,
            parsedRows: $viewModel.uploadParsedRows,
            validationError: $viewModel.uploadValidationError,
            equipmentParameters: $viewModel.uploadEquipmentParameters,
            showCPTTypeSelection: viewModel.hasUploadedCPTData,
            onCloseTap: {
              viewModel.dismissUploadSheet()
            },
            onSubmitTap: {
              viewModel.submitCPTUpload()
            }
          )

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
        }
      }
      .presentationPlacement(.leading)
      .presentationDetents(
        activeSheetDetents,
        selection: activeSheetDetentBinding
      )
      .presentationDragIndicator(.visible)
      .presentationBackgroundInteraction(.enabled)
      .presentationContentInteraction(.scrolls)
      .interactiveDismissDisabled(isInteractiveSheetDismissDisabled)
    }
    .toolbar {
      CPTRecommendationToolbarContent(
        projectName: viewModel.project.name,
        isAnalysis3DEnabled: viewModel.hasUploadedCPTData && !viewModel.cptPoints.isEmpty,
        onEditAreaTap: {
          viewModel.editArea()
          viewModel.dismissSheet()
          router.navigate(to: .editBoundary(id: viewModel.project.id))
        },
        onViewAnalysis3DTap: {
          viewModel.viewAnalysis3D()
          viewModel.dismissSheet()
          router.navigate(to: .resultAnalysis(id: viewModel.project.id))
        }
      )
    }
    .toolbarRole(.editor)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    .ignoresSafeArea(.keyboard)
    .task {
      viewModel.projectViewModel = projectViewModel
      // Allow the previous centered HomePage sheet dismissal and NavigationStack push
      // transition to start before running synchronous CoreML pipeline inference.
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }

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
