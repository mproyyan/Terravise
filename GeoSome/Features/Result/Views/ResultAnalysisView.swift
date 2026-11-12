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
          viewModel.selectedTab == .threeDLayer &&
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
            cameraYaw: $viewModel.cameraYaw,
            cameraPitch: $viewModel.cameraPitch,
            cameraZoom: $viewModel.cameraZoom,
            onSelectVoxel: { voxel in
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                viewModel.handleVoxelSelection(voxel)
              }
            }
          )
          .ignoresSafeArea()

        case .bearingLayer:
          // Intentionally left empty as requested when switching to Bearing Layer
          Color(.systemBackground)
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
      // Bottom-Trailing: Layer & Slicing Sheet/Card (Map Legend omitted as requested)
      .overlay(alignment: .bottomTrailing) {
        if viewModel.selectedTab == .threeDLayer {
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
        }
      }
      // Left Sheet: Subsurface Conditions sized to 1/3 of screen width
      .sheet(isPresented: leftSheetPresentedBinding) {
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
