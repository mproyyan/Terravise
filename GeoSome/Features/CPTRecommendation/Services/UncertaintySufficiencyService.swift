import Foundation

enum CPTAssessmentStatus: Sendable {
  case sufficientCandidate
  case continueInvestigation
  case reviewRequired

  /// Only a validated STOP candidate suppresses the next DQN recommendation.
  var permitsDQN: Bool { self != .sufficientCandidate }

  static func classify(modelValid: Bool, trajectoryCompatible: Bool, inResearchDomain: Bool, isSufficient: Bool) -> Self {
    guard modelValid, trajectoryCompatible, inResearchDomain else { return .reviewRequired }
    return isSufficient ? .sufficientCandidate : .continueInvestigation
  }
}

struct UncertaintySufficiencyEvaluation: Sendable {
  let inferenceSource: String
  let estimatedRMSE: Double
  let predictedCoverage: Double
  let sufficiencyProbability: Double
  let confidenceLevelPercent: Int
  let consecutiveSufficientCount: Int
  let isSufficient: Bool
  let assessmentStatus: CPTAssessmentStatus
  var spatialBounds: [[[Double]]]? = nil
  var spatialEvidenceValid: Bool = false
}

enum UncertaintySufficiencyService {
#if UNCERTAINTY_V3_PARITY_HARNESS
  static var parityFeatures: [[Double]] = []
  static var parityRawBounds: [Double] = []
  static var parityFinalBounds: [Double] = []
  static var parityCoordinates: [[Int]] = []
  static var parityCorrection: Double? = nil
  static var parityModelLoaded = false
#endif
  private struct V32FeatureParityFixture: Decodable {
    let nx: Int, ny: Int, nz: Int
    let dx: Double, dy: Double
    let valid: [[[Bool]]], observed: [[[Bool]]]
    let sites: [[Int]]
    let rawBounds: [Double], correction: Double, expected: [Double]
  }

  /// Verifies the production feature builder against Python's frozen fixture.
  /// This does not certify SchemaGAN or Uncertainty V3 inference parity.
  static let v32FeatureParityVerified: Bool = {
    guard let url = Bundle.main.url(forResource: "SufficiencyV32FeatureParity", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let fixture = try? JSONDecoder().decode(V32FeatureParityFixture.self, from: data),
      fixture.sites.allSatisfy({ $0.count == 2 }), fixture.expected.count == 10,
      fixture.expected.allSatisfy(\.isFinite),
      uncertaintyModel?.calibrationCorrection == fixture.correction,
      let values = v32Features(nx: fixture.nx, ny: fixture.ny, nz: fixture.nz, dx: fixture.dx, dy: fixture.dy,
        valid: fixture.valid, observed: fixture.observed, sites: fixture.sites.map { ($0[0], $0[1]) },
        rawBounds: fixture.rawBounds, correction: fixture.correction), values.count == 10 else { return false }
    return zip(values, fixture.expected).allSatisfy { $0.isFinite && abs($0 - $1) <= 1e-10 }
  }()

  /// Research feature contract. Bounds are uncalibrated, in XYZ hidden-voxel order.
  static func v32Features(nx: Int, ny: Int, nz: Int, dx: Double, dy: Double,
    valid: [[[Bool]]], observed: [[[Bool]]], sites: [(ix: Int, iy: Int)],
    rawBounds: [Double], correction: Double) -> [Double]? {
    guard nx > 1, ny > 1, nz > 0, dx.isFinite, dy.isFinite, dx > 0, dy > 0,
      correction.isFinite, !sites.isEmpty, sites.allSatisfy({ (0..<nx).contains($0.ix) && (0..<ny).contains($0.iy) }),
      valid.count == nx, observed.count == nx else { return nil }
    var hiddenCount = 0, maxDistance = 0.0, validColumns = 0
    for x in 0..<nx {
      guard valid[x].count == ny, observed[x].count == ny else { return nil }
      for y in 0..<ny {
        guard valid[x][y].count == nz, observed[x][y].count == nz else { return nil }
        for z in 0..<nz where valid[x][y][z] && !observed[x][y][z] { hiddenCount += 1 }
        if valid[x][y].contains(true) {
          validColumns += 1
          let nearest = sites.map { hypot(Double(x - $0.ix) * dx, Double(y - $0.iy) * dy) }.min()!
          maxDistance = max(maxDistance, nearest)
        }
      }
    }
    guard validColumns > 0, hiddenCount == rawBounds.count, rawBounds.allSatisfy(\.isFinite) else { return nil }
    let coverage = hiddenCount == 0 ? 1.0 : Double(rawBounds.filter { max(0, $0) + correction <= icTolerance }.count) / Double(hiddenCount)
    let width = Double(nx - 1) * dx, height = Double(ny - 1) * dy
    let diagonal = hypot(width, height), area = width * height
    return [coverage, maxDistance / max(diagonal, 1e-6), Double(sites.count), width, height,
      diagonal, area, sqrt(area / Double(sites.count)), maxDistance, max(width, height) / max(min(width, height), 1e-6)]
  }
  private struct TreeNode: Decodable, Sendable {
    let value: Double
    let featureIndex: Int
    let threshold: Double
    let missingGoToLeft: Bool
    let left: Int
    let right: Int
    let isLeaf: Bool
  }

  private struct ExportedTreeModel: Decodable, Sendable {
    let formatVersion: Int
    let modelType: String
    let baseline: Double
    let featureNames: [String]
    let treeCount: Int
    let trees: [[TreeNode]]
    let calibrationCorrection: Double?
    let probabilityThreshold: Double?
    let persistence: Int?
  }

  static let icTolerance: Double = 0.15
  // Decision policy is independent of the frozen classifier export metadata.
  static let defaultThreshold: Double = 0.95
  static let defaultPersistence: Int = 2
  private static let frozenExportThreshold: Double = 0.9900000000000004
  private static let frozenExportPersistence: Int = 4

  private static let uncertaintyModel: ExportedTreeModel? = loadModel(named: "UncertaintyV3")
  private static let sufficiencyModel: ExportedTreeModel? = loadModel(named: "SufficiencyV3_2")
  private static let sufficiencyFeatureNames = ["predicted_coverage", "max_distance_fraction", "n_cpt", "site_width_m", "site_height_m", "site_diagonal_m", "site_area_m2", "mean_cpt_spacing_m", "max_nearest_distance_m", "aspect_ratio"]
  private static let uncertaintyFeatureNames = ["distance_to_cpt_m", "depth_m", "predicted_ic", "lateral_gradient", "vertical_gradient", "nearby_cpt_fraction_25m", "n_cpt", "dx_m", "dy_m", "dz_m"]

  private static func loadModel(named name: String) -> ExportedTreeModel? {
    guard
      let url = Bundle.main.url(forResource: name, withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let decoded = try? JSONDecoder().decode(ExportedTreeModel.self, from: data)
    else {
      return nil
    }
    return decoded
  }

  static func evaluate(
    reconstruction: SchemaGANReconstructionOutput,
    grid: CPTGridConfig,
    previousConsecutiveSufficientCount: Int,
    stratigraphicMode: Bool = false
  ) -> UncertaintySufficiencyEvaluation {
    let nx = grid.nx
    let ny = grid.ny
    let nz = grid.nz
    let dx = grid.dxM
    let dy = grid.dyM
    let dz = grid.dzM

    let rec = reconstruction.reconstructedIc
    let observed = reconstruction.observedMask
    let valid = reconstruction.validMask
    let sites = reconstruction.observedSitesXY
    let nCPT = max(sites.count, 1)

    // 1. Precompute 2D distance to nearest CPT and nearby fraction within 25m
    var distanceToCPT = Array(repeating: Array(repeating: 0.0, count: ny), count: nx)
    var nearbyFraction25m = Array(repeating: Array(repeating: 0.0, count: ny), count: nx)

    for ix in 0 ..< nx {
      let xM = Double(ix) * dx
      for iy in 0 ..< ny {
        let yM = Double(iy) * dy
        var minD = Double.greatestFiniteMagnitude
        var within25Count = 0
        for site in sites {
          let d = hypot(xM - Double(site.ix) * dx, yM - Double(site.iy) * dy)
          minD = min(minD, d)
          if d <= 25.0 {
            within25Count += 1
          }
        }
        let resolvedD = minD.isFinite ? minD : grid.siteDiagonalM
        distanceToCPT[ix][iy] = resolvedD
        nearbyFraction25m[ix][iy] = Double(within25Count) / Double(nCPT)
      }
    }

    // 2. Compute 3D gradients (grad_x, grad_y, grad_z) matching np.gradient(prediction, dx, dy, dz)
    let (lateralGrad, verticalGrad) = compute3DGradients(
      rec: rec,
      nx: nx,
      ny: ny,
      nz: nz,
      dx: dx,
      dy: dy,
      dz: dz,
      valid: stratigraphicMode ? valid : nil
    )

    // 3. Collect hidden valid voxels (valid & ~observed)
    var hiddenCoords: [(ix: Int, iy: Int, iz: Int)] = []
    hiddenCoords.reserveCapacity(nx * ny * nz)
    for ix in 0 ..< nx {
      for iy in 0 ..< ny {
        for iz in 0 ..< nz {
          if valid[ix][iy][iz], !observed[ix][iy][iz] {
            hiddenCoords.append((ix, iy, iz))
          }
        }
      }
    }

    // V3.2 research computes coverage across all hidden valid voxels.
    let sampledCoords = hiddenCoords

    // 4. Evaluate UncertaintyV3 across sampled hidden voxels
    var errorBounds: [Double] = []
    var rawBounds: [Double] = []
    var uncertaintyFeaturesFinite = true
    errorBounds.reserveCapacity(sampledCoords.count)

    let correction = uncertaintyModel?.calibrationCorrection ?? 0.0030156622852133743

#if UNCERTAINTY_V3_PARITY_HARNESS
    parityFeatures = []; parityRawBounds = []; parityFinalBounds = []; parityCoordinates = []
    parityCorrection = uncertaintyModel?.calibrationCorrection
    parityModelLoaded = uncertaintyModel != nil
#endif

    for coord in sampledCoords {
      let features: [Double] = [
        distanceToCPT[coord.ix][coord.iy],
        Double(coord.iz) * dz,
        rec[coord.ix][coord.iy][coord.iz],
        lateralGrad[coord.ix][coord.iy][coord.iz],
        verticalGrad[coord.ix][coord.iy][coord.iz],
        nearbyFraction25m[coord.ix][coord.iy],
        Double(nCPT),
        dx,
        dy,
        dz
      ]
      if !features.allSatisfy(\.isFinite) { uncertaintyFeaturesFinite = false }

      let bound: Double
      let rawBound: Double
      if let uModel = uncertaintyModel {
        let raw = predictTreeEnsemble(features: features, model: uModel)
        rawBound = raw
        bound = max(0.0, raw) + correction
      } else {
        // Fallback analytical bound if JSON not loaded
        let distFactor = min(distanceToCPT[coord.ix][coord.iy] / max(grid.siteDiagonalM, 1.0), 1.0)
        bound = 0.08 + 0.14 * distFactor / sqrt(Double(nCPT))
        rawBound = bound - correction
      }
      errorBounds.append(bound)
      rawBounds.append(rawBound)
#if UNCERTAINTY_V3_PARITY_HARNESS
      parityFeatures.append(features)
      parityRawBounds.append(rawBound)
      parityFinalBounds.append(bound)
      parityCoordinates.append([coord.ix, coord.iy, coord.iz])
#endif
    }

    let meanBound: Double
    if errorBounds.isEmpty {
      meanBound = 0.05
    } else {
      meanBound = errorBounds.reduce(0.0, +) / Double(errorBounds.count)
    }

    let featureVector = v32Features(nx: nx, ny: ny, nz: nz, dx: dx, dy: dy,
      valid: valid, observed: observed, sites: sites, rawBounds: rawBounds, correction: correction)
    let sufficiencyFeatures = featureVector ?? []
    let predictedCoverage = featureVector?.first ?? 0

    let pSufficient: Double
    let uncertaintyInputsValid = reconstruction.inferenceSource == "SchemaGAN V4.2 Flexible Core ML" &&
      !sites.isEmpty && uncertaintyFeaturesFinite && uncertaintyModel?.featureNames == uncertaintyFeatureNames &&
      uncertaintyModel?.modelType == "histGradientBoostingRegressor" &&
      uncertaintyModel?.calibrationCorrection != nil && errorBounds.allSatisfy(\.isFinite)
    let modelInputsValid = uncertaintyInputsValid && sufficiencyModel?.featureNames == sufficiencyFeatureNames &&
      sufficiencyModel?.modelType == "histGradientBoostingBinaryClassifier" &&
      sufficiencyModel?.probabilityThreshold == frozenExportThreshold &&
      sufficiencyModel?.persistence == frozenExportPersistence && featureVector != nil && sufficiencyFeatures.allSatisfy(\.isFinite)
    if modelInputsValid, let sModel = sufficiencyModel {
      let rawLogit = predictTreeEnsemble(features: sufficiencyFeatures, model: sModel)
      pSufficient = sigmoid(rawLogit)
    } else {
      pSufficient = 0
    }

    let threshold = defaultThreshold
    let requiredPersistence = defaultPersistence

    // Existing projects do not record DQN policy/trajectory provenance; 10%-diagonal
    // compatibility therefore cannot be established. Never turn this into STOP.
    let trajectoryCompatible = false
    let isCurrentStepPositive = modelInputsValid && trajectoryCompatible && pSufficient >= threshold
    let updatedConsecutive = isCurrentStepPositive ? (previousConsecutiveSufficientCount + 1) : 0
    let isSufficient = updatedConsecutive >= requiredPersistence
    // No grid configuration is approved for automatic decisions until its
    // provenance and runtime feature parity are verified.
    let inResearchDomain = false
    let assessmentStatus = CPTAssessmentStatus.classify(modelValid: modelInputsValid && pSufficient.isFinite,
      trajectoryCompatible: trajectoryCompatible, inResearchDomain: inResearchDomain, isSufficient: isSufficient)


    // Map confidence percentage for UI display (combining predicted coverage & sufficiency probability)
    let blendedConfidence = max(predictedCoverage, pSufficient * 0.95)
    let confidencePercent = min(max(Int((blendedConfidence * 100.0).rounded()), 15), 99)

    var spatialBounds = Array(repeating: Array(repeating: Array(repeating: 0.0, count: nz), count: ny), count: nx)
    for (i, c) in sampledCoords.enumerated() { spatialBounds[c.ix][c.iy][c.iz] = errorBounds[i] }
    return UncertaintySufficiencyEvaluation(
      inferenceSource: !modelInputsValid
        ? "Sufficiency V3.2 unavailable: model or reconstruction invalid" : "Sufficiency V3.2 experimental; STOP unavailable: DQN trajectory not verified",
      estimatedRMSE: meanBound,
      predictedCoverage: predictedCoverage,
      sufficiencyProbability: pSufficient,
      confidenceLevelPercent: isSufficient ? max(confidencePercent, 98) : confidencePercent,
      consecutiveSufficientCount: updatedConsecutive,
      isSufficient: isSufficient,
      assessmentStatus: assessmentStatus,
      spatialBounds: spatialBounds,
      spatialEvidenceValid: uncertaintyInputsValid && !hiddenCoords.isEmpty
    )
  }

  /// Evaluates the local prediction confidence (0–100%) specifically at the recommended candidate column `(ix, iy)`
  /// by running `UncertaintyV3` across all depth layers `0 ..< nz` at that coordinate.
  static func evaluateSpotConfidence(
    reconstruction: SchemaGANReconstructionOutput,
    grid: CPTGridConfig,
    ix: Int,
    iy: Int
  ) -> Int {
    let nx = grid.nx
    let ny = grid.ny
    let nz = grid.nz
    let dx = grid.dxM
    let dy = grid.dyM
    let dz = grid.dzM

    let clampedX = min(max(ix, 0), max(nx - 1, 0))
    let clampedY = min(max(iy, 0), max(ny - 1, 0))

    let rec = reconstruction.reconstructedIc
    let valid = reconstruction.validMask
    let sites = reconstruction.observedSitesXY
    let nCPT = max(sites.count, 1)

    let xM = Double(clampedX) * dx
    let yM = Double(clampedY) * dy
    var minD = Double.greatestFiniteMagnitude
    var within25Count = 0
    for site in sites {
      let d = hypot(xM - Double(site.ix) * dx, yM - Double(site.iy) * dy)
      minD = min(minD, d)
      if d <= 25.0 {
        within25Count += 1
      }
    }
    let distToNearestM = minD.isFinite ? minD : grid.siteDiagonalM
    let nearbyFrac25m = Double(within25Count) / Double(nCPT)

    let (lateralGrad, verticalGrad) = compute3DGradients(
      rec: rec,
      nx: nx,
      ny: ny,
      nz: nz,
      dx: dx,
      dy: dy,
      dz: dz
    )

    let correction = uncertaintyModel?.calibrationCorrection ?? 0.0030156622852133743
    var columnBounds: [Double] = []
    columnBounds.reserveCapacity(nz)

    for iz in 0 ..< nz where valid[clampedX][clampedY][iz] {
      let features: [Double] = [
        distToNearestM,
        Double(iz) * dz,
        rec[clampedX][clampedY][iz],
        lateralGrad[clampedX][clampedY][iz],
        verticalGrad[clampedX][clampedY][iz],
        nearbyFrac25m,
        Double(nCPT),
        dx,
        dy,
        dz
      ]

      let bound: Double
      if let uModel = uncertaintyModel {
        let raw = predictTreeEnsemble(features: features, model: uModel)
        bound = max(0.0, raw) + correction
      } else {
        let distFactor = min(distToNearestM / max(grid.siteDiagonalM, 1.0), 1.0)
        bound = 0.08 + 0.14 * distFactor / sqrt(Double(nCPT))
      }
      columnBounds.append(bound)
    }

    guard !columnBounds.isEmpty else {
      return 60
    }

    let meanColumnBound = columnBounds.reduce(0.0, +) / Double(columnBounds.count)
    let localCoverage = Double(columnBounds.filter { $0 <= icTolerance }.count) / Double(columnBounds.count)
    let boundScore = min(max(1.0 - (meanColumnBound / 0.35), 0.0), 1.0)
    let distanceFactor = exp(-distToNearestM / max(grid.siteDiagonalM * 0.85, 20.0))

    let blendedSpotConfidence = 0.55 * boundScore + 0.25 * localCoverage + 0.20 * distanceFactor
    return min(max(Int((blendedSpotConfidence * 100.0).rounded()), 15), 95)
  }

  private static func predictTreeEnsemble(
    features: [Double],
    model: ExportedTreeModel
  ) -> Double {
    var sum = model.baseline
    for tree in model.trees {
      guard !tree.isEmpty else { continue }
      var nodeIdx = 0
      while nodeIdx >= 0, nodeIdx < tree.count {
        let node = tree[nodeIdx]
        if node.isLeaf {
          sum += node.value
          break
        }
        let fIdx = node.featureIndex
        let fVal = (fIdx >= 0 && fIdx < features.count) ? features[fIdx] : .nan
        let goLeft: Bool
        if fVal.isNaN {
          goLeft = node.missingGoToLeft
        } else {
          goLeft = fVal <= node.threshold
        }
        nodeIdx = goLeft ? node.left : node.right
      }
    }
    return sum
  }

  private static func sigmoid(_ x: Double) -> Double {
    if x >= 0 {
      let z = exp(-x)
      return 1.0 / (1.0 + z)
    } else {
      let z = exp(x)
      return z / (1.0 + z)
    }
  }

#if DEBUG
  static func v32ParityProbability(modelURL: URL, features: [Double]) throws -> Double {
    let model = try JSONDecoder().decode(ExportedTreeModel.self, from: Data(contentsOf: modelURL))
    guard model.featureNames == sufficiencyFeatureNames, features.count == 10 else {
      throw NSError(domain: "SufficiencyV32Parity", code: 1)
    }
    return sigmoid(predictTreeEnsemble(features: features, model: model))
  }
#endif

  private static func compute3DGradients(
    rec: [[[Double]]],
    nx: Int,
    ny: Int,
    nz: Int,
    dx: Double,
    dy: Double,
    dz: Double,
    valid: [[[Bool]]]? = nil
  ) -> (lateral: [[[Double]]], vertical: [[[Double]]]) {
    var lateral = Array(
      repeating: Array(repeating: Array(repeating: 0.0, count: nz), count: ny),
      count: nx
    )
    var vertical = Array(
      repeating: Array(repeating: Array(repeating: 0.0, count: nz), count: ny),
      count: nx
    )

    for ix in 0 ..< nx {
      for iy in 0 ..< ny {
        for iz in 0 ..< nz {
          if let mask = valid {
            guard mask[ix][iy][iz] else { continue }
            func derivative(_ axis: Int, _ step: Double) -> Double {
              var plus=[ix,iy,iz], minus=plus; plus[axis]+=1; minus[axis]-=1
              let dims=[nx,ny,nz]
              let p=plus[axis]<dims[axis] && mask[plus[0]][plus[1]][plus[2]]
              let m=minus[axis]>=0 && mask[minus[0]][minus[1]][minus[2]]
              let center=rec[ix][iy][iz]
              if p && m { return (rec[plus[0]][plus[1]][plus[2]]-rec[minus[0]][minus[1]][minus[2]])/(2*step) }
              if p { return (rec[plus[0]][plus[1]][plus[2]]-center)/step }
              if m { return (center-rec[minus[0]][minus[1]][minus[2]])/step }
              return 0
            }
            lateral[ix][iy][iz]=hypot(derivative(0,dx),derivative(1,dy)); vertical[ix][iy][iz]=abs(derivative(2,dz))
            continue
          }
          let gx: Double
          if nx == 1 {
            gx = 0.0
          } else if ix == 0 {
            gx = (rec[1][iy][iz] - rec[0][iy][iz]) / dx
          } else if ix == nx - 1 {
            gx = (rec[nx - 1][iy][iz] - rec[nx - 2][iy][iz]) / dx
          } else {
            gx = (rec[ix + 1][iy][iz] - rec[ix - 1][iy][iz]) / (2.0 * dx)
          }

          let gy: Double
          if ny == 1 {
            gy = 0.0
          } else if iy == 0 {
            gy = (rec[ix][1][iz] - rec[ix][0][iz]) / dy
          } else if iy == ny - 1 {
            gy = (rec[ix][ny - 1][iz] - rec[ix][ny - 2][iz]) / dy
          } else {
            gy = (rec[ix][iy + 1][iz] - rec[ix][iy - 1][iz]) / (2.0 * dy)
          }

          let gz: Double
          if nz == 1 {
            gz = 0.0
          } else if iz == 0 {
            gz = (rec[ix][iy][1] - rec[ix][iy][0]) / dz
          } else if iz == nz - 1 {
            gz = (rec[ix][iy][nz - 1] - rec[ix][iy][nz - 2]) / dz
          } else {
            gz = (rec[ix][iy][iz + 1] - rec[ix][iy][iz - 1]) / (2.0 * dz)
          }

          lateral[ix][iy][iz] = hypot(gx, gy)
          vertical[ix][iy][iz] = abs(gz)
        }
      }
    }

    return (lateral, vertical)
  }
}

