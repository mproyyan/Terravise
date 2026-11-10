import CoreML
import Foundation

struct DQNCandidateEvaluation: Sendable {
  let ix: Int
  let iy: Int
  let qValue: Double
  let nearestCPTDistanceM: Double
  let nearbyCountWithin4m: Int
  let shallowSoilType: String
  let deepSoilType: String
  let lateralIcDifference: Double
}

enum DQNFeatureBuilder {
  static let featureCount = 29
  static let candidateFeatureCount = 18
  static let globalFeatureCount = 11

  static func recommendNextCandidate(
    reconstruction: SchemaGANReconstructionOutput,
    grid: CPTGridConfig
  ) -> DQNCandidateEvaluation? {
    let nx = grid.nx
    let ny = grid.ny
    let nz = grid.nz
    let dx = grid.dxM
    let dy = grid.dyM
    let dz = grid.dzM
    let mean = SchemaGANService.normalizationMean
    let std = SchemaGANService.normalizationStd

    let rec = reconstruction.reconstructedIc
    let observed = reconstruction.observedMask
    let valid = reconstruction.validMask

    // 1. Standardized reconstruction zrec = (rec - mean) / std
    var zrec = Array(
      repeating: Array(repeating: Array(repeating: 0.0, count: nz), count: ny),
      count: nx
    )
    var observedXY = Array(repeating: Array(repeating: false, count: ny), count: nx)
    var validXY = Array(repeating: Array(repeating: false, count: ny), count: nx)

    var allValidZRec: [Double] = []
    var totalValidVoxels = 0
    var observedValidVoxels = 0

    for ix in 0 ..< nx {
      for iy in 0 ..< ny {
        for iz in 0 ..< nz {
          let zVal = (rec[ix][iy][iz] - mean) / std
          zrec[ix][iy][iz] = zVal
          if valid[ix][iy][iz] {
            validXY[ix][iy] = true
            allValidZRec.append(zVal)
            totalValidVoxels += 1
            if observed[ix][iy][iz] {
              observedValidVoxels += 1
            }
          }
          if observed[ix][iy][iz] {
            observedXY[ix][iy] = true
          }
        }
      }
    }

    // 2. Legal candidates: valid.any(z) AND !observedXY AND inside boundary polygon
    var legalCandidates: [(ix: Int, iy: Int)] = []
    for ix in 0 ..< nx {
      for iy in 0 ..< ny {
        if validXY[ix][iy], !observedXY[ix][iy], grid.validXYMask[ix][iy] {
          legalCandidates.append((ix, iy))
        }
      }
    }

    guard !legalCandidates.isEmpty else {
      return nil
    }

    // 3. Lateral Ic gradient map [nx][ny]
    let gradientMap = computeLateralIcGradient(rec: rec, valid: valid, grid: grid)

    // 4. Global 11 context features
    let nSites = reconstruction.observedSitesXY.count
    let possibleSites = validXY.flatMap { $0 }.filter { $0 }.count
    let (globalMeanZ, globalStdZ) = meanAndStd(allValidZRec)
    let totalVoxels = max(nx * ny * nz, 1)

    let globalContext: [Float] = [
      Float(log1p(Double(nSites)) / max(log1p(Double(possibleSites)), 1e-6)),
      Float(log1p((Double(nx) * dx) / 32.0)),
      Float(log1p((Double(ny) * dy) / 32.0)),
      Float(log1p((Double(nz) * dz) / 16.0)),
      Float(log1p(dx / 2.0)),
      Float(log1p(dy / 2.0)),
      Float(log1p(dz / 2.0)),
      Float(globalMeanZ),
      Float(globalStdZ),
      Float(Double(totalValidVoxels) / Double(totalVoxels)),
      Float(Double(observedValidVoxels) / Double(max(totalValidVoxels, 1)))
    ]

    let diagonal = hypot(Double(nx) * dx, Double(ny) * dy)
    let localRadius = max(4.0, 2.0 * max(dx, dy))
    let depthBins = splitIndices(count: nz, parts: 4)

    var allFeatureRows: [[Float]] = []
    allFeatureRows.reserveCapacity(legalCandidates.count)

    struct CandidateMetadata {
      let nearestDistanceM: Double
      let countWithin4m: Int
      let shallowSoil: String
      let deepSoil: String
      let lateralDiffIc: Double
    }
    var metadataList: [CandidateMetadata] = []
    metadataList.reserveCapacity(legalCandidates.count)

    for (cx, cy) in legalCandidates {
      let cXM = Double(cx) * dx
      let cYM = Double(cy) * dy

      // Distance to observed CPT sites
      var minSiteDist = Double.greatestFiniteMagnitude
      var countWithin4m = 0
      for site in reconstruction.observedSitesXY {
        let d = hypot(cXM - Double(site.ix) * dx, cYM - Double(site.iy) * dy)
        minSiteDist = min(minSiteDist, d)
        if d <= 4.0 + 1e-9 {
          countWithin4m += 1
        }
      }
      if !minSiteDist.isFinite {
        minSiteDist = diagonal
      }

      // Neighborhood cells within localRadius
      var neighborhoodCells: [(Int, Int)] = []
      var surroundingCells: [(Int, Int)] = []
      var observedInNeighborhood = 0

      for ix in 0 ..< nx {
        let xM = Double(ix) * dx
        for iy in 0 ..< ny {
          let yM = Double(iy) * dy
          let dist = hypot(xM - cXM, yM - cYM)
          if dist <= localRadius + 1e-9 {
            neighborhoodCells.append((ix, iy))
            if observedXY[ix][iy] {
              observedInNeighborhood += 1
            }
            if !(ix == cx && iy == cy) {
              surroundingCells.append((ix, iy))
            }
          }
        }
      }

      // Local surrounding valid & zrec values (excluding candidate itself unless surrounding has no valid cells)
      let useSurrounding = surroundingCells.contains { validXY[$0.0][$0.1] }
      let refCells = useSurrounding ? surroundingCells : neighborhoodCells

      var localZRecValues: [Double] = []
      var localPhysicalIcValues: [Double] = []
      var localValidCount = 0
      let localTotalVoxels = max(refCells.count * nz, 1)

      for (rx, ry) in refCells {
        for iz in 0 ..< nz {
          if valid[rx][ry][iz] {
            localValidCount += 1
            localZRecValues.append(zrec[rx][ry][iz])
            localPhysicalIcValues.append(rec[rx][ry][iz])
          }
        }
      }

      let localMeanZ = localZRecValues.isEmpty
        ? 0.0
        : (localZRecValues.reduce(0.0, +) / Double(localZRecValues.count))
      let localValidFraction = Double(localValidCount) / Double(localTotalVoxels)

      // Candidate profile along Z
      var profileZRec: [Double] = []
      var profilePhysicalIc: [Double] = []
      for iz in 0 ..< nz where valid[cx][cy][iz] {
        profileZRec.append(zrec[cx][cy][iz])
        profilePhysicalIc.append(rec[cx][cy][iz])
      }
      let validDepthFraction = Double(profileZRec.count) / Double(max(nz, 1))
      let (profileMeanZ, profileStdZ) = meanAndStd(profileZRec)

      // 4 Depth bins
      var binMeans: [Float] = []
      var binEmpty: [Float] = []
      var physicalBinMeans: [Double] = []

      for binIndices in depthBins {
        var vals: [Double] = []
        var physVals: [Double] = []
        for iz in binIndices where valid[cx][cy][iz] {
          vals.append(zrec[cx][cy][iz])
          physVals.append(rec[cx][cy][iz])
        }
        if vals.isEmpty {
          binEmpty.append(1.0)
          binMeans.append(0.0)
          physicalBinMeans.append(mean)
        } else {
          binEmpty.append(0.0)
          let m = vals.reduce(0.0, +) / Double(vals.count)
          binMeans.append(Float(m))
          physicalBinMeans.append(physVals.reduce(0.0, +) / Double(physVals.count))
        }
      }

      let candidateFeatures: [Float] = [
        Float(Double(cx) / Double(max(nx - 1, 1))),
        Float(Double(cy) / Double(max(ny - 1, 1))),
        Float(min(minSiteDist / max(diagonal, 1e-6), 1.0)),
        Float(Double(observedInNeighborhood) / Double(max(neighborhoodCells.count, 1))),
        Float(validDepthFraction),
        Float(profileMeanZ),
        Float(profileStdZ),
        binMeans[0],
        binMeans[1],
        binMeans[2],
        binMeans[3],
        binEmpty[0],
        binEmpty[1],
        binEmpty[2],
        binEmpty[3],
        Float(localMeanZ),
        Float(localValidFraction),
        Float(gradientMap[cx][cy] / max(std, 1e-6))
      ]

      allFeatureRows.append(candidateFeatures + globalContext)

      let shallowIc = (physicalBinMeans[0] + physicalBinMeans[1]) * 0.5
      let deepIc = (physicalBinMeans[2] + physicalBinMeans[3]) * 0.5
      let candidatePhysMean = profilePhysicalIc.isEmpty
        ? mean
        : (profilePhysicalIc.reduce(0.0, +) / Double(profilePhysicalIc.count))
      let surroundingPhysMean = localPhysicalIcValues.isEmpty
        ? mean
        : (localPhysicalIcValues.reduce(0.0, +) / Double(localPhysicalIcValues.count))

      metadataList.append(
        CandidateMetadata(
          nearestDistanceM: minSiteDist,
          countWithin4m: countWithin4m,
          shallowSoil: CPTRowData.soilBehaviorType(forIc: shallowIc),
          deepSoil: CPTRowData.soilBehaviorType(forIc: deepIc),
          lateralDiffIc: abs(candidatePhysMean - surroundingPhysMean)
        )
      )
    }

    // 5. Run DQN V4.6-A CoreML inference
    let qScores = runDQNCoreML(featureRows: allFeatureRows)

    // 6. Select argmax Q among legal candidates (preferring candidates >= max(dx, dy) from existing CPTs)
    let minSeparationM = max(min(dx, dy), 2.0)
    let separatedIndices = legalCandidates.indices.filter {
      metadataList[$0].nearestDistanceM >= minSeparationM
    }
    let poolIndices = separatedIndices.isEmpty ? Array(legalCandidates.indices) : separatedIndices

    let bestIndex = poolIndices.min { i, j in
      let qi = qScores[i]
      let qj = qScores[j]
      if abs(qi - qj) > 1e-9 {
        return qi > qj
      }
      if legalCandidates[i].ix != legalCandidates[j].ix {
        return legalCandidates[i].ix < legalCandidates[j].ix
      }
      return legalCandidates[i].iy < legalCandidates[j].iy
    } ?? 0

    let chosen = legalCandidates[bestIndex]
    let meta = metadataList[bestIndex]

    return DQNCandidateEvaluation(
      ix: chosen.ix,
      iy: chosen.iy,
      qValue: qScores[bestIndex],
      nearestCPTDistanceM: meta.nearestDistanceM,
      nearbyCountWithin4m: meta.countWithin4m,
      shallowSoilType: meta.shallowSoil,
      deepSoilType: meta.deepSoil,
      lateralIcDifference: meta.lateralDiffIc
    )
  }

  private static func runDQNCoreML(featureRows: [[Float]]) -> [Double] {
    let count = featureRows.count
    guard count > 0 else { return [] }

    // CoreML DQN_V4_6_A accepts [1...4096, 29]
    let batchCount = min(count, 4096)
    let shape: [NSNumber] = [NSNumber(value: batchCount), NSNumber(value: featureCount)]

    if let inputArray = try? MLMultiArray(shape: shape, dataType: .float32) {
      let strides = inputArray.strides.map(\.intValue)
      let ptr = inputArray.dataPointer.bindMemory(to: Float.self, capacity: inputArray.count)

      for i in 0 ..< batchCount {
        let row = featureRows[i]
        for f in 0 ..< featureCount {
          let val = row[f]
          ptr[i * strides[0] + f * strides[1]] = val.isFinite ? val : 0.0
        }
      }

      let config = MLModelConfiguration()
      config.computeUnits = .all
      if let model = try? DQN_V4_6_A(configuration: config),
         let output = try? model.prediction(features: inputArray)
      {
        let qArray = output.q_values
        let qPtr = qArray.dataPointer.bindMemory(to: Float.self, capacity: qArray.count)
        var scores = Array(repeating: -Double.greatestFiniteMagnitude, count: count)
        let outCount = min(batchCount, qArray.count)
        for i in 0 ..< outCount {
          scores[i] = Double(qPtr[i])
        }
        return scores
      }
    }

    // Fallback heuristic score if CoreML is unavailable in preview
    return featureRows.map { row in
      let distFrac = Double(row[2])
      let stdZ = Double(row[6])
      let grad = Double(row[17])
      return distFrac * 0.6 + stdZ * 0.2 + grad * 0.2
    }
  }

  /// Exact port of `lateral_ic_gradient` from `geological_features.py`.
  static func computeLateralIcGradient(
    rec: [[[Double]]],
    valid: [[[Bool]]],
    grid: CPTGridConfig
  ) -> [[Double]] {
    let nx = grid.nx
    let ny = grid.ny
    let nz = grid.nz
    let dx = grid.dxM
    let dy = grid.dyM

    var meanIc = Array(repeating: Array(repeating: 0.0, count: ny), count: nx)
    var validXY = Array(repeating: Array(repeating: false, count: ny), count: nx)

    for ix in 0 ..< nx {
      for iy in 0 ..< ny {
        var sum = 0.0
        var count = 0
        for iz in 0 ..< nz where valid[ix][iy][iz] {
          sum += rec[ix][iy][iz]
          count += 1
        }
        if count > 0 {
          meanIc[ix][iy] = sum / Double(count)
          validXY[ix][iy] = true
        }
      }
    }

    var gx = Array(repeating: Array(repeating: 0.0, count: ny), count: nx)
    var gy = Array(repeating: Array(repeating: 0.0, count: ny), count: nx)
    var weightX = Array(repeating: Array(repeating: 0.0, count: ny), count: nx)
    var weightY = Array(repeating: Array(repeating: 0.0, count: ny), count: nx)

    for ix in 0 ..< (nx - 1) {
      for iy in 0 ..< ny {
        if validXY[ix][iy], validXY[ix + 1][iy] {
          let absX = abs(meanIc[ix + 1][iy] - meanIc[ix][iy]) / dx
          gx[ix][iy] += absX
          gx[ix + 1][iy] += absX
          weightX[ix][iy] += 1.0
          weightX[ix + 1][iy] += 1.0
        }
      }
    }

    for ix in 0 ..< nx {
      for iy in 0 ..< (ny - 1) {
        if validXY[ix][iy], validXY[ix][iy + 1] {
          let absY = abs(meanIc[ix][iy + 1] - meanIc[ix][iy]) / dy
          gy[ix][iy] += absY
          gy[ix][iy + 1] += absY
          weightY[ix][iy] += 1.0
          weightY[ix][iy + 1] += 1.0
        }
      }
    }

    var gradient = Array(repeating: Array(repeating: 0.0, count: ny), count: nx)
    for ix in 0 ..< nx {
      for iy in 0 ..< ny where validXY[ix][iy] {
        let vx = weightX[ix][iy] > 0 ? (gx[ix][iy] / weightX[ix][iy]) : 0.0
        let vy = weightY[ix][iy] > 0 ? (gy[ix][iy] / weightY[ix][iy]) : 0.0
        gradient[ix][iy] = hypot(vx, vy)
      }
    }

    return gradient
  }

  private static func splitIndices(count: Int, parts: Int) -> [[Int]] {
    guard parts > 0 else { return [] }
    let base = count / parts
    let rem = count % parts
    var result: [[Int]] = []
    var start = 0
    for p in 0 ..< parts {
      let size = base + (p < rem ? 1 : 0)
      let end = start + size
      result.append(Array(start ..< end))
      start = end
    }
    return result
  }

  private static func meanAndStd(_ values: [Double]) -> (mean: Double, std: Double) {
    guard !values.isEmpty else { return (0.0, 0.0) }
    let count = Double(values.count)
    let mean = values.reduce(0.0, +) / count
    var sumSq = 0.0
    for v in values {
      let d = v - mean
      sumSq += d * d
    }
    return (mean, sqrt(sumSq / count))
  }
}

