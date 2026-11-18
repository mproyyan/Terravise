import SwiftUI

struct HomePage: View {
  @Environment(AppRouter.self) private var router
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var viewModel: ProjectViewModel
  @State private var captionCenter = AccessibilityCaptionCenter.shared
  @AccessibilityFocusState private var isStartButtonFocused: Bool

  @ScaledMetric(relativeTo: .largeTitle) private var logoWidth: CGFloat = 52
  @ScaledMetric(relativeTo: .largeTitle) private var logoHeight: CGFloat = 48

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
        // Fullscreen Hero Background
        heroBackgroundPlaceholder

        // Hero Content placed in the upper portion above the sheet resting line
        ScrollView(.vertical, showsIndicators: false) {
          VStack(spacing: 16) {
            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 12 : 24)

            logoPlaceholder

            VStack(spacing: 8) {
              Text("Terravise")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

              Text("Plan your site investigation with data-driven CPT recommendations.")
                .font(.subheadline)
                .foregroundStyle(contrast == .increased ? .white : .white.opacity(0.92))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            }

            StartProjectButton(action: {
              viewModel.dismissProjectSheet()
              router.navigate(to: .boundaryCreation)
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
              router.navigate(to: .projectDetail(id: project.id))
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

  // MARK: - Placeholders

  private var heroBackgroundPlaceholder: some View {
    ZStack {
      LinearGradient(
        colors: heroGradientColors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      Rectangle()
        .fill(
          RadialGradient(
            colors: [
              Color.white.opacity(contrast == .increased ? 0.04 : 0.08),
              Color.black.opacity(contrast == .increased ? 0.6 : 0.45)
            ],
            center: .center,
            startRadius: 40,
            endRadius: 400
          )
        )
    }
    .accessibilityHidden(true)
  }

  private var heroGradientColors: [Color] {
    if contrast == .increased {
      return [
        Color(red: 0.16, green: 0.12, blue: 0.10),
        Color(red: 0.10, green: 0.08, blue: 0.06),
        Color(red: 0.05, green: 0.04, blue: 0.03)
      ]
    }
    if colorScheme == .dark {
      return [
        Color(red: 0.24, green: 0.19, blue: 0.16),
        Color(red: 0.17, green: 0.13, blue: 0.11),
        Color(red: 0.10, green: 0.08, blue: 0.07)
      ]
    }
    return [
      Color(red: 0.34, green: 0.26, blue: 0.22),
      Color(red: 0.25, green: 0.19, blue: 0.15),
      Color(red: 0.16, green: 0.12, blue: 0.10)
    ]
  }

  private var logoPlaceholder: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 14, style: .continuous)

        .frame(width: logoWidth, height: logoHeight)
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(
              Color.white.opacity(contrast == .increased ? 0.8 : 0.2),
              lineWidth: contrast == .increased ? 2 : 1
            )
        )
        .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)

        Image("logo-fix")
            .resizable()
            .scaledToFit()
            .frame(width: 56, height: 56)
    }
    .accessibilityHidden(true)
  }
}

#Preview("Empty State") {
  HomePage(viewModel: ProjectViewModel(projects: []))
    .environment(AppRouter())
}
