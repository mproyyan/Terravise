import CoreLocation
import Foundation
import MapKit

struct Project: Identifiable, Hashable, Codable, Sendable {
  let id: UUID
  var name: String
  var lastEdited: Date
  var boundaryPoints: [BoundaryPoint]
  var cptPoints: [CPTPointEntry]
  var latestRecommendation: CPTRecommendationResult?
  var consecutiveSufficientCount: Int

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case lastEdited
    case boundaryPoints
    case cptPoints
    case latestRecommendation
    case consecutiveSufficientCount
  }

  init(
    id: UUID = UUID(),
    name: String,
    lastEdited: Date = Date(),
    boundaryPoints: [BoundaryPoint] = [],
    cptPoints: [CPTPointEntry] = [],
    latestRecommendation: CPTRecommendationResult? = nil,
    consecutiveSufficientCount: Int = 0
  ) {
    self.id = id
    self.name = name
    self.lastEdited = lastEdited
    self.boundaryPoints = boundaryPoints
    self.cptPoints = cptPoints
    self.latestRecommendation = latestRecommendation
    self.consecutiveSufficientCount = consecutiveSufficientCount
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    lastEdited = try container.decode(Date.self, forKey: .lastEdited)
    boundaryPoints = try container.decode([BoundaryPoint].self, forKey: .boundaryPoints)
    cptPoints = try container.decodeIfPresent([CPTPointEntry].self, forKey: .cptPoints) ?? []
    latestRecommendation = try container.decodeIfPresent(CPTRecommendationResult.self, forKey: .latestRecommendation)
    consecutiveSufficientCount = try container.decodeIfPresent(Int.self, forKey: .consecutiveSufficientCount) ?? 0
  }

  var boundaryCoordinates: [CLLocationCoordinate2D] {
    boundaryPoints.map(\.coordinate)
  }

  var boundaryRegion: MKCoordinateRegion {
    guard let first = boundaryPoints.first else {
      return BoundaryMapConfiguration.defaultRegion
    }

    var minLat = first.latitude
    var maxLat = first.latitude
    var minLon = first.longitude
    var maxLon = first.longitude

    for point in boundaryPoints {
      minLat = min(minLat, point.latitude)
      maxLat = max(maxLat, point.latitude)
      minLon = min(minLon, point.longitude)
      maxLon = max(maxLon, point.longitude)
    }

    let center = CLLocationCoordinate2D(
      latitude: (minLat + maxLat) / 2,
      longitude: (minLon + maxLon) / 2
    )
    let span = MKCoordinateSpan(
      latitudeDelta: max((maxLat - minLat) * 1.8, 0.002),
      longitudeDelta: max((maxLon - minLon) * 1.8, 0.002)
    )
    return MKCoordinateRegion(center: center, span: span)
  }
}

protocol ProjectStorageProtocol {
  func loadProjects() -> [Project]
  func saveProjects(_ projects: [Project])
}

struct LocalProjectStorage: ProjectStorageProtocol {
  private let fileURL: URL

  init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      let baseDirectory =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ??
        URL.temporaryDirectory
      self.fileURL = baseDirectory.appendingPathComponent("projects.json")
    }
  }

  func loadProjects() -> [Project] {
    guard
      FileManager.default.fileExists(atPath: fileURL.path),
      let data = try? Data(contentsOf: fileURL),
      let decoded = try? JSONDecoder().decode([Project].self, from: data)
    else {
      return []
    }
    return decoded
  }

  func saveProjects(_ projects: [Project]) {
    let directoryURL = fileURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    guard let data = try? JSONEncoder().encode(projects) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }
}
