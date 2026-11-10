import CoreLocation
import Foundation

enum CPTPipelineCoordinator {
  /// Runs the end-to-end CPT3D-67 pipeline:
  /// 1. Builds the local 3D grid configuration from boundary polygon & uploaded CPTs
  /// 2. Reconstructs the 3D Robertson Ic volume via SchemaGAN V4.2 Flexible
  /// 3. Evaluates voxel error bounds (Uncertainty V3) and stopping probability (Sufficiency V3.1)
  /// 4. Recommends the next candidate CPT location via DQN V4.6-A (29 features)
  static func runPipeline(
    boundaryCoordinates: [CLLocationCoordinate2D],
    cptPoints: [CPTPointEntry],
    previousConsecutiveSufficientCount: Int
  ) -> CPTRecommendationResult {
    let grid = CPTGridConfig.build(
      boundaryCoordinates: boundaryCoordinates,
      cptPoints: cptPoints
    )

    let reconstruction = SchemaGANService.reconstruct(
      cptPoints: cptPoints,
      grid: grid
    )

    let uncertaintyEval = UncertaintySufficiencyService.evaluate(
      reconstruction: reconstruction,
      grid: grid,
      previousConsecutiveSufficientCount: previousConsecutiveSufficientCount
    )

    let candidateEval = DQNFeatureBuilder.recommendNextCandidate(
      reconstruction: reconstruction,
      grid: grid
    )

    let spotName = spotLabel(forNextIndex: cptPoints.count)
    let isSufficient = uncertaintyEval.isSufficient || candidateEval == nil

    if let candidate = candidateEval {
      let recommendedCoord = grid.coordinate(ix: candidate.ix, iy: candidate.iy)
      return CPTRecommendationResult(
        coordinate: recommendedCoord,
        rmse: uncertaintyEval.estimatedRMSE,
        confidenceLevel: uncertaintyEval.confidenceLevelPercent,
        spotName: spotName,
        nearestCPTDistance: candidate.nearestCPTDistanceM,
        nearbyCountWithin4m: candidate.nearbyCountWithin4m,
        shallowSoilType: candidate.shallowSoilType,
        deepSoilType: candidate.deepSoilType,
        lateralIcDifference: candidate.lateralIcDifference,
        qValue: candidate.qValue,
        predictedCoverage: uncertaintyEval.predictedCoverage,
        sufficiencyProbability: uncertaintyEval.sufficiencyProbability,
        consecutiveSufficientCount: uncertaintyEval.consecutiveSufficientCount,
        isSufficient: isSufficient
      )
    } else {
      let fallbackCoord = cptPoints.last?.coordinate
        ?? grid.coordinate(ix: grid.nx / 2, iy: grid.ny / 2)
      return CPTRecommendationResult(
        coordinate: fallbackCoord,
        rmse: uncertaintyEval.estimatedRMSE,
        confidenceLevel: uncertaintyEval.confidenceLevelPercent,
        spotName: spotName,
        nearestCPTDistance: 0.0,
        nearbyCountWithin4m: cptPoints.count,
        shallowSoilType: "sand",
        deepSoilType: "clay",
        lateralIcDifference: 0.0,
        qValue: 0.0,
        predictedCoverage: uncertaintyEval.predictedCoverage,
        sufficiencyProbability: uncertaintyEval.sufficiencyProbability,
        consecutiveSufficientCount: uncertaintyEval.consecutiveSufficientCount,
        isSufficient: true
      )
    }
  }

  /// Recomputes the pipeline sequentially from 1..N CPT points (used when a point is deleted).
  static func recomputeFromScratch(
    boundaryCoordinates: [CLLocationCoordinate2D],
    cptPoints: [CPTPointEntry]
  ) -> CPTRecommendationResult {
    guard !cptPoints.isEmpty else {
      return CPTRecommendationResult()
    }
    var consecutiveCount = 0
    var latestResult = CPTRecommendationResult()

    for endIdx in 1 ... cptPoints.count {
      let prefixPoints = Array(cptPoints.prefix(endIdx))
      latestResult = runPipeline(
        boundaryCoordinates: boundaryCoordinates,
        cptPoints: prefixPoints,
        previousConsecutiveSufficientCount: consecutiveCount
      )
      consecutiveCount = latestResult.consecutiveSufficientCount
    }

    return latestResult
  }

  /// Generates "Spot B" after 1st CPT, "Spot C" after 2nd CPT, etc.
  static func spotLabel(forNextIndex currentCPTCount: Int) -> String {
    let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    let index = max(currentCPTCount, 0)
    if index < letters.count {
      return "Spot \(letters[index])"
    }
    return "Spot #\(index + 1)"
  }
}

