import SwiftUI

struct ResultAnalysisView: View {
  var projectId: Project.ID?
  @Environment(AppRouter.self) private var router
  @Environment(ProjectViewModel.self) private var projectViewModel: ProjectViewModel?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var viewModel: ResultAnalysisViewModel
  @State private var captionCenter = AccessibilityCaptionCenter.shared

  init(
    projectId: Project.ID? = nil,
    project: Project? = nil,
    viewModel: ResultAnalysisViewModel? = nil
  ) {
    self.projectId = projectId
    if let viewModel {
      _viewModel = State(initialValue: viewModel)
    } else {
      _viewModel = State(initialValue: ResultAnalysisViewModel(project: project))
    }
  }

  private var isCurrentDestination: Bool {
    if case .resultAnalysis = router.currentRoute {
      return true
    }
    return false
  }

  private var leftSheetPresentedBinding: Binding<Bool> {
    Binding(
      get: {
        isCurrentDestination &&
          viewModel.isLeftSheetPresented
      },
      set: { newValue in
        viewModel.isLeftSheetPresented = newValue
      }
    )
  }

  var body: some View {
    @Bindable var viewModel = viewModel

    GeometryReader { proxy in
      let oneThirdSheetWidth = max((proxy.size.width / 3.0).rounded(), 280)

      ZStack {
        Color(.systemBackground)
          .ignoresSafeArea()

        switch viewModel.selectedTab {
        case .threeDLayer:
          // RealityKit 3D Subsurface Voxel Visualization
          ResultSubsurfaceRealityView(
            volume: viewModel.volume,
            maxSliceX: viewModel.maxSliceXIndex,
            maxSliceZ: viewModel.maxSliceZIndex,
            selectedVoxel: viewModel.selectedVoxel,
            selectedPipePosition3D: viewModel.selectedPipePosition3D,
            cameraYaw: $viewModel.cameraYaw,
            cameraPitch: $viewModel.cameraPitch,
            cameraZoom: $viewModel.cameraZoom,
            isProfilePopoverPresented: $viewModel.isProfilePopoverPresented,
            profilePopoverLocation: $viewModel.profilePopoverLocation,
            popoverTitle: viewModel.selectedCPTPointTitle,
            popoverLatitude: viewModel.selectedCPTPointLatitude,
            popoverLongitude: viewModel.selectedCPTPointLongitude,
            popoverLayers: viewModel.selectedPopoverLayers,
            onSelectVoxel: { voxel in
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                viewModel.handleVoxelSelection(voxel)
              }
            },
            onTapTopSurface: { screenPoint, hit3D, voxel in
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                viewModel.handleTopSurfaceTap(at: screenPoint, local3DPoint: hit3D, voxel: voxel)
              }
            }
          )
          .ignoresSafeArea()

        case .bearingLayer:
          // RealityKit Flat 3D Surface Depth Map ("Permukaan yang disorot dari atas")
          ResultBearingSurfaceRealityView(
            volume: viewModel.volume,
            cameraYaw: $viewModel.bearingCameraYaw,
            cameraPitch: $viewModel.bearingCameraPitch,
            cameraZoom: $viewModel.bearingCameraZoom,
            isProfilePopoverPresented: $viewModel.isProfilePopoverPresented,
            profilePopoverLocation: $viewModel.profilePopoverLocation,
            popoverTitle: viewModel.selectedCPTPointTitle,
            popoverLatitude: viewModel.selectedCPTPointLatitude,
            popoverLongitude: viewModel.selectedCPTPointLongitude,
            popoverLayers: viewModel.selectedPopoverLayers,
            onTapCPTPoint: { screenPoint, idx in
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                viewModel.handleBearingCPTPointTap(at: screenPoint, pointIndex: idx)
              }
            },
            onSelectBearingVoxel: { bearingVoxel in
              viewModel.selectedBearingVoxel = bearingVoxel
            }
          )
          .ignoresSafeArea()
        }
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
      // Bottom-Trailing: Slicing Card (3D Layer) or Depth Legend (Bearing Layer)
      .overlay(alignment: .bottomTrailing) {
        switch viewModel.selectedTab {
        case .threeDLayer:
          ResultLayerSlicingCardView(
            isExpanded: $viewModel.isSlicingCardExpanded,
            slicingXMeters: $viewModel.slicingXMeters,
            slicingYMeters: $viewModel.slicingYMeters,
            minXMeters: viewModel.minSlicingXMeters,
            maxXMeters: viewModel.maxSlicingXMeters,
            minYMeters: viewModel.minSlicingYMeters,
            maxYMeters: viewModel.maxSlicingYMeters,
            onResetView: {
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                viewModel.resetView()
              }
            }
          )
          .padding(.trailing, 20)
          .padding(.bottom, 24)
          .transition(.opacity.combined(with: .move(edge: .bottom)))

        case .bearingLayer:
          ResultBearingDepthLegendView()
            .padding(.trailing, 28)
            .padding(.bottom, 22)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
      }
      // Left Sheet sized to 1/3 of screen width
      .sheet(isPresented: leftSheetPresentedBinding) {
        Group {
          switch viewModel.selectedTab {
          case .threeDLayer:
            ResultLeftPlaceholderSheetView(
              groundConditionsSummary: viewModel.groundConditionsSummary,
              concerns: viewModel.geotechnicalConcerns,
              isSubsurfaceConditionsEmpty: viewModel.isSubsurfaceConditionsEmpty,
              isGeotechnicalConcernsEmpty: viewModel.isGeotechnicalConcernsEmpty,
              selectedConcernID: viewModel.selectedConcernID,
              predictionUncertaintyPercent: viewModel.predictionUncertaintyPercent,
              cptPointsCount: viewModel.displayedCPTPointsCount,
              onSelectConcern: { concern in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                  viewModel.selectConcern(concern)
                }
              },
              onClearHighlight: {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                  viewModel.clearHighlight()
                }
              }
            )
          case .bearingLayer:
            ResultBearingLayerSheetView(
              shallowestDepthText: viewModel.shallowestBearingDepthText,
              deepestDepthText: viewModel.deepestBearingDepthText,
              variationDepthText: viewModel.variationBearingDepthText,
              coneResistanceText: viewModel.coneResistanceCriteriaText,
              soilBehaviorIndexText: viewModel.soilBehaviorIndexCriteriaText,
              minLayerThicknessText: viewModel.minLayerThicknessCriteriaText,
              relativeUncertaintyText: viewModel.relativeUncertaintyText,
              highUncertaintyAreaPercentText: viewModel.highUncertaintyAreaPercentText,
              highUncertaintyDescription: viewModel.highUncertaintyDescription
            )
          }
        }
        .frame(width: oneThirdSheetWidth)
        .background(
          SheetWidthConfigurator(width: oneThirdSheetWidth)
        )
        .presentationPlacement(.leading)
        .presentationSizing(OneThirdScreenSheetSizing(width: oneThirdSheetWidth))
        .presentationDetents(
          [
            ResultAnalysisViewModel.collapsedSheetDetent,
            ResultAnalysisViewModel.defaultSheetDetent,
            ResultAnalysisViewModel.expandedSheetDetent,
            .large
          ],
          selection: $viewModel.selectedSheetDetent
        )
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled()
      }
    }
    .toolbar {
      ResultToolbarContent(
        selectedTab: viewModel.selectedTab,
        onSelectTab: { tab in
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            viewModel.selectTab(tab)
          }
        }
      )
    }
    .toolbarRole(.editor)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    .ignoresSafeArea(.keyboard)
    .task {
      if let projectId {
        viewModel.resolveProject(with: projectId, from: projectViewModel)
      } else if let selected = projectViewModel?.selectedProject {
        viewModel.updateProject(selected)
      }

      try? await Task.sleep(for: .milliseconds(400))
      if !Task.isCancelled, isCurrentDestination {
        viewModel.presentLeftSheetIfNeeded()
      }
    }
    .onDisappear {
      viewModel.dismissLeftSheet()
    }
  }
}

#Preview {
  NavigationStack {
    ResultAnalysisView()
  }
  .environment(AppRouter())
  .environment(ProjectViewModel())
}
