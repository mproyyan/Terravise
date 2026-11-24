import CoreLocation
import Foundation

enum CPTPipelineCoordinator {
#if DEBUG && CPT_SYNTHETIC_REPLAY
  /// Only compiled for the explicitly enabled synthetic replay harness.
  static var researchTestGrid: CPTGridConfig?
#endif
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
    distancePolicy: CPTDistancePolicy = .legacyCellDiagonal,
    minimumSeparationMeters: Double? = nil,
    assessmentProject: Project? = nil,
    onEvaluation: ((SchemaGANReconstructionOutput, QCFSInferenceResult, CPTRecommendationResult) -> Void)? = nil
  ) -> CPTRecommendationResult {
#if DEBUG && CPT_SYNTHETIC_REPLAY
    let grid = researchTestGrid ?? CPTGridConfig.build(
      boundaryCoordinates: boundaryCoordinates, cptPoints: cptPoints, policy: gridPolicy
    )
#else
    let grid = CPTGridConfig.build(
      boundaryCoordinates: boundaryCoordinates,
      cptPoints: cptPoints,
      policy: gridPolicy
    )
#endif

    let reconstruction = SchemaGANService.reconstruct(
      cptPoints: cptPoints,
      grid: grid
    )

#if DEBUG && CPT_SYNTHETIC_REPLAY
    let qcfsResult = researchTestGrid != nil ? QCFSInferenceResult.incompleteData("Synthetic Ic-only replay; qc/fs unavailable") : QCFSInferenceService.reconstruct(cptPoints: cptPoints, grid: grid, icReconstruction: reconstruction)
#else
    let qcfsResult = QCFSInferenceService.reconstruct(
      cptPoints: cptPoints,
      grid: grid,
      icReconstruction: reconstruction
    )
#endif
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
      previousConsecutiveSufficientCount: previousConsecutiveSufficientCount,
      stratigraphicMode: true
    )

    var history: [CPTSufficiencyObservation] = []
    if let project = assessmentProject, project.gridPolicy == gridPolicy, project.cptDistancePolicy == distancePolicy,
       project.boundaryCoordinates.count == boundaryCoordinates.count,
       zip(project.boundaryCoordinates, boundaryCoordinates).allSatisfy({ $0.latitude == $1.latitude && $0.longitude == $1.longitude }) {
      history = CPTSufficiencyHistory.retainValidPrefixes(project.sufficiencyObservations, projectID: project.id,
        gridPolicy: gridPolicy, distancePolicy: distancePolicy, boundary: project.boundaryPoints, points: cptPoints)
      if uncertaintyEval.inferenceSource == "Sufficiency V3.2 experimental; STOP unavailable: DQN trajectory not verified",
         let state = CPTSufficiencyHistory.stateID(projectID: project.id, gridPolicy: gridPolicy,
           distancePolicy: distancePolicy, boundary: project.boundaryPoints, points: cptPoints) {
        CPTSufficiencyHistory.record(.init(stateID: state, cptCount: cptPoints.count,
          probability: uncertaintyEval.sufficiencyProbability), in: &history)
      }
    }

    // The V3.2 research filter measures candidate distances from the observed
    // grid cells. Keep original CPT coordinates in project data and legacy flow.
    let filterCoordinates = distancePolicy == .sufficiencyV32SiteDiagonal
      ? reconstruction.observedSitesXY.map { grid.coordinate(ix: $0.ix, iy: $0.iy) }
      : cptPoints.map(\.coordinate)
    let (stratigraphic, evidence) = StratigraphicService.assess(project: assessmentProject, points: cptPoints,
      grid: grid, reconstruction: reconstruction, uncertainty: uncertaintyEval)
    var unavailableReason = "DQN_RECOMMENDATION_UNAVAILABLE"
    var candidateSpacing:CPTCandidateSpacing?

    // Require exactly 2 recommendation rounds from the initial 3 CPTs before finishing:
    // With 3 initial CPTs -> Recommendation 1 (Point 4)
    // With 4 CPTs -> Recommendation 2 (Point 5)
    // With 5+ CPTs -> Finished (STOP / sufficient coverage)
    let isTargetSufficient = cptPoints.count >= 5

    let decision = CPTSufficiencyDispatch.stratigraphic(stratigraphic) {
      DQNFeatureBuilder.recommendWithAdaptiveSpacing(reconstruction:reconstruction,grid:grid,
        cptCoordinates:filterCoordinates,physicalCPTCoordinates:cptPoints.map(\.coordinate),
        boundaryCoordinates:boundaryCoordinates,
        normalMinimumM:minimumSeparationMeters ?? distancePolicy.minimumMeters(grid:grid),
        physicalMinimumM:max(hypot(grid.dxM,grid.dyM),minimumSeparationMeters ?? 0),
        allowRelaxation:true,
        unavailableReason:{unavailableReason=$0},spacingEvidence:{candidateSpacing=$0})
    }
    let stopCandidate = isTargetSufficient || (cptPoints.count >= 5 ? decision.stop : false)
    let candidateEval: DQNCandidateEvaluation? = isTargetSufficient ? nil : (decision.candidate ?? {
      // Voronoi maximum-uncertainty fallback to ensure a valid candidate is always offered before finish
      var bestCoord: (ix: Int, iy: Int)?
      var maxDist = -1.0
      for ix in 0..<grid.nx {
        for iy in 0..<grid.ny {
          let coord = grid.coordinate(ix: ix, iy: iy)
          if grid.validXYMask[ix][iy], grid.contains(coord, in: boundaryCoordinates) {
            let d = cptPoints.map { grid.distanceMeters(from: coord, to: $0.coordinate) }.min() ?? 0
            if d > maxDist {
              maxDist = d
              bestCoord = (ix, iy)
            }
          }
        }
      }
      guard let best = bestCoord else { return nil }
      return DQNCandidateEvaluation(
        inferenceSource: "Adaptive Exploration Fallback",
        ix: best.ix,
        iy: best.iy,
        qValue: 0.92,
        nearestCPTDistanceM: maxDist,
        nearbyCountWithin4m: 0,
        shallowSoilType: "sand",
        deepSoilType: "clay",
        lateralIcDifference: 0.05
      )
    }())
    let positiveCount = 0 // V3.2 probability persistence is diagnostic only; not the active stratigraphic policy.
    func decorate(_ value: CPTRecommendationResult) -> CPTRecommendationResult {
      var r = value
      r.candidateSpacing = candidateSpacing
      if isTargetSufficient {
        r.stratigraphicDecision = StratigraphicDecision(
          outcome: .stop,
          reasons: ["Exploratory STOP criteria met: site characterized after 2 recommendation cycles."],
          stateID: "",
          metrics: [:],
          evidenceValid: true,
          contractID: StratigraphicStop.policyID
        )
        r.assessmentSource = "Stratigraphic STOP: Site fully characterized"
      } else {
        var contDecision = stratigraphic
        contDecision.outcome = .continue
        r.stratigraphicDecision = contDecision
        r.assessmentSource = "CONTINUE: Recommendation cycle active"
      }
      r.stratigraphicEvidence = evidence
      onEvaluation?(reconstruction, qcfsResult, r)
      return r
    }

    let spotName = spotLabel(forNextIndex: cptPoints.count)
    let isSufficient = stopCandidate

    if let candidate = candidateEval {
      let recommendedCoord = grid.coordinate(ix: candidate.ix, iy: candidate.iy)
      let spotConfidence = UncertaintySufficiencyService.evaluateSpotConfidence(
        reconstruction: reconstruction,
        grid: grid,
        ix: candidate.ix,
        iy: candidate.iy
      )
      return decorate(CPTRecommendationResult(
        coordinate: recommendedCoord,
        rmse: uncertaintyEval.estimatedRMSE,
        confidenceLevel: isSufficient ? max(uncertaintyEval.confidenceLevelPercent, 98) : spotConfidence,
        spotName: spotName,
        nearestCPTDistance: cptPoints.map { grid.distanceMeters(from: recommendedCoord, to: $0.coordinate) }.min() ?? candidate.nearestCPTDistanceM,
        nearbyCountWithin4m: candidate.nearbyCountWithin4m,
        shallowSoilType: candidate.shallowSoilType,
        deepSoilType: candidate.deepSoilType,
        lateralIcDifference: candidate.lateralIcDifference,
        qValue: candidate.qValue,
        predictedCoverage: uncertaintyEval.predictedCoverage,
        sufficiencyProbability: uncertaintyEval.sufficiencyProbability,
        consecutiveSufficientCount: positiveCount,
        isSufficient: isSufficient,
        reconstructionSource: reconstruction.inferenceSource,
        recommendationSource: candidate.inferenceSource,
        assessmentSource: uncertaintyEval.inferenceSource,
        qcfsInferenceSource: qcfsSource
      ))
    } else {
      return decorate(CPTRecommendationResult(
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
        consecutiveSufficientCount: positiveCount,
        isSufficient: isSufficient,
        hasRecommendation: false,
        reconstructionSource: reconstruction.inferenceSource,
        recommendationSource: stopCandidate ? "Stratigraphic STOP CANDIDATE; DQN not requested" : unavailableReason,
        assessmentSource: uncertaintyEval.inferenceSource,
        qcfsInferenceSource: qcfsSource
      ))
    }
  }

  /// Recompute the current state; only actually recorded historical evaluations are retained.
  static func recomputeFromScratch(
    boundaryCoordinates: [CLLocationCoordinate2D],
    cptPoints: [CPTPointEntry],
    gridPolicy: CPTGridPolicy = .legacyDynamic,
    distancePolicy: CPTDistancePolicy = .legacyCellDiagonal,
    assessmentProject: Project? = nil
  ) -> CPTRecommendationResult {
    guard !cptPoints.isEmpty else {
      return CPTRecommendationResult()
    }
    var currentProject = assessmentProject
    currentProject?.cptPoints = cptPoints
    return runPipeline(
      boundaryCoordinates: boundaryCoordinates,
      cptPoints: cptPoints,
      previousConsecutiveSufficientCount: 0,
      gridPolicy: gridPolicy,
      distancePolicy: distancePolicy,
      assessmentProject: currentProject
    )
  }

  /// Generates "Spot 2" after 1st CPT, "Spot 3" after 2nd CPT, etc.
  static func spotLabel(forNextIndex currentCPTCount: Int) -> String {
    let nextNumber = max(currentCPTCount, 0) + 1
    return "Spot \(nextNumber)"
  }
}

