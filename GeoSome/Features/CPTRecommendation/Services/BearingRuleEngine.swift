import Foundation

/// Screening rule only; neither bearing capacity nor proof of a bearing stratum.
struct BearingRuleCriteria: Sendable {
  var qcMinimumMPa: Double = 15
  var minimumThicknessM: Double = 2
  var minimumLateralFraction: Double = 0.05
}

struct BearingRuleGrid: Sendable {
  let nx: Int
  let ny: Int
  let nz: Int
  let dxM: Double
  let dyM: Double
  let dzM: Double

  var voxelCount: Int { nx * ny * nz }
  func index(_ x: Int, _ y: Int, _ z: Int) -> Int { (x * ny + y) * nz + z }
  func column(_ x: Int, _ y: Int) -> Int { x * ny + y }
}

struct BearingRuleInterval: Sendable {
  let xIndex: Int
  let yIndex: Int
  /// Python V2 contract's boundary-origin cell centers. The Terravise grid's
  /// first-center-origin coordinates are xIndex*dxM and yIndex*dyM instead.
  let referenceXCenterM: Double
  let referenceYCenterM: Double
  let projectXM: Double
  let projectYM: Double
  let topDepthM: Double
  let bottomDepthM: Double
  let thicknessM: Double
  let componentIDs: [Int]
  let nearestCPTDistanceM: Double
}

struct BearingRuleComponent: Sendable {
  let id: Int
  let voxelCount: Int
  let footprintColumns: Int
  let footprintFraction: Double
  let horizontalAreaM2: Double
  let topDepthM: Double
  let bottomDepthM: Double
}

struct BearingRuleSummary: Sendable {
  let cptCount: Int
  let candidateVoxels: Int
  let candidateFraction: Double
  let candidateColumns: Int
  let validColumns: Int
  let componentCount: Int
  let intervalCount: Int
  let minimumVerticalCells: Int
  let minimumLateralColumns: Int
  let shallowestTopDepthM: Double?
  let deepestBottomDepthM: Double?
  let maxContiguousThicknessM: Double?
}

struct BearingRuleOutput: Sendable {
  let grid: BearingRuleGrid
  /// Flattened XYZ, C-contiguous with Z fastest: (x*ny+y)*nz+z.
  let candidateMaskXYZ: [Bool]
  let componentIDsXYZ: [Int]
  /// Flattened XY: x*ny+y. Nil represents Python NaN for empty columns.
  let topDepthMXY: [Double?]
  let bottomDepthMXY: [Double?]
  let totalThicknessMXY: [Double]
  let intervalCountXY: [Int]
  let nearestCPTDistanceMXY: [Double]
  let intervals: [BearingRuleInterval]
  let components: [BearingRuleComponent]
  let summary: BearingRuleSummary
}

enum BearingRuleError: Error, CustomStringConvertible {
  case invalidInput(String)

  var description: String {
    switch self { case .invalidInput(let reason): reason }
  }
}

enum BearingRuleEngine {
  static func evaluate(
    qcMPaXYZ: [Float],
    validXYZ: [Bool],
    grid: BearingRuleGrid,
    cptSitesXY: [(x: Int, y: Int)],
    criteria: BearingRuleCriteria = .init()
  ) throws -> BearingRuleOutput {
    guard grid.nx > 0, grid.ny > 0, grid.nz > 0,
          grid.dxM.isFinite, grid.dyM.isFinite, grid.dzM.isFinite,
          grid.dxM > 0, grid.dyM > 0, grid.dzM > 0,
          qcMPaXYZ.count == grid.voxelCount, validXYZ.count == grid.voxelCount else {
      throw BearingRuleError.invalidInput("Bentuk volume atau spacing QC-FS tidak valid.")
    }
    guard criteria.qcMinimumMPa.isFinite, criteria.minimumThicknessM.isFinite,
          criteria.minimumLateralFraction.isFinite, criteria.minimumThicknessM > 0,
          (0...1).contains(criteria.minimumLateralFraction) else {
      throw BearingRuleError.invalidInput("Kriteria bearing tidak valid.")
    }
    guard !cptSitesXY.isEmpty,
          cptSitesXY.allSatisfy({ $0.x >= 0 && $0.x < grid.nx && $0.y >= 0 && $0.y < grid.ny }) else {
      throw BearingRuleError.invalidInput("Posisi CPT tidak tersedia atau di luar grid.")
    }
    let minVertical = max(1, Int(ceil(criteria.minimumThicknessM / grid.dzM - 1e-9)))
    let minLateral = max(1, Int(ceil(criteria.minimumLateralFraction * Double(grid.nx * grid.ny))))
    // Python converts qc to float32 before thresholding.
    let threshold = Float(criteria.qcMinimumMPa)
    var thick = Array(repeating: false, count: grid.voxelCount)
    for x in 0..<grid.nx {
      for y in 0..<grid.ny {
        var start: Int? = nil
        for z in 0...grid.nz {
          let eligible = z < grid.nz && validXYZ[grid.index(x, y, z)] &&
            qcMPaXYZ[grid.index(x, y, z)].isFinite && qcMPaXYZ[grid.index(x, y, z)] >= threshold
          if eligible {
            if start == nil { start = z }
          } else if let first = start {
            if z - first >= minVertical {
              for runZ in first..<z { thick[grid.index(x, y, runZ)] = true }
            }
            start = nil
          }
        }
      }
    }

    // Label thick voxels with 6-neighbor connectivity, then apply the Python
    // lateral footprint criterion before relabeling the retained mask.
    var provisional = Array(repeating: 0, count: grid.voxelCount)
    var accepted = Array(repeating: false, count: grid.voxelCount)
    var nextID = 0
    for x in 0..<grid.nx {
      for y in 0..<grid.ny {
        for z in 0..<grid.nz {
          let seed = grid.index(x, y, z)
          guard thick[seed], provisional[seed] == 0 else { continue }
          nextID += 1
          var queue = [seed]
          provisional[seed] = nextID
          var footprint = Set<Int>()
          var cursor = 0
          while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            let cx = current / (grid.ny * grid.nz)
            let cy = (current / grid.nz) % grid.ny
            let cz = current % grid.nz
            footprint.insert(grid.column(cx, cy))
            for (ax, ay, az) in [(cx-1,cy,cz),(cx+1,cy,cz),(cx,cy-1,cz),(cx,cy+1,cz),(cx,cy,cz-1),(cx,cy,cz+1)] {
              guard ax >= 0, ax < grid.nx, ay >= 0, ay < grid.ny, az >= 0, az < grid.nz else { continue }
              let neighbor = grid.index(ax, ay, az)
              if thick[neighbor] && provisional[neighbor] == 0 {
                provisional[neighbor] = nextID
                queue.append(neighbor)
              }
            }
          }
          if footprint.count >= minLateral { for index in queue { accepted[index] = true } }
        }
      }
    }

    var labels = Array(repeating: 0, count: grid.voxelCount)
    var components: [BearingRuleComponent] = []
    var finalID = 0
    for x in 0..<grid.nx {
      for y in 0..<grid.ny {
        for z in 0..<grid.nz {
          let seed = grid.index(x, y, z)
          guard accepted[seed], labels[seed] == 0 else { continue }
          finalID += 1
          var queue = [seed]
          labels[seed] = finalID
          var footprint = Set<Int>()
          var lowestZ = z, highestZ = z, cursor = 0
          while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            let cx = current / (grid.ny * grid.nz)
            let cy = (current / grid.nz) % grid.ny
            let cz = current % grid.nz
            footprint.insert(grid.column(cx, cy))
            lowestZ = min(lowestZ, cz)
            highestZ = max(highestZ, cz)
            for (ax, ay, az) in [(cx-1,cy,cz),(cx+1,cy,cz),(cx,cy-1,cz),(cx,cy+1,cz),(cx,cy,cz-1),(cx,cy,cz+1)] {
              guard ax >= 0, ax < grid.nx, ay >= 0, ay < grid.ny, az >= 0, az < grid.nz else { continue }
              let neighbor = grid.index(ax, ay, az)
              if accepted[neighbor] && labels[neighbor] == 0 {
                labels[neighbor] = finalID
                queue.append(neighbor)
              }
            }
          }
          components.append(BearingRuleComponent(
            id: finalID, voxelCount: queue.count, footprintColumns: footprint.count,
            footprintFraction: Double(footprint.count) / Double(grid.nx * grid.ny),
            horizontalAreaM2: Double(footprint.count) * grid.dxM * grid.dyM,
            topDepthM: Double(lowestZ) * grid.dzM,
            bottomDepthM: Double(highestZ + 1) * grid.dzM
          ))
        }
      }
    }

    let columnCount = grid.nx * grid.ny
    var top = [Double?](repeating: nil, count: columnCount)
    var bottom = top
    var totalThickness = [Double](repeating: 0, count: columnCount)
    var intervalCount = [Int](repeating: 0, count: columnCount)
    var nearest = [Double](repeating: 0, count: columnCount)
    var intervals: [BearingRuleInterval] = []
    var validColumns = 0, candidateColumns = 0
    for x in 0..<grid.nx {
      for y in 0..<grid.ny {
        let column = grid.column(x, y)
        let distance = cptSitesXY.map { site in
          hypot(Double(x - site.x) * grid.dxM, Double(y - site.y) * grid.dyM)
        }.min()!
        nearest[column] = Double(Float(distance)) // Python stores float32 nearest map
        if (0..<grid.nz).contains(where: { validXYZ[grid.index(x, y, $0)] }) { validColumns += 1 }
        var z = 0
        while z < grid.nz {
          guard accepted[grid.index(x, y, z)] else { z += 1; continue }
          let start = z
          var ids = Set<Int>()
          while z < grid.nz && accepted[grid.index(x, y, z)] {
            ids.insert(labels[grid.index(x, y, z)])
            z += 1
          }
          let thickness = Double(z - start) * grid.dzM
          top[column] = top[column] ?? Double(start) * grid.dzM
          bottom[column] = Double(z) * grid.dzM
          totalThickness[column] += thickness
          intervalCount[column] += 1
          intervals.append(BearingRuleInterval(
            xIndex: x, yIndex: y,
            referenceXCenterM: (Double(x) + 0.5) * grid.dxM,
            referenceYCenterM: (Double(y) + 0.5) * grid.dyM,
            projectXM: Double(x) * grid.dxM,
            projectYM: Double(y) * grid.dyM,
            topDepthM: Double(start) * grid.dzM,
            bottomDepthM: Double(z) * grid.dzM,
            thicknessM: thickness,
            componentIDs: ids.sorted(), nearestCPTDistanceM: nearest[column]
          ))
        }
        if intervalCount[column] > 0 { candidateColumns += 1 }
      }
    }
    let candidateVoxels = accepted.reduce(0) { $0 + ($1 ? 1 : 0) }
    let validVoxels = validXYZ.reduce(0) { $0 + ($1 ? 1 : 0) }
    let summary = BearingRuleSummary(
      cptCount: cptSitesXY.count,
      candidateVoxels: candidateVoxels,
      candidateFraction: validVoxels > 0 ? Double(candidateVoxels) / Double(validVoxels) : 0,
      candidateColumns: candidateColumns, validColumns: validColumns,
      componentCount: components.count, intervalCount: intervals.count,
      minimumVerticalCells: minVertical, minimumLateralColumns: minLateral,
      shallowestTopDepthM: intervals.map(\.topDepthM).min(),
      deepestBottomDepthM: intervals.map(\.bottomDepthM).max(),
      maxContiguousThicknessM: intervals.map(\.thicknessM).max()
    )
    return BearingRuleOutput(
      grid: grid, candidateMaskXYZ: accepted, componentIDsXYZ: labels,
      topDepthMXY: top, bottomDepthMXY: bottom,
      totalThicknessMXY: totalThickness, intervalCountXY: intervalCount,
      nearestCPTDistanceMXY: nearest, intervals: intervals,
      components: components, summary: summary
    )
  }
}
