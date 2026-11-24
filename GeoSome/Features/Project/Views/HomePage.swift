import SwiftUI

struct HomePage: View {
  @Environment(AppRouter.self) private var router
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var viewModel: ProjectViewModel
  @State private var captionCenter = AccessibilityCaptionCenter.shared
  @State private var isLaunchingDemo = false
  @AccessibilityFocusState private var isStartButtonFocused: Bool

  @ScaledMetric(relativeTo: .largeTitle) private var logoWidth: CGFloat = 100
  @ScaledMetric(relativeTo: .largeTitle) private var logoHeight: CGFloat = 100
  @ScaledMetric(relativeTo: .largeTitle) private var titleFontSize: CGFloat = 44

  init(viewModel: ProjectViewModel? = nil) {
    _viewModel = State(initialValue: viewModel ?? ProjectViewModel())
  }

  private var sheetBinding: Binding<SheetDestination?> {
    Binding(
      get: { router.isAtRoot ? viewModel.activeSheet : nil },
      set: { viewModel.activeSheet = $0 }
    )
  }

  var body: some View {
    @Bindable var viewModel = viewModel

    GeometryReader { geometry in
      ZStack(alignment: .top) {
        // Fullscreen Hero Background with secret multi-finger demo gesture
        TopographyBackground(
          darkOverlayOpacity: contrast == .increased ? 0.75 : 0.7,
          alignment: .center
        )
        .overlay {
          MultiFingerTapDetector(numberOfTouches: [3, 4]) {
            triggerDemoProject()
          }
        }

        // Hero Content placed in the upper portion above the sheet resting line
        ScrollView(.vertical, showsIndicators: false) {
          VStack(spacing: 16) {
            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 12 : 24)

            logoMark

            VStack(spacing: 8) {
              Text("Terravise")
                .font(.system(size: titleFontSize, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

              Text("Plan your site investigation with data-driven CPT recommendations.")
                .font(.title3)
                .foregroundStyle(contrast == .increased ? .white : .white.opacity(0.92))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            }

            StartProjectButton(action: {
              viewModel.dismissProjectSheet()
              Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                router.navigate(to: .boundaryCreation)
              }
            })
            .accessibilityFocused($isStartButtonFocused)
            .padding(.top, 4)

            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 12 : 24)
          }
          .frame(
            minWidth: geometry.size.width,
            minHeight: geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.62 : 0.56)
          )
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(
          width: geometry.size.width,
          height: geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.64 : 0.56)
        )
        .padding(.top, geometry.safeAreaInsets.top)

        if let caption = captionCenter.currentCaption {
          AccessibilityCaptionBannerView(
            caption: caption,
            onDismiss: { captionCenter.dismissCaption() }
          )
          .padding(.horizontal, 16)
          .padding(.top, geometry.safeAreaInsets.top + 8)
          .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        }
      }
      .ignoresSafeArea()
      .toolbar(.hidden, for: .navigationBar)
      .sheet(item: sheetBinding) { destination in
        switch destination {
        case .projectList:
          ProjectListSheet(
            projects: viewModel.projects,
            onSelectProject: { project in
              viewModel.selectProject(project)
              viewModel.dismissProjectSheet()
              captionCenter.announce("Opened project \(project.name).")
              Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                router.navigate(to: .projectDetail(id: project.id))
              }
            },
            onRenameProject: { project, newName in
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                viewModel.renameProject(id: project.id, newName: newName)
              }
              captionCenter.announce("Renamed project to \(newName).")
            },
            onDeleteProject: { project in
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                viewModel.deleteProject(id: project.id)
              }
              captionCenter.announce("Deleted project \(project.name).")
            }
          )
          .presentationPlacement(.center)
          .presentationSizing(FullWidthPresentationSizing())
          .presentationDetents(
            [
              ProjectViewModel.defaultSheetDetent,
              ProjectViewModel.expandedSheetDetent
            ],
            selection: $viewModel.selectedSheetDetent
          )
          .presentationDragIndicator(.visible)
          .presentationBackground(.background)
          .presentationBackgroundInteraction(.enabled)
          .presentationContentInteraction(.scrolls)
          .interactiveDismissDisabled()
        case .boundaryCoordinate:
          EmptyView()
        }
      }
      .onChange(of: router.isAtRoot) { _, isAtRoot in
        if isAtRoot {
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            if router.isAtRoot {
              viewModel.presentProjectSheet()
              isStartButtonFocused = true
            }
          }
        }
      }
    }
  }

  // MARK: - Branding

  private var logoMark: some View {
    Image("hero-mark")
      .resizable()
      .scaledToFit()
      .frame(width: logoWidth, height: logoHeight)
      .accessibilityHidden(true)
      .contentShape(Rectangle())
      .onTapGesture(count: 3) {
        triggerDemoProject()
      }
      .onLongPressGesture(minimumDuration: 1.5) {
        triggerDemoProject()
      }
  }

  // MARK: - Secret Demo Action

  private func triggerDemoProject() {
    guard !isLaunchingDemo else { return }
    isLaunchingDemo = true

    viewModel.dismissProjectSheet()
    let demoProject = DemoShowcaseData.makeDemoProject()
    viewModel.addProject(demoProject)
    viewModel.selectProject(demoProject)
    captionCenter.announce("Demo project loaded: \(demoProject.name)")

    #if canImport(UIKit)
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(.success)
    #endif

    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(220))
      router.navigate(to: .projectDetail(id: demoProject.id))
      try? await Task.sleep(for: .milliseconds(1200))
      isLaunchingDemo = false
    }
  }
}

#Preview("Empty State") {
  HomePage(viewModel: ProjectViewModel(projects: []))
    .environment(AppRouter())
}
