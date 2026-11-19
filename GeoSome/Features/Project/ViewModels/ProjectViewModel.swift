import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ProjectViewModel {
  static let defaultSheetDetent: PresentationDetent = .fraction(0.44)
  static let expandedSheetDetent: PresentationDetent = .fraction(0.88)

  private(set) var projects: [Project]
  private(set) var selectedProject: Project?
  var activeSheet: SheetDestination? = .projectList
  var selectedSheetDetent: PresentationDetent
  private let storage: ProjectStorageProtocol?

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter
  }()

  private static let monthDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter
  }()

  init(
    projects: [Project]? = nil,
    storage: ProjectStorageProtocol? = nil,
    selectedSheetDetent: PresentationDetent = .fraction(0.44)
  ) {
    if let projects {
      self.storage = storage
      self.projects = projects
    } else {
      let resolvedStorage = storage ?? LocalProjectStorage()
      self.storage = resolvedStorage
      self.projects = resolvedStorage.loadProjects()
    }
    self.selectedSheetDetent = selectedSheetDetent
  }

  var hasProjects: Bool {
    !projects.isEmpty
  }

  // MARK: - Intents

  func dismissProjectSheet() {
    activeSheet = nil
  }

  func presentProjectSheet() {
    activeSheet = .projectList
  }

  func selectProject(_ project: Project) {
    selectedProject = project
  }

  func updateProject(_ project: Project) {
    if let index = projects.firstIndex(where: { $0.id == project.id }) {
      projects[index] = project
      storage?.saveProjects(projects)
    }
  }

  func addProject(_ project: Project) {
    projects.insert(project, at: 0)
    storage?.saveProjects(projects)
  }

  func addProject(name: String, boundaryPoints: [BoundaryPoint] = []) {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return }
    let newProject = Project(
      name: trimmedName,
      lastEdited: Date(),
      boundaryPoints: boundaryPoints
    )
    projects.insert(newProject, at: 0)
    storage?.saveProjects(projects)
  }

  func deleteProject(id: UUID) {
    projects.removeAll { $0.id == id }
    storage?.saveProjects(projects)
  }

  func clearAllProjects() {
    projects.removeAll()
    storage?.saveProjects(projects)
  }

  // MARK: - Presentation Formatting

  func formattedLastEdited(for project: Project, relativeTo now: Date = Date()) -> String {
    Self.formatLastEdited(project.lastEdited, relativeTo: now)
  }

  static func formatLastEdited(
    _ date: Date,
    relativeTo now: Date = Date(),
    calendar: Calendar = .current
  ) -> String {
    let timeString = timeFormatter.string(from: date)

    if calendar.isDateInToday(date) {
      let interval = now.timeIntervalSince(date)
      if interval < 120 {
        return "Edited just now"
      }
      return "Edited today at \(timeString)"
    } else if calendar.isDateInYesterday(date) {
      return "Edited yesterday at \(timeString)"
    } else {
      let dateString = monthDayFormatter.string(from: date)
      return "Edited \(dateString) at \(timeString)"
    }
  }
}
