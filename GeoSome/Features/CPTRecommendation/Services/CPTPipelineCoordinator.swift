import CoreLocation
import Foundation

enum CPTPipelineCoordinator {
  /// Phase 4 screening accepts only a successful QC-FS Core ML result.
  static func evaluateBearingRule(
    qcfs: QCFSInferenceResult,
    criteria: BearingRuleCriteria = .init()
  ) -> BearingRuleEvaluation {
    BearingRuleService.evaluate(qcfs: qcfs, criteria: criteria)
  }

  /// Phase 2 QC-FS result for the same grid and observed-site mapping as SchemaGAN.
  /// This is independent of DQN and never substitutes IDW for a failed CNN inference.
  static func reconstructQCFS(
    boundaryCoordinates: [CLLocationCoordinate2D],
    cptPoints: [CPTPointEntry],
    gridPolicy: CPTGridPolicy = .legacyDynamic
  ) -> QCFSInferenceResult {
    let grid = CPTGridConfig.build(boundaryCoordinates: boundaryCoordinates, cptPoints: cptPoints, policy: gridPolicy)
    let ic = SchemaGANService.reconstruct(cptPoints: cptPoints, grid: grid)
    return QCFSInferenceService.reconstruct(cptPoints: cptPoints, grid: grid, icReconstruction: ic)
  }

  /// Runs the end-to-end CPT3D-67 pipeline:
  /// 1. Builds the local 3D grid configuration from boundary polygon & uploaded CPTs
  /// 2. Reconstructs the 3D Robertson Ic volume via SchemaGAN V4.2 Flexible
  /// 3. Evaluates voxel error bounds (Uncertainty V3) and stopping probability (Sufficiency V3.1)
  /// 4. Recommends the next candidate CPT location via DQN V4.6-A (29 features)
  static func runPipeline(
    boundaryCoordinates: [CLLocationCoordinate2D],
    cptPoints: [CPTPointEntry],
    previousConsecutiveSufficientCount: Int,
    gridPolicy: CPTGridPolicy = .legacyDynamic,
    minimumSeparationMeters: Double? = nil
  ) -> CPTRecommendationResult {
    let grid = CPTGridConfig.build(
      boundaryCoordinates: boundaryCoordinates,
      cptPoints: cptPoints,
      policy: gridPolicy
    )

    let reconstruction = SchemaGANService.reconstruct(
      cptPoints: cptPoints,
      grid: grid
    )

    let qcfsResult = QCFSInferenceService.reconstruct(
      cptPoints: cptPoints,
      grid: grid,
      icReconstruction: reconstruction
    )
    let qcfsSource: String
    switch qcfsResult {
    case .coreML(let volume):
      qcfsSource = "QC-FS CNN V3 Core ML (\(volume.inputProvenance))"
    case .unsupportedGrid(let reason):
      qcfsSource = "QC-FS unsupported grid: \(reason)"
    case .incompleteData(let reason):
      qcfsSource = "QC-FS incomplete data: \(reason)"
    case .inferenceFailed(let reason):
      qcfsSource = "QC-FS inference failed: \(reason)"
    }

    let uncertaintyEval = UncertaintySufficiencyService.evaluate(
      reconstruction: reconstruction,
      grid: grid,
      previousConsecutiveSufficientCount: previousConsecutiveSufficientCount
    )

    let candidateEval = DQNFeatureBuilder.recommendNextCandidate(
      reconstruction: reconstruction,
      grid: grid,
      cptCoordinates: cptPoints.map(\.coordinate),
      boundaryCoordinates: boundaryCoordinates,
      minimumSeparationMeters: minimumSeparationMeters
    )

    let spotName = spotLabel(forNextIndex: cptPoints.count)
    let isSufficient = uncertaintyEval.isSufficient

    if let candidate = candidateEval {
      let recommendedCoord = grid.coordinate(ix: candidate.ix, iy: candidate.iy)
      let spotConfidence = UncertaintySufficiencyService.evaluateSpotConfidence(
        reconstruction: reconstruction,
        grid: grid,
        ix: candidate.ix,
        iy: candidate.iy
      )
      return CPTRecommendationResult(
        coordinate: recommendedCoord,
        rmse: uncertaintyEval.estimatedRMSE,
        confidenceLevel: isSufficient ? max(uncertaintyEval.confidenceLevelPercent, 98) : spotConfidence,
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
        isSufficient: isSufficient,
        reconstructionSource: reconstruction.inferenceSource,
        recommendationSource: candidate.inferenceSource,
        assessmentSource: uncertaintyEval.inferenceSource,
        qcfsInferenceSource: qcfsSource
      )
    } else {
      return CPTRecommendationResult(
        // Coordinate is ignored when hasRecommendation is false; retain a finite
        // value only for compatibility with existing saved-project encoding.
        coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
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
        isSufficient: isSufficient,
        hasRecommendation: false,
        reconstructionSource: reconstruction.inferenceSource,
        recommendationSource: "Tidak ada kandidat legal; DQN tidak menghasilkan titik",
        assessmentSource: uncertaintyEval.inferenceSource,
        qcfsInferenceSource: qcfsSource
      )
    }
  }

  /// Recomputes the pipeline sequentially from 1..N CPT points (used when a point is deleted).
  static func recomputeFromScratch(
    boundaryCoordinates: [CLLocationCoordinate2D],
    cptPoints: [CPTPointEntry],
    gridPolicy: CPTGridPolicy = .legacyDynamic
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
        previousConsecutiveSufficientCount: consecutiveCount,
        gridPolicy: gridPolicy
      )
      consecutiveCount = latestResult.consecutiveSufficientCount
    }

    return latestResult
  }

  /// Generates "Spot 2" after 1st CPT, "Spot 3" after 2nd CPT, etc.
  static func spotLabel(forNextIndex currentCPTCount: Int) -> String {
    let nextNumber = max(currentCPTCount, 0) + 1
    return "Spot \(nextNumber)"
  }
}

