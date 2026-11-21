import CoreML
import CoreLocation
import Foundation

struct DQNCandidateEvaluation: Sendable {
  let inferenceSource: String
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
    grid: CPTGridConfig,
    cptCoordinates: [CLLocationCoordinate2D],
    boundaryCoordinates: [CLLocationCoordinate2D],
    minimumSeparationMeters: Double? = nil,
    unavailableReason: ((String) -> Void)? = nil,
    physicalCPTCoordinates: [CLLocationCoordinate2D]? = nil,
    physicalMinimumSeparationMeters: Double = 0,
    legalCandidateCount: ((Int) -> Void)? = nil
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

    // The default is one grid-cell diagonal, a sampling-resolution policy, not a geotechnical standard.
    let separation = minimumSeparationMeters ?? hypot(dx, dy)
    let physicalCoordinates = physicalCPTCoordinates ?? cptCoordinates
    guard physicalMinimumSeparationMeters.isFinite, physicalMinimumSeparationMeters>=0,
          !physicalCoordinates.isEmpty,physicalCoordinates.allSatisfy({$0.latitude.isFinite && $0.longitude.isFinite && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude)}),
          separation.isFinite, separation >= 0, !cptCoordinates.isEmpty,
          boundaryCoordinates.count >= 3 else { unavailableReason?("DQN_INVALID_CANDIDATE_INPUTS"); return nil }
    // 2. Apply boundary and distance legality using original, unsnapped CPT coordinates.
    var legalCandidates: [(ix: Int, iy: Int)] = []
    var physicallyPlaceableCandidates=0
    for ix in 0 ..< nx {
      for iy in 0 ..< ny {
        let coordinate = grid.coordinate(ix: ix, iy: iy)
        if validXY[ix][iy], !observedXY[ix][iy], grid.validXYMask[ix][iy],
           grid.contains(coordinate, in: boundaryCoordinates),
           physicalCoordinates.allSatisfy({grid.distanceMeters(from:coordinate,to:$0) >= physicalMinimumSeparationMeters && grid.distanceMeters(from:coordinate,to:$0)>0}) {
          physicallyPlaceableCandidates+=1
          if cptCoordinates.allSatisfy({ grid.distanceMeters(from: coordinate, to: $0) >= separation }) {
            legalCandidates.append((ix, iy))
          }
        }
      }
    }

    legalCandidateCount?(legalCandidates.count)
    guard !legalCandidates.isEmpty else {
      unavailableReason?(physicallyPlaceableCandidates==0 ? "DQN_NO_CANDIDATES_WITHIN_PHYSICAL_CONSTRAINTS" : "DQN_NO_LEGAL_CANDIDATES")
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
    guard let scoring = runDQNCoreML(featureRows: allFeatureRows) else { unavailableReason?("DQN_INFERENCE_UNAVAILABLE"); return nil }
    let qScores = scoring.values

    // Select the actual global argmax; ties use deterministic grid ordering.
    let bestIndex = legalCandidates.indices.min { i, j in
      let qi = qScores[i]
      let qj = qScores[j]
      if qi != qj {
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
      inferenceSource: scoring.source,
      ix: chosen.ix,
      iy: chosen.iy,
      qValue: qScores[bestIndex],
      nearestCPTDistanceM: cptCoordinates.map { grid.distanceMeters(from: grid.coordinate(ix: chosen.ix, iy: chosen.iy), to: $0) }.min() ?? 0,
      nearbyCountWithin4m: meta.countWithin4m,
      shallowSoilType: meta.shallowSoil,
      deepSoilType: meta.deepSoil,
      lateralIcDifference: meta.lateralDiffIc
    )
  }

  static func recommendWithAdaptiveSpacing(
    reconstruction:SchemaGANReconstructionOutput, grid:CPTGridConfig,
    cptCoordinates:[CLLocationCoordinate2D], physicalCPTCoordinates:[CLLocationCoordinate2D],
    boundaryCoordinates:[CLLocationCoordinate2D], normalMinimumM:Double, physicalMinimumM:Double,
    allowRelaxation:Bool, unavailableReason:((String)->Void)?=nil,
    spacingEvidence:((CPTCandidateSpacing)->Void)?=nil
  ) -> DQNCandidateEvaluation? {
    guard normalMinimumM.isFinite,normalMinimumM>=0,physicalMinimumM.isFinite,physicalMinimumM>0 else {
      unavailableReason?("DQN_INVALID_CANDIDATE_INPUTS");return nil
    }
    var minimum=max(normalMinimumM,physicalMinimumM)
    var evidence=CPTCandidateSpacing(normalMinimumM:normalMinimumM,physicalMinimumM:physicalMinimumM,
      attemptedMinimumM:[],legalCandidateCounts:[],usedMinimumM:minimum)
    while true {
      var reason="DQN_RECOMMENDATION_UNAVAILABLE",count=0
      let result=recommendNextCandidate(reconstruction:reconstruction,grid:grid,cptCoordinates:cptCoordinates,
        boundaryCoordinates:boundaryCoordinates,minimumSeparationMeters:minimum,unavailableReason:{reason=$0},
        physicalCPTCoordinates:physicalCPTCoordinates,physicalMinimumSeparationMeters:physicalMinimumM,
        legalCandidateCount:{count=$0})
      evidence.attemptedMinimumM.append(minimum);evidence.legalCandidateCounts.append(count);evidence.usedMinimumM=minimum
      if let result {spacingEvidence?(evidence);return result}
      guard allowRelaxation,reason=="DQN_NO_LEGAL_CANDIDATES" else {
        spacingEvidence?(evidence);unavailableReason?(reason);return nil
      }
      guard minimum>physicalMinimumM else {
        spacingEvidence?(evidence);unavailableReason?("DQN_NO_CANDIDATES_AFTER_SPACING_RELAXATION");return nil
      }
      minimum=max(physicalMinimumM,minimum*0.8)
    }
  }

  private static func runDQNCoreML(featureRows: [[Float]]) -> (values: [Double], source: String)? {
    let count = featureRows.count
    guard count > 0, featureRows.allSatisfy({ $0.count == featureCount && $0.allSatisfy(\.isFinite) }) else { return nil }

    // CoreML DQN_V4_6_A accepts [1...4096, 29]
    let batchCount = min(count, 4096)
    let shape: [NSNumber] = [NSNumber(value: batchCount), NSNumber(value: featureCount)]

    if let inputArray = try? MLMultiArray(shape: shape, dataType: .float32) {
      let strides = inputArray.strides.map(\.intValue)
      let ptr = inputArray.dataPointer.bindMemory(to: Float.self, capacity: inputArray.count)

      let config = MLModelConfiguration()
      config.computeUnits = .all
      if let model = try? DQN_V4_6_A(configuration: config) {
        var scores: [Double] = []
        for start in stride(from: 0, to: count, by: batchCount) {
          let actual = min(batchCount, count - start)
          for i in 0..<batchCount {
            let row = featureRows[start + min(i, actual - 1)]
            for f in 0..<featureCount { ptr[i * strides[0] + f * strides[1]] = row[f] }
          }
          guard let output = try? model.prediction(features: inputArray) else { return nil }
        let qArray = output.q_values
          guard qArray.count >= actual else { return nil }
        let qPtr = qArray.dataPointer.bindMemory(to: Float.self, capacity: qArray.count)
          for i in 0..<actual {
            let score = Double(qPtr[i])
            guard score.isFinite else { return nil }
            scores.append(score)
          }
        }
        return (scores, "DQN V4.6-A Core ML")
      }
    }

    return nil
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

