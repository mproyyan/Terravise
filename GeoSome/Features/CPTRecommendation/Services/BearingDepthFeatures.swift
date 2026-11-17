import Foundation

/// Experimental U4 features and candidate geometry, in the frozen research order.
enum BearingDepthFeatures {
  enum Failure: Error { case invalidInput }
  static func make(grid: BearingRuleGrid, qc: [Double], valid: [Bool],
                   candidate: [Bool], sites: [(x: Int, y: Int)],
                   includeGeometry: Bool, zeroGeometryForNonCandidates: Bool = false) throws -> [[Double]?] {
    guard qc.count == grid.voxelCount, valid.count == grid.voxelCount,
          candidate.count == grid.voxelCount, grid.dzM > 0 else { throw Failure.invalidInput }
    var xy = [Bool](repeating: false, count: grid.nx * grid.ny)
    for x in 0..<grid.nx { for y in 0..<grid.ny {
      xy[grid.column(x,y)] = (0..<grid.nz).contains { candidate[grid.index(x,y,$0)] }
    } }
    // Python receives QC-FS as float32 before computing these features.
    let q32 = qc.map { Double(Float($0)) }
    var values = try BearingU42Features.make(nx: grid.nx, ny: grid.ny, nz: grid.nz,
      dxM: grid.dxM, dyM: grid.dyM, cptSitesXY: sites,
      qcMPaXYZ: q32, validXYZ: valid, candidateXY: xy)
    guard includeGeometry else { return values }
    for x in 0..<grid.nx { for y in 0..<grid.ny {
      let column = grid.column(x,y)
      guard var features = values[column] else { continue }
      if !xy[column] {
        values[column] = zeroGeometryForNonCandidates ? features + [Double](repeating: 0, count: 6) : nil
        continue
      }
      let zs = (0..<grid.nz).filter { candidate[grid.index(x,y,$0)] }
      var runs: [[Int]] = []
      for z in zs {
        if let last = runs.indices.last, runs[last].last! + 1 == z { runs[last].append(z) }
        else { runs.append([z]) }
      }
      guard let first = runs.first, let firstZ = first.first, let lastZ = first.last else { throw Failure.invalidInput }
      let gap = runs.count > 1 ? Double(runs[1][0] - lastZ - 1) * grid.dzM : -1
      let x0 = max(0,x-1), x1 = min(grid.nx,x+2), y0 = max(0,y-1), y1 = min(grid.ny,y+2)
      var nearby = 0
      for xx in x0..<x1 { for yy in y0..<y1 { if xy[grid.column(xx,yy)] { nearby += 1 } } }
      let geometry = [Double(firstZ) * grid.dzM, Double(first.count) * grid.dzM,
                      Double(runs.count), gap, Double(nearby) / Double((x1-x0)*(y1-y0)),
                      Double(zs.count) / Double(grid.nz)]
      features.append(contentsOf: geometry.map { Double(Float($0)) })
      values[column] = features
    } }
    return values
  }
}
