import CoreML
import Foundation

/// Physical output uses the application's XYZ convention; fs is kPa.
struct QCFSVolume {
  let grid: CPTGridConfig
  let qcMPa: [[[Double]]]
  let fsKPa: [[[Double]]]
  let observedMask: [[[Bool]]]
  let validMask: [[[Bool]]]
  let modelName: String
  let inputProvenance: String
  let cptSitesXY: [(x: Int, y: Int)]
  /// The exact same-grid Ic reconstruction supplied to this QC-FS inference.
  /// Kept for display provenance; Bearing Rule remains qc-only.
  var icReconstruction: SchemaGANReconstructionOutput? = nil
}

enum QCFSInferenceResult {
  case coreML(QCFSVolume)
  case unsupportedGrid(String)
  case incompleteData(String)
  case inferenceFailed(String)
}

enum QCFSInferenceService {
  static let modelName = "QCFS_CNN_V3"
  static let qcReferenceMPa = 5.0
  static let fsReferenceMPa = 0.10

  struct Prepared {
    let input: MLMultiArray
    let idwQC: [Double]
    let idwFS: [Double]
    let measuredQC: [Double]
    let measuredFS: [Double]
    let observed: [Bool]
    let valid: [Bool]
  }

  private enum PreparationError: Error {
    case incomplete(String)
  }

  static func reconstruct(
    cptPoints: [CPTPointEntry],
    grid: CPTGridConfig,
    icReconstruction: SchemaGANReconstructionOutput,
    modelURL overrideModelURL: URL? = nil
  ) -> QCFSInferenceResult {
    let shape = "\(grid.nx)x\(grid.ny)x\(grid.nz)"
    guard grid.isQCFSV3Shape else {
      return .unsupportedGrid("Grid \(shape) tidak termasuk empat bentuk QC-FS CNN V3 yang tervalidasi.")
    }
    guard grid.hasSamePhysicalGrid(as: icReconstruction.grid),
          grid.dxM > 0, grid.dyM > 0, grid.dzM > 0,
          icReconstruction.validMask.count == grid.nx,
          icReconstruction.validMask.allSatisfy({ $0.count == grid.ny && $0.allSatisfy({ $0.count == grid.nz }) }),
          icReconstruction.observedMask.count == grid.nx,
          icReconstruction.observedMask.allSatisfy({ $0.count == grid.ny && $0.allSatisfy({ $0.count == grid.nz }) }) else {
      return .incompleteData("Grid atau mask rekonstruksi Ic tidak sesuai.")
    }
    guard icReconstruction.observedSitesXY.allSatisfy({
      $0.ix >= 0 && $0.ix < grid.nx && $0.iy >= 0 && $0.iy < grid.ny
    }) else {
      return .incompleteData("Koordinat grid CPT berada di luar grid bersama.")
    }
    let occupiedSites = Set(icReconstruction.observedSitesXY.map { $0.ix * grid.ny + $0.iy })
    for x in 0..<grid.nx {
      for y in 0..<grid.ny {
        let expectedValid = grid.validXYMask[x][y] || occupiedSites.contains(x * grid.ny + y)
        guard icReconstruction.validMask[x][y].allSatisfy({ $0 == expectedValid }) else {
          return .incompleteData("Mask valid Ic tidak selaras dengan poligon/grid bersama.")
        }
      }
    }
    let prepared: Prepared
    do {
      prepared = try prepare(cptPoints: cptPoints, grid: grid, reconstruction: icReconstruction)
    } catch PreparationError.incomplete(let reason) {
      return .incompleteData(reason)
    } catch {
      return .inferenceFailed("Input QC-FS tidak dapat dibentuk: \(error.localizedDescription)")
    }
    guard let modelURL = overrideModelURL ?? Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
      return .inferenceFailed("Model Core ML \(modelName) tidak ada di bundle aplikasi.")
    }
    do {
      let configuration = MLModelConfiguration()
      let model = try MLModel(contentsOf: modelURL, configuration: configuration)
      let provider = try MLDictionaryFeatureProvider(dictionary: ["input_volume": MLFeatureValue(multiArray: prepared.input)])
      let prediction = try model.prediction(from: provider)
      guard let residual = prediction.featureValue(for: "residual")?.multiArrayValue,
            residual.shape.map(\.intValue) == [1, 2, grid.nz, grid.ny, grid.nx] else {
        return .inferenceFailed("Output residual QC-FS memiliki bentuk yang tidak sesuai.")
      }
      let count = grid.nx * grid.ny * grid.nz
      var qc = Array(repeating: Array(repeating: Array(repeating: 0.0, count: grid.nz), count: grid.ny), count: grid.nx)
      var fs = qc
      var observedMask = Array(repeating: Array(repeating: Array(repeating: false, count: grid.nz), count: grid.ny), count: grid.nx)
      var validMask = observedMask
      for z in 0..<grid.nz {
        for y in 0..<grid.ny {
          for x in 0..<grid.nx {
            let index = flatIndex(x: x, y: y, z: z, grid: grid)
            let qCorrection = residual[index].doubleValue
            let fCorrection = residual[count + index].doubleValue
            guard qCorrection.isFinite, fCorrection.isFinite else {
              return .inferenceFailed("Output residual QC-FS mengandung nilai tidak finite.")
            }
            let predictedQ = exp(log(max(prepared.idwQC[index], 1e-6)) + qCorrection)
            let predictedF = exp(log(max(prepared.idwFS[index], 1e-8)) + fCorrection)
            let q = prepared.observed[index] ? prepared.measuredQC[index] : predictedQ
            let f = prepared.observed[index] ? prepared.measuredFS[index] : predictedF
            guard q.isFinite, f.isFinite else {
              return .inferenceFailed("Output fisik QC-FS mengandung nilai tidak finite.")
            }
            qc[x][y][z] = q
            fs[x][y][z] = f * 1_000.0
            observedMask[x][y][z] = prepared.observed[index]
            validMask[x][y][z] = prepared.valid[index]
          }
        }
      }
      let provenance = cptPoints.contains(where: { $0.file.isDemo }) ? "Demo CPT" : "Imported CPT measurements"
      var volume = QCFSVolume(
        grid: grid, qcMPa: qc, fsKPa: fs, observedMask: observedMask,
        validMask: validMask, modelName: modelName,
        inputProvenance: provenance,
        cptSitesXY: icReconstruction.observedSitesXY.map { ($0.ix, $0.iy) }
      )
      volume.icReconstruction = icReconstruction
      return .coreML(volume)
    } catch {
      return .inferenceFailed("Inference QC-FS gagal: \(error.localizedDescription)")
    }
  }

  private static func flatIndex(x: Int, y: Int, z: Int, grid: CPTGridConfig) -> Int {
    (z * grid.ny + y) * grid.nx + x
  }

  private static func interpolate(_ depth: Double, rows: [CPTRowData], keyPath: KeyPath<CPTRowData, Double>) -> Double {
    if depth <= rows[0].depth { return rows[0][keyPath: keyPath] }
    if depth >= rows[rows.count - 1].depth { return rows[rows.count - 1][keyPath: keyPath] }
    for i in 1..<rows.count where depth <= rows[i].depth {
      let lower = rows[i - 1]
      let upper = rows[i]
      let fraction = (depth - lower.depth) / (upper.depth - lower.depth)
      return lower[keyPath: keyPath] + fraction * (upper[keyPath: keyPath] - lower[keyPath: keyPath])
    }
    return rows[rows.count - 1][keyPath: keyPath]
  }

  static func prepare(
    cptPoints: [CPTPointEntry],
    grid: CPTGridConfig,
    reconstruction: SchemaGANReconstructionOutput
  ) throws -> Prepared {
    let n = grid.nx * grid.ny * grid.nz
    let sitePoints = cptPoints.filter { !$0.rows.isEmpty }
    guard sitePoints.count == reconstruction.observedSitesXY.count else {
      throw PreparationError.incomplete("Pemetaan CPT dan rekonstruksi Ic tidak selaras.")
    }
    var measuredQC = Array(repeating: 0.0, count: n)
    var measuredFS = measuredQC // MPa internally
    var observed = Array(repeating: false, count: n)
    var valid = observed
    for x in 0..<grid.nx {
      for y in 0..<grid.ny {
        for z in 0..<grid.nz {
          valid[flatIndex(x: x, y: y, z: z, grid: grid)] = reconstruction.validMask[x][y][z]
        }
      }
    }
    for (siteIndex, point) in sitePoints.enumerated() {
      let site = reconstruction.observedSitesXY[siteIndex]
      let rows = point.rows.sorted { $0.depth < $1.depth }
      guard rows.allSatisfy({ $0.depth.isFinite && $0.depth >= 0 && $0.coneResistance.isFinite && $0.coneResistance > 0 && $0.localFriction.isFinite && $0.localFriction >= 0 }),
            zip(rows, rows.dropFirst()).allSatisfy({ $0.depth < $1.depth }) else {
        throw PreparationError.incomplete("Profil qc/fs CPT-\(siteIndex + 1) berisi nilai atau kedalaman tidak valid.")
      }
      for z in 0..<grid.nz where reconstruction.observedMask[site.ix][site.iy][z] {
        let depth = Double(z) * grid.dzM
        // The Ic pipeline accepts half-cell edge coverage. QC-FS does not extrapolate measured qc/fs.
        guard depth >= rows[0].depth, depth <= rows[rows.count - 1].depth else { continue }
        let index = flatIndex(x: site.ix, y: site.iy, z: z, grid: grid)
        measuredQC[index] = interpolate(depth, rows: rows, keyPath: \.coneResistance)
        measuredFS[index] = interpolate(depth, rows: rows, keyPath: \.localFriction) / 1_000.0
        observed[index] = true
      }
    }
    var idwQC = measuredQC
    var idwFS = measuredFS
    var distances = Array(repeating: 0.0, count: n)
    let diagonal = max(hypot(Double(grid.nx) * grid.dxM, Double(grid.ny) * grid.dyM), 1e-8)
    for z in 0..<grid.nz {
      let measured = reconstruction.observedSitesXY.filter { observed[flatIndex(x: $0.ix, y: $0.iy, z: z, grid: grid)] }
      guard !measured.isEmpty else {
        throw PreparationError.incomplete("Tidak ada pengukuran qc/fs pada depth \(Double(z) * grid.dzM) m; QC-FS memerlukan cakupan setiap lapisan grid.")
      }
      for y in 0..<grid.ny {
        for x in 0..<grid.nx {
          let index = flatIndex(x: x, y: y, z: z, grid: grid)
          let nearest = measured.map { site -> (index: Int, distance: Double) in
            let d = hypot(Double(x - site.ix) * grid.dxM, Double(y - site.iy) * grid.dyM)
            return (flatIndex(x: site.ix, y: site.iy, z: z, grid: grid), d)
          }.sorted { $0.distance < $1.distance }.prefix(4)
          var weightSum = 0.0
          var weightedQ = 0.0
          var weightedF = 0.0
          for site in nearest {
            let weight = 1.0 / pow(max(site.distance, 1e-8), 2)
            weightSum += weight
            weightedQ += weight * measuredQC[site.index]
            weightedF += weight * measuredFS[site.index]
          }
          idwQC[index] = weightedQ / weightSum
          idwFS[index] = weightedF / weightSum
          distances[index] = min(max((nearest.first?.distance ?? 0) / diagonal, 0), 1)
        }
      }
    }
    let input = try MLMultiArray(shape: [1, 9, NSNumber(value: grid.nz), NSNumber(value: grid.ny), NSNumber(value: grid.nx)], dataType: .float32)
    for z in 0..<grid.nz {
      for y in 0..<grid.ny {
        for x in 0..<grid.nx {
          let index = flatIndex(x: x, y: y, z: z, grid: grid)
          let channelValues = [
            log(max(idwQC[index], 1e-6) / qcReferenceMPa),
            log(max(idwFS[index], 1e-8) / fsReferenceMPa),
            observed[index] ? log(max(measuredQC[index], 1e-6) / qcReferenceMPa) : 0,
            observed[index] ? log(max(measuredFS[index], 1e-8) / fsReferenceMPa) : 0,
            observed[index] ? 1.0 : 0.0,
            distances[index],
            (Double(x) + 0.5) / Double(grid.nx),
            (Double(y) + 0.5) / Double(grid.ny),
            (Double(z) + 0.5) / Double(grid.nz)
          ]
          for channel in 0..<9 { input[channel * n + index] = NSNumber(value: Float(channelValues[channel])) }
        }
      }
    }
    return Prepared(input: input, idwQC: idwQC, idwFS: idwFS, measuredQC: measuredQC, measuredFS: measuredFS, observed: observed, valid: valid)
  }
}
