import CoreML
import Foundation

struct SchemaGANReconstructionOutput: Sendable {
  /// Reconstructed physical Robertson Ic volume [nx][ny][nz]
  let reconstructedIc: [[[Double]]]
  /// Observed physical Ic volume [nx][ny][nz]
  let observedIc: [[[Double]]]
  /// Boolean mask of observed voxels [nx][ny][nz]
  let observedMask: [[[Bool]]]
  /// Boolean mask of valid domain voxels [nx][ny][nz]
  let validMask: [[[Bool]]]
  /// Occupied (ix, iy) grid cells corresponding to uploaded CPTs
  let observedSitesXY: [(ix: Int, iy: Int)]
}

enum SchemaGANService {
  static let normalizationMean: Double = 2.7903323310879604
  static let normalizationStd: Double = 0.7723778445702414

  static func reconstruct(
    cptPoints: [CPTPointEntry],
    grid: CPTGridConfig
  ) -> SchemaGANReconstructionOutput {
    let nx = grid.nx
    let ny = grid.ny
    let nz = grid.nz
    let dx = grid.dxM
    let dy = grid.dyM
    let dz = grid.dzM

    var validXY = grid.validXYMask
    var observedIc = Array(
      repeating: Array(repeating: Array(repeating: 0.0, count: nz), count: ny),
      count: nx
    )
    var observedMask = Array(
      repeating: Array(repeating: Array(repeating: false, count: nz), count: ny),
      count: nx
    )

    var occupiedCells = Set<Int>()
    var sitesXY: [(ix: Int, iy: Int)] = []

    for point in cptPoints {
      let rawIdx = grid.gridIndices(for: point.coordinate)
      let (ix, iy) = resolveUniqueCell(
        preferredX: rawIdx.ix,
        preferredY: rawIdx.iy,
        nx: nx,
        ny: ny,
        validXY: validXY,
        occupied: occupiedCells
      )
      occupiedCells.insert(ix * ny + iy)
      validXY[ix][iy] = true
      sitesXY.append((ix, iy))

      let sourceRows = point.rows.isEmpty ? CPTRowData.sampleRows : point.rows
      let sortedRows = sourceRows.sorted { $0.depth < $1.depth }
      let depths = sortedRows.map(\.depth)
      let icValues = sortedRows.map(\.ic)

      let minDepth = depths.first ?? 0.0
      let maxDepth = depths.last ?? (Double(nz - 1) * dz)

      var hasAnyDepth = false
      for iz in 0 ..< nz {
        let z = Double(iz) * dz
        if z >= minDepth - (0.5 * dz) - 1e-6, z <= maxDepth + (0.5 * dz) + 1e-6 {
          let interpolatedIc = interpolate1D(x: z, xs: depths, ys: icValues)
          observedIc[ix][iy][iz] = interpolatedIc
          observedMask[ix][iy][iz] = true
          hasAnyDepth = true
        }
      }

      if !hasAnyDepth {
        let fallbackIc = icValues.first ?? normalizationMean
        observedIc[ix][iy][0] = fallbackIc
        observedMask[ix][iy][0] = true
      }
    }

    var validMask = Array(
      repeating: Array(repeating: Array(repeating: false, count: nz), count: ny),
      count: nx
    )
    for ix in 0 ..< nx {
      for iy in 0 ..< ny {
        if validXY[ix][iy] {
          for iz in 0 ..< nz {
            validMask[ix][iy][iz] = true
          }
        }
      }
    }

    // 1. Normalized sparse observations
    var sparse = Array(
      repeating: Array(repeating: Array(repeating: 0.0, count: nz), count: ny),
      count: nx
    )
    for ix in 0 ..< nx {
      for iy in 0 ..< ny {
        for iz in 0 ..< nz where observedMask[ix][iy][iz] {
          sparse[ix][iy][iz] = (observedIc[ix][iy][iz] - normalizationMean) / normalizationStd
        }
      }
    }

    // 2. 2D Euclidean distance from each grid cell to each observed site
    var siteDistances: [[[Double]]] = [] // [k][nx][ny]
    for site in sitesXY {
      var distMap = Array(repeating: Array(repeating: 0.0, count: ny), count: nx)
      let sx = Double(site.ix) * dx
      let sy = Double(site.iy) * dy
      for ix in 0 ..< nx {
        let x = Double(ix) * dx
        for iy in 0 ..< ny {
          let y = Double(iy) * dy
          distMap[ix][iy] = hypot(x - sx, y - sy)
        }
      }
      siteDistances.append(distMap)
    }

    // 3. Depth-aware Inverse Distance Weighting (IDW)
    var idw = Array(
      repeating: Array(repeating: Array(repeating: 0.0, count: nz), count: ny),
      count: nx
    )
    var activeZIndices: [Int] = []

    for iz in 0 ..< nz {
      var activeSiteIndices: [Int] = []
      for (k, site) in sitesXY.enumerated() where observedMask[site.ix][site.iy][iz] {
        activeSiteIndices.append(k)
      }
      guard !activeSiteIndices.isEmpty else { continue }
      activeZIndices.append(iz)

      for ix in 0 ..< nx {
        for iy in 0 ..< ny {
          if observedMask[ix][iy][iz] {
            idw[ix][iy][iz] = sparse[ix][iy][iz]
            continue
          }
          var weightedSum = 0.0
          var weightTotal = 0.0
          for k in activeSiteIndices {
            let site = sitesXY[k]
            let d = max(siteDistances[k][ix][iy], 1e-5)
            let w = 1.0 / (d * d)
            weightedSum += w * sparse[site.ix][site.iy][iz]
            weightTotal += w
          }
          idw[ix][iy][iz] = weightTotal > 0 ? (weightedSum / weightTotal) : 0.0
        }
      }
    }

    // Propagate from nearest depth slice if any depth slice had no active CPT observations
    if !activeZIndices.isEmpty, activeZIndices.count < nz {
      for iz in 0 ..< nz where !activeZIndices.contains(iz) {
        let nearestZ = activeZIndices.min(by: { abs($0 - iz) < abs($1 - iz) }) ?? activeZIndices[0]
        for ix in 0 ..< nx {
          for iy in 0 ..< ny {
            idw[ix][iy][iz] = idw[ix][iy][nearestZ]
          }
        }
      }
    }

    // 4. Normalized nearest distance field
    let distanceScale = max(Double(nx) * dx, Double(ny) * dy, 1.0)
    var nearestNorm = Array(repeating: Array(repeating: 0.0, count: ny), count: nx)
    for ix in 0 ..< nx {
      for iy in 0 ..< ny {
        var minD = Double.greatestFiniteMagnitude
        for k in siteDistances.indices {
          minD = min(minD, siteDistances[k][ix][iy])
        }
        nearestNorm[ix][iy] = (minD.isFinite ? minD : 0.0) / distanceScale
      }
    }

    let logDx = Float(log1p(dx))
    let logDy = Float(log1p(dy))
    let logDz = Float(log1p(dz))

    // 5. Run CoreML inference if available, otherwise fallback to denormalized IDW
    var physicalPrediction = Array(
      repeating: Array(repeating: Array(repeating: normalizationMean, count: nz), count: ny),
      count: nx
    )

    if let coreMLPred = runCoreMLInference(
      nx: nx,
      ny: ny,
      nz: nz,
      sparse: sparse,
      observedMask: observedMask,
      idw: idw,
      nearestNorm: nearestNorm,
      logDx: logDx,
      logDy: logDy,
      logDz: logDz
    ) {
      physicalPrediction = coreMLPred
    } else {
      for ix in 0 ..< nx {
        for iy in 0 ..< ny {
          for iz in 0 ..< nz {
            physicalPrediction[ix][iy][iz] = idw[ix][iy][iz] * normalizationStd + normalizationMean
          }
        }
      }
    }

    // 6. Hard data consistency: preserve measured soundings exactly
    for ix in 0 ..< nx {
      for iy in 0 ..< ny {
        for iz in 0 ..< nz where observedMask[ix][iy][iz] {
          physicalPrediction[ix][iy][iz] = observedIc[ix][iy][iz]
        }
      }
    }

    return SchemaGANReconstructionOutput(
      reconstructedIc: physicalPrediction,
      observedIc: observedIc,
      observedMask: observedMask,
      validMask: validMask,
      observedSitesXY: sitesXY
    )
  }

  private static func runCoreMLInference(
    nx: Int,
    ny: Int,
    nz: Int,
    sparse: [[[Double]]],
    observedMask: [[[Bool]]],
    idw: [[[Double]]],
    nearestNorm: [[Double]],
    logDx: Float,
    logDy: Float,
    logDz: Float
  ) -> [[[Double]]]? {
    let shape: [NSNumber] = [
      1,
      7,
      NSNumber(value: nz),
      NSNumber(value: ny),
      NSNumber(value: nx)
    ]
    guard let inputArray = try? MLMultiArray(shape: shape, dataType: .float32) else {
      return nil
    }

    let strides = inputArray.strides.map(\.intValue)
    let ptr = inputArray.dataPointer.bindMemory(to: Float.self, capacity: inputArray.count)

    // Populate [1, 7, Z, Y, X]
    for iz in 0 ..< nz {
      for iy in 0 ..< ny {
        for ix in 0 ..< nx {
          let baseOffset = iz * strides[2] + iy * strides[3] + ix * strides[4]
          ptr[0 * strides[1] + baseOffset] = Float(sparse[ix][iy][iz])
          ptr[1 * strides[1] + baseOffset] = observedMask[ix][iy][iz] ? 1.0 : 0.0
          ptr[2 * strides[1] + baseOffset] = Float(idw[ix][iy][iz])
          ptr[3 * strides[1] + baseOffset] = Float(nearestNorm[ix][iy])
          ptr[4 * strides[1] + baseOffset] = logDx
          ptr[5 * strides[1] + baseOffset] = logDy
          ptr[6 * strides[1] + baseOffset] = logDz
        }
      }
    }

    let config = MLModelConfiguration()
    config.computeUnits = .all
    guard
      let model = try? SchemaGAN_V4_2_Flexible(configuration: config),
      let output = try? model.prediction(features: inputArray)
    else {
      return nil
    }

    let outArray = output.var_124
    let outStrides = outArray.strides.map(\.intValue)
    let outPtr = outArray.dataPointer.bindMemory(to: Float.self, capacity: outArray.count)

    // Output layout is [1, 1, Z, Y, X] -> transpose back to [X][Y][Z] and denormalize
    let zStride = outStrides.count >= 5 ? outStrides[2] : (ny * nx)
    let yStride = outStrides.count >= 5 ? outStrides[3] : nx
    let xStride = outStrides.count >= 5 ? outStrides[4] : 1

    var physical = Array(
      repeating: Array(repeating: Array(repeating: normalizationMean, count: nz), count: ny),
      count: nx
    )
    for ix in 0 ..< nx {
      for iy in 0 ..< ny {
        for iz in 0 ..< nz {
          let idx = iz * zStride + iy * yStride + ix * xStride
          let normVal = Double(outPtr[idx])
          let val = normVal * normalizationStd + normalizationMean
          physical[ix][iy][iz] = val.isFinite ? val : normalizationMean
        }
      }
    }
    return physical
  }

  private static func resolveUniqueCell(
    preferredX: Int,
    preferredY: Int,
    nx: Int,
    ny: Int,
    validXY: [[Bool]],
    occupied: Set<Int>
  ) -> (ix: Int, iy: Int) {
    let key = preferredX * ny + preferredY
    if !occupied.contains(key) {
      return (preferredX, preferredY)
    }
    var bestX = preferredX
    var bestY = preferredY
    var bestDist = Int.max

    for x in 0 ..< nx {
      for y in 0 ..< ny {
        let k = x * ny + y
        if !occupied.contains(k) {
          let dist = (x - preferredX) * (x - preferredX) + (y - preferredY) * (y - preferredY)
          let penalty = validXY[x][y] ? 0 : 1000
          if dist + penalty < bestDist {
            bestDist = dist + penalty
            bestX = x
            bestY = y
          }
        }
      }
    }
    return (bestX, bestY)
  }

  private static func interpolate1D(x: Double, xs: [Double], ys: [Double]) -> Double {
    guard !xs.isEmpty, xs.count == ys.count else {
      return normalizationMean
    }
    if x <= xs[0] {
      return ys[0]
    }
    if x >= xs[xs.count - 1] {
      return ys[ys.count - 1]
    }
    for i in 0 ..< (xs.count - 1) {
      let x0 = xs[i]
      let x1 = xs[i + 1]
      if x >= x0, x <= x1 {
        let span = x1 - x0
        if span <= 1e-9 {
          return ys[i]
        }
        let t = (x - x0) / span
        return ys[i] + t * (ys[i + 1] - ys[i])
      }
    }
    return ys[ys.count - 1]
  }
}

