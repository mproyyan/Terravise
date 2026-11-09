import Observation
import SwiftUI

@MainActor
@Observable
final class AppRouter {
  var path: [AppRoute]

  init(initialPath: [AppRoute] = []) {
    path = initialPath
  }

  var currentRoute: AppRoute? {
    path.last
  }

  var isAtRoot: Bool {
    path.isEmpty
  }

  func navigate(to route: AppRoute) {
    path.append(route)
  }

  func pop() {
    guard !path.isEmpty else { return }
    path.removeLast()
  }

  func popToRoot() {
    path = []
  }
}

extension View {
  func withAppRouter() -> some View {
    navigationDestination(for: AppRoute.self) { route in
      switch route {
      case .boundaryCreation:
        BoundaryCreationView()
      case let .projectDetail(id):
        CPTRecommendationView(projectId: id)
      }
    }
  }
}
