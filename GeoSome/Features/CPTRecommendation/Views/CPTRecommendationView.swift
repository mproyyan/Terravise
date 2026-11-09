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

  var body: some View {
    @Bindable var viewModel = viewModel

    ZStack {
      // Fullscreen Map Content Layer with Boundary (Tanpa Titik)
      CPTMapContentLayer(
        cameraPosition: $viewModel.cameraPosition,
        coordinates: viewModel.coordinates,
        isSatelliteStyle: viewModel.isSatelliteStyle
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
    // Native Sheet with .presentationPlacement(.leading) matching BoundaryCreationView
    .sheet(isPresented: $viewModel.isSheetPresented) {
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
    }
    .toolbar {
      CPTRecommendationToolbarContent(
        projectName: viewModel.project.name,
        onEditAreaTap: {
          viewModel.editArea()
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
    .alert("Upload CPT Data", isPresented: $viewModel.isUploadAlertPresented) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("CPT data uploader will be configured here. Your uploaded data will help identify areas where additional CPT testing may be useful.")
    }
    .task {
      if let projectId {
        viewModel.resolveProject(with: projectId, from: projectViewModel)
      } else if let selected = projectViewModel?.selectedProject {
        viewModel.updateProject(selected)
      }

      try? await Task.sleep(for: .milliseconds(450))
      if !Task.isCancelled, isCurrentDestination {
        viewModel.presentSheet()
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
