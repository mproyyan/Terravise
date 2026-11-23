import Foundation

/// Column features in the frozen U4.2 Python order. Arrays use XYZ with Z fastest.
enum BearingU42Features {
  enum FeatureError: Error { case invalidInput }

  static func make(
    nx: Int, ny: Int, nz: Int, dxM: Double, dyM: Double,
    cptSitesXY: [(x: Int, y: Int)], qcMPaXYZ: [Double],
    validXYZ: [Bool], candidateXY: [Bool]
  ) throws -> [[Double]?] {
    guard nx > 0, ny > 0, nz > 0, dxM > 0, dyM > 0,
          dxM.isFinite, dyM.isFinite, !cptSitesXY.isEmpty,
          cptSitesXY.allSatisfy({ (0..<nx).contains($0.x) && (0..<ny).contains($0.y) }),
          qcMPaXYZ.count == nx * ny * nz, validXYZ.count == qcMPaXYZ.count,
          candidateXY.count == nx * ny else { throw FeatureError.invalidInput }
    let diagonal = max(hypot(Double(nx) * dxM, Double(ny) * dyM), 1e-8)
    var result = [[Double]?](repeating: nil, count: nx * ny)
    for x in 0..<nx {
      for y in 0..<ny {
        let column = x * ny + y
        var values = [Double]()
        for z in 0..<nz {
          let index = column * nz + z
          if validXYZ[index] {
            let qc = qcMPaXYZ[index]
            guard qc.isFinite else { throw FeatureError.invalidInput }
            values.append(qc)
          }
        }
        guard !values.isEmpty else { continue }
        let distance = cptSitesXY.map {
          hypot(Double(x - $0.x) * dxM, Double(y - $0.y) * dyM)
        }.min()!
        let count = Double(values.count)
        let features = [
          log1p(distance), distance / diagonal, log2(Double(cptSitesXY.count)),
          candidateXY[column] ? 1 : 0, values.max()!,
          values.reduce(0, +) / count,
          Double(values.filter { $0 >= 12 }.count) / count,
          Double(values.filter { $0 >= 15 }.count) / count,
          Double(values.filter { $0 >= 18 }.count) / count
        ]
        // The frozen training/export pipeline casts the complete feature matrix to float32.
        result[column] = features.map { Double(Float($0)) }
      }
    }
    return result
  }
}
