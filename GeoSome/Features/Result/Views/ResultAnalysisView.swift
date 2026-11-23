import SwiftUI

struct ResultAnalysisView: View {
  var projectId: Project.ID?
  @Environment(AppRouter.self) private var router
  @Environment(ProjectViewModel.self) private var projectViewModel: ProjectViewModel?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast

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
            isHardSoilVisible: viewModel.isHardSoilVisible,
            // selectedConcernID: viewModel.selectedConcernID,
            // isolatedVoxels: viewModel.activeConcernVoxels,
            cameraController: viewModel.cameraController,
            cameraYaw: $viewModel.cameraYaw,
            cameraPitch: $viewModel.cameraPitch,
            cameraZoom: $viewModel.cameraZoom,
            isProfilePopoverPresented: $viewModel.isProfilePopoverPresented,
            profilePopoverLocation: $viewModel.profilePopoverLocation,
            isSideLayerPopoverPresented: $viewModel.isSideLayerPopoverPresented,
            sideLayerPopoverLocation: $viewModel.sideLayerPopoverLocation,
            selectedSideSoilType: viewModel.selectedSideSoilType,
            popoverTitle: viewModel.selectedCPTPointTitle,
            popoverEasting: viewModel.selectedCPTPointEasting,
            popoverNorthing: viewModel.selectedCPTPointNorthing,
            popoverZone: viewModel.selectedCPTPointZone,
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
            },
            onTapSideLayer: { screenPoint, voxel in
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                viewModel.handleSideLayerTap(at: screenPoint, voxel: voxel)
              }
            }
          )
          .ignoresSafeArea()

        case .bearingLayer:
          if viewModel.hasBearingLayer {
            // RealityKit Flat 3D Surface Depth Map ("Permukaan yang disorot dari atas")
            ResultBearingSurfaceRealityView(
              volume: viewModel.volume,
              bearingOutput: viewModel.bearingRuleOutput,
              bearingRevision: viewModel.bearingRenderRevision,
              measuredCPTCount: viewModel.project.cptPoints.count,
              selectedCell: viewModel.selectedBearingCell,
              isMapOverlayVisible: viewModel.isBearingMapOverlayVisible,
              cameraController: viewModel.bearingCameraController,
              cameraYaw: $viewModel.bearingCameraYaw,
              cameraPitch: $viewModel.bearingCameraPitch,
              cameraZoom: $viewModel.bearingCameraZoom,
              isBearingPopoverPresented: $viewModel.isBearingPopoverPresented,
              bearingPopoverLocation: $viewModel.bearingPopoverLocation,
              bearingPopoverTitle: viewModel.selectedBearingTitle,
              bearingPopoverDepthText: viewModel.selectedBearingDepthText,
              bearingPopoverNorthingText: viewModel.selectedBearingNorthingText,
              bearingPopoverEastingText: viewModel.selectedBearingEastingText,
              isBearingCompared: viewModel.isBearingCompared,
              comparedPoints: viewModel.comparedBearingPoints,
              onAddToCompare: {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                  viewModel.addCurrentBearingToCompare()
                }
              },
              onTapBearingSurface: { screenPoint, voxel, xGrid, zGrid in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                  viewModel.handleBearingLayerTap(at: screenPoint, voxel: voxel, gridX: xGrid, gridZ: zGrid)
                }
              },
              onSelectBearingVoxel: { bearingVoxel in
                viewModel.selectedBearingVoxel = bearingVoxel
              }
            )
            .ignoresSafeArea()
            .transition(reduceMotion ? .opacity : .opacity)
          }
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
      // Top-Trailing: Depth Legend (Bearing Layer)
      .overlay(alignment: .topTrailing) {
        if viewModel.selectedTab == .bearingLayer && viewModel.hasBearingLayer {
          ResultBearingDepthLegendView(
            shallowestLimitText: viewModel.shallowestBearingDepthText,
            deepestLimitText: viewModel.deepestBearingDepthText,
            shallowestDepthM: viewModel.bearingRuleOutput?.summary.shallowestTopDepthM,
            deepestDepthM: viewModel.bearingRuleOutput?.summary.deepestBottomDepthM,
            activeDepthM: viewModel.selectedBearingTopDepthM
          )
          .padding(.trailing, 20)
          .padding(.top, 16)
          .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        }
      }
      // Center: Empty State Card when No Bearing Layer Meets Criteria
      .overlay(alignment: .center) {
        if viewModel.selectedTab == .bearingLayer && !viewModel.hasBearingLayer {
          noBearingLayerCard
            .transition(reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity))
        }
      }
      // Bottom-Trailing: Slicing Card (3D Layer) or Criteria Card (Bearing Layer)
      .overlay(alignment: .bottomTrailing) {
        let maxFloatingCardHeight = max(proxy.size.height - proxy.safeAreaInsets.top - 52, 280)

        switch viewModel.selectedTab {
        case .threeDLayer:
          ResultLayerSlicingCardView(
            cardWidth: oneThirdSheetWidth,
            maxCardHeight: maxFloatingCardHeight,
            isExpanded: $viewModel.isSlicingCardExpanded,
            isHardSoilVisible: $viewModel.isHardSoilVisible,
            volume: viewModel.volume,
            boundaryCoordinates: viewModel.activeBoundaryCoordinates,
            cptPoints: viewModel.project.cptPoints,
            cameraController: viewModel.cameraController,
            virtualCPTPosition3D: viewModel.selectedPipePosition3D,
            onTapCreateVirtualCPT: {
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                viewModel.createVirtualCPTAtMinimapCenter()
              }
            },
            // concerns: viewModel.geotechnicalConcerns,
            // isGeotechnicalConcernsEmpty: viewModel.isGeotechnicalConcernsEmpty,
            // selectedConcernID: viewModel.selectedConcernID,
            // onSelectConcern: { concern in
            //   withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            //     viewModel.selectConcern(concern)
            //   }
            // },
            slicingXMeters: $viewModel.slicingXMeters,
            slicingYMeters: $viewModel.slicingYMeters,
            minXMeters: viewModel.minSlicingXMeters,
            maxXMeters: viewModel.maxSlicingXMeters,
            minYMeters: viewModel.minSlicingYMeters,
            maxYMeters: viewModel.maxSlicingYMeters,
            maxSliceX: viewModel.maxSliceXIndex,
            maxSliceZ: viewModel.maxSliceZIndex,
            onResetView: {
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                viewModel.resetView()
              }
            }
          )
          .padding(.top, 16)
          .padding(.trailing, 20)
          .padding(.bottom, 20)
          .transition(.opacity.combined(with: .move(edge: .bottom)))

        case .bearingLayer:
          ResultBearingCriteriaCardView(
            cardWidth: oneThirdSheetWidth,
            isExpanded: $viewModel.isBearingCriteriaCardExpanded,
            isMapOverlayVisible: $viewModel.isBearingMapOverlayVisible,
            coneResistanceQc: $viewModel.coneResistanceQc,
            soilBehaviorIndexIc: $viewModel.soilBehaviorIndexIc,
            selectedIcText: viewModel.bearingIcThresholdText,
            minLayerThickness: $viewModel.minLayerThickness,
            onResetCriteria: {
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                viewModel.resetBearingCriteria()
              }
            }
          )
          .padding(.trailing, 20)
          .padding(.bottom, 20)
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
              // concerns: viewModel.geotechnicalConcerns,
              isSubsurfaceConditionsEmpty: viewModel.isSubsurfaceConditionsEmpty,
              // isGeotechnicalConcernsEmpty: viewModel.isGeotechnicalConcernsEmpty,
              legendItems: viewModel.activeLegendItems,
              predictionUncertaintyPercent: viewModel.predictionUncertaintyPercent,
              cptPointsCount: viewModel.displayedCPTPointsCount,
              isCollapsed: viewModel.isLeftSheetCollapsed
            )
          case .bearingLayer:
            if viewModel.isCompareDataSheetActive {
              ResultBearingCompareDataSheetView(
                items: viewModel.comparedBearingPoints,
                onRemoveItem: { item in
                  withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    viewModel.removeComparedPoint(item)
                  }
                },
                onClose: {
                  withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    viewModel.exitCompareMode()
                  }
                }
              )
            } else {
              ResultBearingLayerSheetView(
                shallowestDepthText: viewModel.shallowestBearingDepthText,
                deepestDepthText: viewModel.deepestBearingDepthText,
                variationDepthText: viewModel.variationBearingDepthText,
                // Use the current Bearing evaluation, not depth error or CPT coverage.
                relativeUncertaintyText: viewModel.bearingUncertaintyExperimentalInferenceReady
                  ? viewModel.relativeUncertaintyText : nil,
                highUncertaintyAreaPercentText: viewModel.highUncertaintyAreaPercentText,
                highUncertaintyDescription: nil,
                hasBearingLayer: viewModel.hasBearingLayer,
                isCollapsed: viewModel.isLeftSheetCollapsed
              )
            }
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
        .presentationContentInteraction(viewModel.isLeftSheetCollapsed ? .resizes : .scrolls)
        .interactiveDismissDisabled()
        .onTapGesture {
          if viewModel.isLeftSheetCollapsed {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
              viewModel.selectedSheetDetent = ResultAnalysisViewModel.defaultSheetDetent
            }
          }
        }
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
    .onChange(of: viewModel.coneResistanceQc) { _, _ in viewModel.reevaluateBearingRule() }
    .onChange(of: viewModel.soilBehaviorIndexIc) { _, _ in viewModel.reevaluateBearingRule() }
    .onChange(of: viewModel.minLayerThickness) { _, _ in viewModel.reevaluateBearingRule() }
    .onChange(of: projectViewModel?.projects.first(where: { $0.id == (projectId ?? viewModel.project.id) })) { _, updated in
      guard let updated, updated != viewModel.project else { return }
      viewModel.updateProject(updated)
    }
    .onDisappear {
      viewModel.dismissLeftSheet()
    }
  }

  // MARK: - Empty State Card

  @ViewBuilder
  private var noBearingLayerCard: some View {
    VStack(spacing: 14) {
      Image(systemName: "square.3.layers.3d.slash")
        .font(.system(size: 38, weight: .regular))
        .foregroundStyle(Color.secondary)

      VStack(spacing: 6) {
        Text("No Bearing Layer")
          .font(.headline.weight(.bold))
          .foregroundStyle(Color.primary)

        Text("No soil strata meet the current identification criteria.")
          .font(.subheadline)
          .foregroundStyle(Color.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 24)
    .frame(maxWidth: 320)
    .background(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground).opacity(0.95))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
    .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 8)
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  NavigationStack {
    ResultAnalysisView()
  }
  .environment(AppRouter())
  .environment(ProjectViewModel())
}
