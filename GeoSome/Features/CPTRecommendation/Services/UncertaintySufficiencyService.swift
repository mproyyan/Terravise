import Foundation

struct UncertaintySufficiencyEvaluation: Sendable {
  let estimatedRMSE: Double
  let predictedCoverage: Double
  let sufficiencyProbability: Double
  let confidenceLevelPercent: Int
  let consecutiveSufficientCount: Int
  let isSufficient: Bool
}

enum UncertaintySufficiencyService {
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
  static let defaultThreshold: Double = 0.98
  static let defaultPersistence: Int = 3

  private static let uncertaintyModel: ExportedTreeModel? = loadModel(named: "UncertaintyV3")
  private static let sufficiencyModel: ExportedTreeModel? = loadModel(named: "SufficiencyV3_1")

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
    previousConsecutiveSufficientCount: Int
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
    var maxNearestDistanceM = 0.0

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
        if grid.validXYMask[ix][iy] {
          maxNearestDistanceM = max(maxNearestDistanceM, resolvedD)
        }
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
      dz: dz
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

    // Subsample deterministically up to 512 voxels for fast, consistent evaluation
    let maxSamples = 512
    let sampledCoords: [(ix: Int, iy: Int, iz: Int)]
    if hiddenCoords.count <= maxSamples {
      sampledCoords = hiddenCoords
    } else {
      let step = Double(hiddenCoords.count) / Double(maxSamples)
      sampledCoords = (0 ..< maxSamples).map { i in
        hiddenCoords[min(Int(Double(i) * step), hiddenCoords.count - 1)]
      }
    }

    // 4. Evaluate UncertaintyV3 across sampled hidden voxels
    var errorBounds: [Double] = []
    errorBounds.reserveCapacity(sampledCoords.count)

    let correction = uncertaintyModel?.calibrationCorrection ?? 0.0030156622852133743

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

      let bound: Double
      if let uModel = uncertaintyModel {
        let raw = predictTreeEnsemble(features: features, model: uModel)
        bound = max(0.0, raw) + correction
      } else {
        // Fallback analytical bound if JSON not loaded
        let distFactor = min(distanceToCPT[coord.ix][coord.iy] / max(grid.siteDiagonalM, 1.0), 1.0)
        bound = 0.08 + 0.14 * distFactor / sqrt(Double(nCPT))
      }
      errorBounds.append(bound)
    }

    let meanBound: Double
    let coveredCount: Int
    if errorBounds.isEmpty {
      meanBound = 0.05
      coveredCount = 1
    } else {
      meanBound = errorBounds.reduce(0.0, +) / Double(errorBounds.count)
      coveredCount = errorBounds.filter { $0 <= icTolerance }.count
    }

    let predictedCoverage = errorBounds.isEmpty
      ? 1.0
      : (Double(coveredCount) / Double(errorBounds.count))

    // 5. Compute mean CPT spacing for SufficiencyV3_1
    let meanCPTSpacingM: Double
    if sites.count <= 1 {
      meanCPTSpacingM = grid.siteDiagonalM
    } else {
      var nearestSiteDistances: [Double] = []
      for i in sites.indices {
        var minOther = Double.greatestFiniteMagnitude
        for j in sites.indices where i != j {
          let d = hypot(
            Double(sites[i].ix - sites[j].ix) * dx,
            Double(sites[i].iy - sites[j].iy) * dy
          )
          minOther = min(minOther, d)
        }
        if minOther.isFinite {
          nearestSiteDistances.append(minOther)
        }
      }
      meanCPTSpacingM = nearestSiteDistances.isEmpty
        ? grid.siteDiagonalM
        : (nearestSiteDistances.reduce(0.0, +) / Double(nearestSiteDistances.count))
    }

    let maxDistanceFraction = maxNearestDistanceM / max(grid.siteDiagonalM, 1e-6)

    // 10 features for SufficiencyV3_1:
    // ["predicted_coverage","max_distance_fraction","n_cpt","site_width_m","site_height_m",
    //  "site_diagonal_m","site_area_m2","mean_cpt_spacing_m","max_nearest_distance_m","aspect_ratio"]
    let sufficiencyFeatures: [Double] = [
      predictedCoverage,
      maxDistanceFraction,
      Double(nCPT),
      grid.siteWidthM,
      grid.siteHeightM,
      grid.siteDiagonalM,
      grid.siteAreaM2,
      meanCPTSpacingM,
      maxNearestDistanceM,
      grid.aspectRatio
    ]

    let pSufficient: Double
    if let sModel = sufficiencyModel {
      let rawLogit = predictTreeEnsemble(features: sufficiencyFeatures, model: sModel)
      pSufficient = sigmoid(rawLogit)
    } else {
      pSufficient = predictedCoverage
    }

    let threshold = sufficiencyModel?.probabilityThreshold ?? defaultThreshold
    let requiredPersistence = sufficiencyModel?.persistence ?? defaultPersistence

    let isCurrentStepPositive = pSufficient >= threshold
    let updatedConsecutive = isCurrentStepPositive ? (previousConsecutiveSufficientCount + 1) : 0
    let isSufficient = updatedConsecutive >= requiredPersistence

    // Map confidence percentage for UI display (combining predicted coverage & sufficiency probability)
    let blendedConfidence = max(predictedCoverage, pSufficient * 0.95)
    let confidencePercent = min(max(Int((blendedConfidence * 100.0).rounded()), 15), 99)

    return UncertaintySufficiencyEvaluation(
      estimatedRMSE: meanBound,
      predictedCoverage: predictedCoverage,
      sufficiencyProbability: pSufficient,
      confidenceLevelPercent: isSufficient ? max(confidencePercent, 98) : confidencePercent,
      consecutiveSufficientCount: updatedConsecutive,
      isSufficient: isSufficient
    )
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

  private static func compute3DGradients(
    rec: [[[Double]]],
    nx: Int,
    ny: Int,
    nz: Int,
    dx: Double,
    dy: Double,
    dz: Double
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

