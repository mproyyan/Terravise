import Foundation

enum AppRoute: Hashable {
  case boundaryCreation
  case editBoundary(id: Project.ID)
  case projectDetail(id: Project.ID)
}

enum SheetDestination: String, Identifiable, Hashable {
  case projectList
  case boundaryCoordinate

  var id: String {
    rawValue
  }
}
