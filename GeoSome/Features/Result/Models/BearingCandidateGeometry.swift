import Foundation
import RealityKit
import simd

/// Maps the authoritative southwest-origin QC-FS grid into the existing
/// centered Result Analysis scene. X is east, scene +Z is south, depth is -Y.
enum BearingCandidateGeometry {
  static func localX(_ x: Double, output: BearingRuleOutput, volume: SubsurfaceVoxelVolume) -> Float {
    Float(x * output.grid.dxM) / volume.cellStepXM - volume.centerX
  }

  static func localZ(_ y: Double, output: BearingRuleOutput, volume: SubsurfaceVoxelVolume) -> Float {
    Float(Double(output.grid.ny - 1) * output.grid.dyM - y * output.grid.dyM) / volume.cellStepZM - volume.centerZ
  }

  static func localY(depthM: Double, volume: SubsurfaceVoxelVolume) -> Float {
    -Float(depthM) / volume.cellStepYM
  }

  static func gridXY(localX: Float, localZ: Float, output: BearingRuleOutput, volume: SubsurfaceVoxelVolume) -> (x: Int, y: Int)? {
    let x = Int((Double(localX + volume.centerX) * Double(volume.cellStepXM) / output.grid.dxM).rounded())
    let y = Int((Double(output.grid.ny - 1) - Double(localZ + volume.centerZ) * Double(volume.cellStepZM) / output.grid.dyM).rounded())
    guard (0..<output.grid.nx).contains(x), (0..<output.grid.ny).contains(y) else { return nil }
    return (x, y)
  }

  @MainActor
  static func mesh(output: BearingRuleOutput, volume: SubsurfaceVoxelVolume) -> MeshResource? {
    let grid = output.grid
    func active(_ x: Int, _ y: Int, _ z: Int) -> Bool {
      (0..<grid.nx).contains(x) && (0..<grid.ny).contains(y) && (0..<grid.nz).contains(z) &&
        output.candidateMaskXYZ[grid.index(x, y, z)]
    }
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []
    func face(_ points: [SIMD3<Float>], normal: SIMD3<Float>, uv: SIMD2<Float>) {
      let base = UInt32(positions.count)
      positions.append(contentsOf: points)
      normals.append(contentsOf: Array(repeating: normal, count: 4))
      uvs.append(contentsOf: Array(repeating: uv, count: 4))
      indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
    }
    for x in 0..<grid.nx {
      for y in 0..<grid.ny {
        let uv = SIMD2<Float>((Float(x) + 0.5) / Float(grid.nx), (Float(y) + 0.5) / Float(grid.ny))
        for z in 0..<grid.nz where active(x, y, z) {
          let x0 = localX(Double(x) - 0.5, output: output, volume: volume)
          let x1 = localX(Double(x) + 0.5, output: output, volume: volume)
          let z0 = localZ(Double(y) + 0.5, output: output, volume: volume)
          let z1 = localZ(Double(y) - 0.5, output: output, volume: volume)
          let top = localY(depthM: Double(z) * grid.dzM, volume: volume)
          let bottom = localY(depthM: Double(z + 1) * grid.dzM, volume: volume)
          if !active(x, y, z - 1) {
            face([SIMD3(x0,top,z0), SIMD3(x0,top,z1), SIMD3(x1,top,z1), SIMD3(x1,top,z0)], normal: SIMD3(0,1,0), uv: uv)
          }
          if !active(x, y, z + 1) {
            face([SIMD3(x0,bottom,z1), SIMD3(x0,bottom,z0), SIMD3(x1,bottom,z0), SIMD3(x1,bottom,z1)], normal: SIMD3(0,-1,0), uv: uv)
          }
          if !active(x - 1, y, z) {
            face([SIMD3(x0,bottom,z0), SIMD3(x0,bottom,z1), SIMD3(x0,top,z1), SIMD3(x0,top,z0)], normal: SIMD3(-1,0,0), uv: uv)
          }
          if !active(x + 1, y, z) {
            face([SIMD3(x1,bottom,z1), SIMD3(x1,bottom,z0), SIMD3(x1,top,z0), SIMD3(x1,top,z1)], normal: SIMD3(1,0,0), uv: uv)
          }
          if !active(x, y - 1, z) {
            face([SIMD3(x0,bottom,z1), SIMD3(x1,bottom,z1), SIMD3(x1,top,z1), SIMD3(x0,top,z1)], normal: SIMD3(0,0,1), uv: uv)
          }
          if !active(x, y + 1, z) {
            face([SIMD3(x1,bottom,z0), SIMD3(x0,bottom,z0), SIMD3(x0,top,z0), SIMD3(x1,top,z0)], normal: SIMD3(0,0,-1), uv: uv)
          }
        }
      }
    }
    guard !positions.isEmpty else { return nil }
    var descriptor = MeshDescriptor(name: "BearingRuleCandidateVoxels")
    descriptor.positions = MeshBuffers.Positions(positions)
    descriptor.normals = MeshBuffers.Normals(normals)
    descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
    descriptor.primitives = .triangles(indices)
    return try? MeshResource.generate(from: [descriptor])
  }
}
