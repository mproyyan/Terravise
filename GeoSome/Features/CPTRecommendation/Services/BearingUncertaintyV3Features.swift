import Foundation

enum BearingUncertaintyV3Features {
  enum Failure: Error { case incompatible }
  static func make(grid: BearingRuleGrid, qc: [Double], ic: [Double], valid: [Bool],
                   candidate: [Bool], sites: [(x: Int, y: Int)],
                   qcMinimum: Double, icMaximum: Double, thickness: Double, footprint: Double) throws -> [[Double]?] {
    guard ic.count == grid.voxelCount, valid.count == grid.voxelCount,
          qcMinimum.isFinite, icMaximum.isFinite, thickness.isFinite, thickness > 0,
          footprint.isFinite, (0...1).contains(footprint), grid.dzM.isFinite, grid.dzM > 0 else { throw Failure.incompatible }
    var base = try BearingDepthFeatures.make(grid: grid, qc: qc, valid: valid,
      candidate: candidate, sites: sites, includeGeometry: true, zeroGeometryForNonCandidates: true)
    let effective = Double(max(1, Int(ceil(thickness / grid.dzM - 1e-9)))) * grid.dzM
    for x in 0..<grid.nx { for y in 0..<grid.ny {
      let column = grid.column(x,y)
      guard var row = base[column] else { continue }
      var values = [Float]()
      var qcSum: Float = 0
      for z in 0..<grid.nz where valid[grid.index(x,y,z)] {
        qcSum += Float(qc[grid.index(x,y,z)])
        let value = ic[grid.index(x,y,z)]
        // The frozen Python rule uses Ic in [0, ic_max]. A negative Ic must not
        // enter this pipeline with a mask produced using only an upper bound.
        guard value.isFinite, value >= 0 else { throw Failure.incompatible }
        values.append(Float(value))
      }
      guard !values.isEmpty else { throw Failure.incompatible }
      // NumPy sums the float32 qc array before division promotes to float64.
      row[5] = Double(Float(Double(qcSum) / Double(values.count)))
      let sum = values.reduce(Float(0), +)
      let extra = [qcMinimum, thickness, footprint, grid.dzM, effective, icMaximum,
                   Double(sum / Float(values.count)), Double(values.min()!),
                   Double(values.filter { Double($0) <= icMaximum }.count) / Double(values.count)]
      row.append(contentsOf: extra.map { Double(Float($0)) })
      guard row.count == 24, row.allSatisfy(\.isFinite) else { throw Failure.incompatible }
      base[column] = row
    } }
    return base
  }
}
