import Foundation

enum BearingUncertaintyV3Service {
  enum Failure: Error { case incompatible(String), empty }
  struct Result {
    let meanRiskPercent: Double, highRiskAreaPercent: Double, meanDepthM: Double?
#if DEBUG
    /// XY order x * ny + y; nil denotes an invalid column.
    var benchmarkRiskXY: [Double?] = []
    /// Raw model depth output, available only for predicted candidate columns.
    var benchmarkDepthXY: [Double?] = []
#endif
  }
  static func evaluate(volume: QCFSVolume, output: BearingRuleOutput, qcMinimum: Double,
                       icMaximum: Double, thickness: Double, model: BearingUncertaintyV3Model) throws -> Result {
    let grid = output.grid, source = volume.grid
    guard let ic = volume.icReconstruction, ic.inferenceSource == "SchemaGAN V4.2 Flexible Core ML",
          ic.grid.hasSamePhysicalGrid(as: source), ic.validMask == volume.validMask,
          grid.nx == source.nx, grid.ny == source.ny, grid.nz == source.nz,
          grid.dxM == source.dxM, grid.dyM == source.dyM, grid.dzM == source.dzM,
          volume.qcMPa.count == grid.nx, ic.reconstructedIc.count == grid.nx,
          volume.validMask.count == grid.nx, !volume.cptSitesXY.isEmpty else { throw Failure.incompatible("Ic atau grid tidak valid") }
    var qc = [Double](), icValues = [Double](), valid = [Bool]()
    for x in 0..<grid.nx {
      guard volume.qcMPa[x].count == grid.ny, ic.reconstructedIc[x].count == grid.ny, volume.validMask[x].count == grid.ny else { throw Failure.incompatible("Bentuk grid tidak valid") }
      for y in 0..<grid.ny {
        guard volume.qcMPa[x][y].count == grid.nz, ic.reconstructedIc[x][y].count == grid.nz, volume.validMask[x][y].count == grid.nz else { throw Failure.incompatible("Bentuk grid tidak valid") }
        qc.append(contentsOf: volume.qcMPa[x][y]); icValues.append(contentsOf: ic.reconstructedIc[x][y]); valid.append(contentsOf: volume.validMask[x][y])
      }
    }
    let features = try BearingUncertaintyV3Features.make(grid: grid, qc: qc, ic: icValues, valid: valid,
      candidate: output.candidateMaskXYZ, sites: volume.cptSitesXY, qcMinimum: qcMinimum,
      icMaximum: icMaximum, thickness: thickness, footprint: 0.05)
    var riskSum = 0.0, high = 0, count = 0, depthSum = 0.0, depthCount = 0
#if DEBUG
    var benchmarkRiskXY = [Double?](repeating: nil, count: grid.nx * grid.ny)
    var benchmarkDepthXY = [Double?](repeating: nil, count: grid.nx * grid.ny)
#endif
    for (column, optionalRow) in features.enumerated() {
      guard let row = optionalRow else { continue }
      guard row.count == model.featureCount, row.allSatisfy(\.isFinite) else { throw Failure.incompatible("Fitur tidak finite atau tidak lengkap") }
      let prediction = try model.predict(row, cptCount: volume.cptSitesXY.count,
        qc: Double(Float(qcMinimum)), ic: Double(Float(icMaximum)), thickness: Double(Float(thickness)))
      let risk = row[3] == 1 ? 1 - prediction.match : prediction.miss
      guard risk.isFinite, (0...1).contains(risk) else { throw Failure.incompatible("Risiko tidak finite") }
      riskSum += risk; count += 1
      if risk >= model.highRiskThreshold { high += 1 }
#if DEBUG
      benchmarkRiskXY[column] = risk
      if row[3] == 1 { benchmarkDepthXY[column] = max(0, prediction.depth) }
#endif
      // The research evaluation clamps the raw depth regressor at zero.
      if row[3] == 1 { depthSum += max(0, prediction.depth); depthCount += 1 }
    }
    guard count > 0 else { throw Failure.empty }
    let validColumnCount = (0..<(grid.nx * grid.ny)).filter { column in
      (0..<grid.nz).contains { valid[column * grid.nz + $0] }
    }.count
    guard count == validColumnCount else { throw Failure.incompatible("Jumlah risiko tidak sesuai kolom valid") }
    var result = Result(meanRiskPercent: 100 * riskSum / Double(count), highRiskAreaPercent: 100 * Double(high) / Double(count), meanDepthM: depthCount > 0 ? depthSum / Double(depthCount) : nil)
#if DEBUG
    result.benchmarkRiskXY = benchmarkRiskXY
    result.benchmarkDepthXY = benchmarkDepthXY
#endif
    return result
  }
}
