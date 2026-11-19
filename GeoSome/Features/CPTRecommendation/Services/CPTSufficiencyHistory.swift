import CryptoKit
import CoreLocation
import Foundation

/// Evidence of an actual first CPT upload; no DQN recommendation is implied.
struct CPTInitialObservationEvidence: Codable, Hashable, Sendable {
  let stateBefore: String
  let stateAfter: String
  let cptID: UUID
  let latitude: Double
  let longitude: Double
}

/// Persisted evidence only. A matching coordinate alone does not prove DQN provenance.
struct CPTRecommendationEvidence: Codable, Hashable, Sendable {
  let id: UUID
  let stateBefore: String
  let recommendedLatitude: Double
  let recommendedLongitude: Double
  let model: String
  let distancePolicy: String
  var acceptedCPTID: UUID?
  var stateAfter: String?
  var coordinateMatches: Bool?
  /// Nil means the app cannot prove whether the user manually edited the coordinate.
  var acceptedWithoutManualChange: Bool?
}

struct CPTSufficiencyObservation: Codable, Hashable, Sendable {
  let stateID: String
  let cptCount: Int
  let probability: Double
}

enum CPTSufficiencyHistory {
#if DEBUG && CPT_SYNTHETIC_REPLAY
  /// Explicit opt-in for one synthetic replay grid; never included in Release.
  static var syntheticReplayEnabled = false
#endif
#if CPT_COORDINATOR_TEST
  // Test harness only. Not present in application builds.
  static var testOnlyPipelineParityEvidence = false
#endif
  enum CompatibilityFailure: String, Sendable {
    case missingProject, stateMismatch, wrongPolicy, outsideResearchDomain, outsideValidatedCPTCount, missingProvenance, featureParityUnverified, pipelineParityUnverified, outsideParityFixtureScope
  }

  struct Compatibility: Sendable {
    let failures: [CompatibilityFailure]
    var isCompatible: Bool { failures.isEmpty }
    /// The experimental model decision is separate from research-domain status.
    var permitsModelDecision: Bool { failures.allSatisfy { $0 == .outsideResearchDomain } }
  }

  /// Fails closed: the historical Python/Swift runtime-feature parity evidence
  /// has not yet been established for this application pipeline.
  static func validate(project: Project?, points: [CPTPointEntry], grid: CPTGridConfig) -> Compatibility {
    guard let project else { return .init(failures: [.missingProject, .featureParityUnverified]) }
    var failures: [CompatibilityFailure] = []
    let projectState = stateID(projectID: project.id, gridPolicy: project.gridPolicy, distancePolicy: project.cptDistancePolicy,
      boundary: project.boundaryPoints, points: project.cptPoints)
    let inputState = stateID(projectID: project.id, gridPolicy: project.gridPolicy, distancePolicy: project.cptDistancePolicy,
      boundary: project.boundaryPoints, points: points)
    if projectState == nil || projectState != inputState { failures.append(.stateMismatch) }
    if project.cptDistancePolicy != .sufficiencyV32SiteDiagonal { failures.append(.wrongPolicy) }
    // Grid configurations listed in v32_holdout2_manifest.csv. Geographic projection
    // round-off is tolerated; this does not extend the evaluated physical domain.
    func spacing(_ actual: Double, _ expected: Double) -> Bool { actual.isFinite && abs(actual - expected) <= 1e-6 }
    let supported = (grid.nx == 24 && grid.ny == 24 && grid.nz == 12 && spacing(grid.dzM, 1) &&
      ((spacing(grid.dxM, 1) && spacing(grid.dyM, 1)) || (spacing(grid.dxM, 5) && spacing(grid.dyM, 5)))) ||
      (grid.nx == 32 && grid.ny == 32 && grid.nz == 16 && spacing(grid.dxM, 5) && spacing(grid.dyM, 5) && spacing(grid.dzM, 2)) ||
      (grid.nx == 40 && grid.ny == 40 && grid.nz == 24 && spacing(grid.dxM, 25) && spacing(grid.dyM, 25) && spacing(grid.dzM, 2)) ||
      (grid.nx == 48 && grid.ny == 32 && grid.nz == 20 && spacing(grid.dxM, 10) && spacing(grid.dyM, 10) && spacing(grid.dzM, 2))
    var supportedDomain = supported
#if DEBUG && CPT_SYNTHETIC_REPLAY
    if syntheticReplayEnabled && grid.nx == 32 && grid.ny == 32 && grid.nz == 16 &&
      spacing(grid.dxM, 7.139612356115623) && spacing(grid.dyM, 7.134670784122269) && spacing(grid.dzM, 0.7333333333333333) {
      supportedDomain = true
    }
#endif
    if !(1...32).contains(points.count) { failures.append(.outsideValidatedCPTCount) }
    if !supportedDomain { failures.append(.outsideResearchDomain) }
    // Every transition must be linked to the exact prefix and accepted CPT.
    if points.count > 1 {
      for index in 1..<points.count {
        let before = stateID(projectID: project.id, gridPolicy: project.gridPolicy, distancePolicy: project.cptDistancePolicy,
          boundary: project.boundaryPoints, points: Array(points.prefix(index)))
        let after = stateID(projectID: project.id, gridPolicy: project.gridPolicy, distancePolicy: project.cptDistancePolicy,
          boundary: project.boundaryPoints, points: Array(points.prefix(index + 1)))
        let evidence = project.cptRecommendationEvidence.first { $0.stateBefore == before && $0.stateAfter == after &&
          $0.acceptedCPTID == points[index].id && $0.model == "DQN V4.6-A Core ML" &&
          $0.distancePolicy == CPTDistancePolicy.sufficiencyV32SiteDiagonal.rawValue &&
          $0.coordinateMatches == true && $0.acceptedWithoutManualChange == true }
        if before == nil || after == nil || evidence == nil { failures.append(.missingProvenance); break }
      }
    }
    // Python starts at the closest full-depth valid cell to the grid centre,
    // with x-major/y-minor tie breaking. The evidence must be from upload time.
    let initial = project.cptInitialObservation
    let emptyState = stateID(projectID: project.id, gridPolicy: project.gridPolicy, distancePolicy: project.cptDistancePolicy,
      boundary: project.boundaryPoints, points: [])
    let firstState = stateID(projectID: project.id, gridPolicy: project.gridPolicy, distancePolicy: project.cptDistancePolicy,
      boundary: project.boundaryPoints, points: Array(points.prefix(1)))
    let centerX = Double(grid.nx - 1) / 2, centerY = Double(grid.ny - 1) / 2
    var centerCell: (Int, Int)?
    var centerDistance = Double.infinity
    if grid.validXYMask.count == grid.nx, grid.validXYMask.allSatisfy({ $0.count == grid.ny }) {
      for x in 0..<grid.nx { for y in 0..<grid.ny where grid.validXYMask[x][y] {
        let distance = hypot(Double(x) - centerX, Double(y) - centerY)
        if distance < centerDistance { centerCell = (x, y); centerDistance = distance }
      } }
    }
    let first = points.first
    let cell = first.map { grid.gridIndices(for: $0.coordinate) }
    let coversDepth = first.map { point in
      guard let minDepth = point.rows.map(\.depth).min(), let maxDepth = point.rows.map(\.depth).max() else { return false }
      return minDepth <= 0.5 * grid.dzM + 1e-6 && maxDepth >= Double(grid.nz - 1) * grid.dzM - 0.5 * grid.dzM - 1e-6
    } ?? false
    let initialValid = initial != nil && first != nil && emptyState != nil && firstState != nil &&
      initial?.stateBefore == emptyState && initial?.stateAfter == firstState && initial?.cptID == first?.id &&
      initial?.latitude == first?.coordinate.latitude && initial?.longitude == first?.coordinate.longitude &&
      cell?.ix == centerCell?.0 && cell?.iy == centerCell?.1 && centerCell != nil && coversDepth
    if !initialValid && !failures.contains(.missingProvenance) { failures.append(.missingProvenance) }
    if !UncertaintySufficiencyService.v32FeatureParityVerified { failures.append(.featureParityUnverified) }
    // The bundled fixture validates aggregation from raw bounds, not the full
    // SchemaGAN-to-Uncertainty raw-bound pipeline on matching runtime inputs.
#if CPT_COORDINATOR_TEST
    if !testOnlyPipelineParityEvidence { failures.append(.pipelineParityUnverified) }
#else
    if !CPTPipelineParityAttestation.implementationVerified() { failures.append(.pipelineParityUnverified) }

#endif
    return .init(failures: failures)
  }
  private struct State: Encodable {
    let projectID: UUID
    let gridPolicy: CPTGridPolicy
    let distancePolicy: CPTDistancePolicy
    let boundary: [BoundaryPoint]
    let points: [CPTPointEntry]
  }

  static func stateID(projectID: UUID, gridPolicy: CPTGridPolicy, distancePolicy: CPTDistancePolicy = .legacyCellDiagonal, boundary: [BoundaryPoint], points: [CPTPointEntry]) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let bytes = try? encoder.encode(State(projectID: projectID, gridPolicy: gridPolicy, distancePolicy: distancePolicy, boundary: boundary, points: points)) else { return nil }
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }

  /// Remove observations whose complete prefix no longer matches current data.
  static func retainValidPrefixes(_ history: [CPTSufficiencyObservation], projectID: UUID, gridPolicy: CPTGridPolicy, distancePolicy: CPTDistancePolicy = .legacyCellDiagonal,
                                  boundary: [BoundaryPoint], points: [CPTPointEntry]) -> [CPTSufficiencyObservation] {
    history.filter { item in
      guard item.cptCount > 0, item.cptCount <= points.count else { return false }
      return stateID(projectID: projectID, gridPolicy: gridPolicy, distancePolicy: distancePolicy, boundary: boundary,
                     points: Array(points.prefix(item.cptCount))) == item.stateID
    }
  }

  static func record(_ observation: CPTSufficiencyObservation, in history: inout [CPTSufficiencyObservation]) {
    guard observation.probability.isFinite, (0...1).contains(observation.probability), observation.cptCount > 0 else { return }
    history.removeAll { $0.cptCount >= observation.cptCount }
    history.append(observation)
  }

  /// Describes model outputs, not permission to stop; compatibility is separate.
  static func consecutivePositive(_ history: [CPTSufficiencyObservation], threshold: Double) -> Int {
    var result = 0, previous: Int?
    for item in history.reversed() {
      guard item.probability >= threshold, previous == nil || item.cptCount == previous! - 1 else { break }
      result += 1
      previous = item.cptCount
    }
    return result
  }
}
