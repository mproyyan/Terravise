import Foundation

enum BearingRuleEvaluation {
  case candidateDetected(BearingRuleOutput)
  /// A screened volume without candidates does not establish absence of a bearing stratum.
  case noCandidateDetected(BearingRuleOutput)
  case qcfsUnavailable(String)
  case incompatibleGrid(String)
  case insufficientMeasurementCoverage(String)
  case invalidInput(String)

  var statusText: String {
    switch self {
    case .candidateDetected: "Kandidat lapisan terdeteksi dari QC-FS CNN V3 dan Bearing Rule."
    case .noCandidateDetected: "Tidak ada kandidat menurut kriteria ini; ini bukan bukti lapisan yang sesuai tidak ada."
    case .qcfsUnavailable(let reason): "QC-FS tidak tersedia: \(reason)"
    case .incompatibleGrid(let reason): "Grid tidak kompatibel: \(reason)"
    case .insufficientMeasurementCoverage(let reason): "Cakupan CPT belum cukup: \(reason)"
    case .invalidInput(let reason): "Input rule tidak valid: \(reason)"
    }
  }
}

enum BearingRuleService {
  /// Pure rule evaluation; repeat with new criteria using the same cached QC-FS volume.
  static func evaluate(
    qcfs: QCFSInferenceResult,
    criteria: BearingRuleCriteria = .init(),
    experimentalIcMaximum: Double? = nil
  ) -> BearingRuleEvaluation {
    switch qcfs {
    case .unsupportedGrid(let reason): return .incompatibleGrid(reason)
    case .incompleteData(let reason): return .insufficientMeasurementCoverage(reason)
    case .inferenceFailed(let reason): return .qcfsUnavailable(reason)
    case .coreML(let volume):
      let source = volume.grid
      let grid = BearingRuleGrid(nx: source.nx, ny: source.ny, nz: source.nz, dxM: source.dxM, dyM: source.dyM, dzM: source.dzM)
      guard volume.qcMPa.count == grid.nx, volume.validMask.count == grid.nx,
            volume.qcMPa.allSatisfy({ $0.count == grid.ny && $0.allSatisfy({ $0.count == grid.nz }) }),
            volume.validMask.allSatisfy({ $0.count == grid.ny && $0.allSatisfy({ $0.count == grid.nz }) }) else {
        return .invalidInput("Dimensi qc/valid mask tidak cocok dengan grid.")
      }
      var qc = [Float](repeating: 0, count: grid.voxelCount)
      var valid = [Bool](repeating: false, count: grid.voxelCount)
      for x in 0..<grid.nx {
        for y in 0..<grid.ny {
          for z in 0..<grid.nz {
            let index = grid.index(x, y, z)
            qc[index] = Float(volume.qcMPa[x][y][z])
            valid[index] = volume.validMask[x][y][z]
          }
        }
      }
      if let maximum = experimentalIcMaximum {
        guard maximum.isFinite,
         let ic = volume.icReconstruction,
         ic.inferenceSource == "SchemaGAN V4.2 Flexible Core ML",
         ic.grid.hasSamePhysicalGrid(as: source),
         ic.reconstructedIc.count == grid.nx, ic.validMask.count == grid.nx,
         ic.reconstructedIc.allSatisfy({ $0.count == grid.ny && $0.allSatisfy({ $0.count == grid.nz }) }),
         ic.validMask == volume.validMask,
         ic.reconstructedIc.enumerated().allSatisfy({ x, rows in
           rows.enumerated().allSatisfy({ y, values in
             values.enumerated().allSatisfy({ z, value in !volume.validMask[x][y][z] || value.isFinite })
           })
         }) else {
          return .invalidInput("Hasil Bearing Layer memerlukan rekonstruksi Ic SchemaGAN yang valid dan selaras.")
        }
        // Mask the eligibility input, preserving the domain mask used for component footprint.
        for x in 0..<grid.nx { for y in 0..<grid.ny { for z in 0..<grid.nz {
          if ic.reconstructedIc[x][y][z] > maximum { qc[grid.index(x, y, z)] = .nan }
        } } }
      }
      do {
        let output = try BearingRuleEngine.evaluate(
          qcMPaXYZ: qc, validXYZ: valid, grid: grid,
          cptSitesXY: volume.cptSitesXY, criteria: criteria
        )
        return output.summary.candidateVoxels > 0 ? .candidateDetected(output) : .noCandidateDetected(output)
      } catch {
        return .invalidInput(String(describing: error))
      }
    }
  }
}
