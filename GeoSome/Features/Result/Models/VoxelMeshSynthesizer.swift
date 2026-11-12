import CoreLocation
import Foundation
import RealityKit
import simd
import UIKit

enum VoxelMeshSynthesizer {
  /// Builds the shared palette of materials corresponding to `SoilLayerType.allCases`.
  /// Used with `meshDescriptor.materials = .perFace(...)` so the entire voxel volume renders in 1 draw call.
  @MainActor
  static func makeMaterialPalette() -> [SimpleMaterial] {
    SoilLayerType.allCases.map { layer in
      var material = SimpleMaterial(color: layer.uiColor, roughness: 0.88, isMetallic: false)
      material.faceCulling = .back
      return material
    }
  }

  /// Constructs a `SubsurfaceVoxelVolume` (`[GridCoord: SoilVoxel]`) shaped to the user-drawn boundary polygon.
  static func buildVolume(
    boundaryCoordinates: [CLLocationCoordinate2D],
    cptPoints: [CPTPointEntry]
  ) -> SubsurfaceVoxelVolume {
    let polygon = boundaryCoordinates.count >= 3
      ? boundaryCoordinates
      : CPTRecommendationViewModel.defaultSamplePoints.map(\.coordinate)

    var minLat = polygon[0].latitude
    var maxLat = polygon[0].latitude
    var minLon = polygon[0].longitude
    var maxLon = polygon[0].longitude

    for coord in polygon {
      minLat = min(minLat, coord.latitude)
      maxLat = max(maxLat, coord.latitude)
      minLon = min(minLon, coord.longitude)
      maxLon = max(maxLon, coord.longitude)
    }

    let meanLatRad = ((minLat + maxLat) * 0.5) * .pi / 180.0
    let mPerDegLat = 111_132.92 - 559.82 * cos(2.0 * meanLatRad) + 1.175 * cos(4.0 * meanLatRad)
    let mPerDegLon = max(111_412.84 * cos(meanLatRad) - 93.5 * cos(3.0 * meanLatRad), 1.0)

    let rawWidthM = max((maxLon - minLon) * mPerDegLon, 12.0)
    let rawLengthM = max((maxLat - minLat) * mPerDegLat, 12.0)

    // Discretize into a high-density 1m-normalized voxel grid (target 28...48 horizontal cells)
    // preserving the exact aspect ratio and polygon shape of the drawn boundary.
    let aspect = rawWidthM / max(rawLengthM, 1.0)
    let baseResolution = 32
    let nx: Int
    let nz: Int
    if aspect >= 1.0 {
      nz = baseResolution
      nx = min(max(Int((Double(baseResolution) * aspect).rounded()), 24), 48)
    } else {
      nx = baseResolution
      nz = min(max(Int((Double(baseResolution) / max(aspect, 0.25)).rounded()), 24), 48)
    }
    let ny = 20 // 20 vertical strata subdivisions

    let stepXM = Float(rawWidthM) / Float(max(nx - 1, 1))
    let stepZM = Float(rawLengthM) / Float(max(nz - 1, 1))
    let maxObservedDepth = cptPoints.flatMap(\.rows).map(\.depth).max() ?? 15.0
    let totalDepthM = Float(max(maxObservedDepth, 12.0))
    let stepYM = totalDepthM / Float(ny)

    // Project boundary vertices into normalized grid space [0 ... nx-1] x [0 ... nz-1]
    // Note: Z in 3D space corresponds to South (-Lat) -> North (+Lat) mapped so North is -Z or +Z consistently.
    let polyGridXZ: [(x: Double, z: Double)] = polygon.map { coord in
      let normX = (coord.longitude - minLon) / max(maxLon - minLon, 1e-9)
      let normZ = 1.0 - ((coord.latitude - minLat) / max(maxLat - minLat, 1e-9))
      return (normX * Double(nx - 1), normZ * Double(nz - 1))
    }

    var activeColumns = Array(repeating: Array(repeating: false, count: nz), count: nx)
    var activeColumnCount = 0

    for ix in 0 ..< nx {
      for iz in 0 ..< nz {
        if isPointInPolygon(x: Double(ix), z: Double(iz), polygon: polyGridXZ) {
          activeColumns[ix][iz] = true
          activeColumnCount += 1
        }
      }
    }

    // Fallback if polygon is degenerate
    if activeColumnCount < 8 {
      for ix in 0 ..< nx {
        for iz in 0 ..< nz {
          activeColumns[ix][iz] = true
        }
      }
    }

    // Optional SchemaGAN reconstruction when CPT points exist
    let schemaGrid: CPTGridConfig?
    let schemaRecon: SchemaGANReconstructionOutput?
    if !cptPoints.isEmpty {
      let g = CPTGridConfig.build(boundaryCoordinates: polygon, cptPoints: cptPoints)
      schemaGrid = g
      schemaRecon = SchemaGANService.reconstruct(cptPoints: cptPoints, grid: g)
    } else {
      schemaGrid = nil
      schemaRecon = nil
    }

    let centerX = Float(nx - 1) * 0.5
    let centerZ = Float(nz - 1) * 0.5

    var voxels: [GridCoord: SoilVoxel] = [:]
    voxels.reserveCapacity(nx * nz * ny)
    var flatMaterialGrid = Array(repeating: Int16(-1), count: nx * nz * ny)

    for ix in 0 ..< nx {
      let fx = Double(ix) / Double(max(nx - 1, 1))
      let lon = minLon + fx * (maxLon - minLon)

      for iz in 0 ..< nz where activeColumns[ix][iz] {
        let fz = Double(iz) / Double(max(nz - 1, 1))
        let lat = maxLat - fz * (maxLat - minLat)

        // Compute undulating geological horizon offsets across (fx, fz) so strata dip & wave naturally
        let wave1 = sin(fx * .pi * 2.1 + fz * 1.4) * 0.055
        let wave2 = cos(fz * .pi * 1.8 - fx * 1.1) * 0.045
        let dip = (fx * 0.06) - (fz * 0.04)

        // Map to SchemaGAN indices if available
        var reconBias = 0.0
        if let g = schemaGrid, let r = schemaRecon {
          let gx = min(max(Int((fx * Double(g.nx - 1)).rounded()), 0), g.nx - 1)
          let gy = min(max(Int(((1.0 - fz) * Double(g.ny - 1)).rounded()), 0), g.ny - 1)
          let midZ = g.nz / 2
          let icSample = r.reconstructedIc[gx][gy][midZ]
          reconBias = (icSample - 2.65) * 0.04
        }

        let horizonShift = wave1 + wave2 + dip + reconBias

        // Populate vertical column from y = 0 (bottom bedrock) to y = ny - 1 (top surface Y = 0)
        for iy in 0 ..< ny {
          // layerIdxFromTop: 0 at surface (iy == ny - 1), ny - 1 at bottom (iy == 0)
          let depthIndexFromTop = (ny - 1) - iy
          let normalizedDepth = (Double(depthIndexFromTop) + 0.5) / Double(ny)
          let adjustedDepth = min(max(normalizedDepth + horizonShift, 0.0), 0.999)

          // Map adjusted depth into the 8 stratified geotechnical layers (matching reference visual)
          let soilType = stratifiedLayer(forAdjustedDepth: adjustedDepth)
          let topDepth = Float(depthIndexFromTop) * stepYM
          let bottomDepth = Float(depthIndexFromTop + 1) * stepYM

          // Compute Robertson Ic consistent with the layer
          let synthesizedIc = Float(3.65 - adjustedDepth * 2.15)
          let coord = GridCoord(x: ix, y: iy, z: iz)

          let voxel = SoilVoxel(
            coord: coord,
            latitude: lat,
            longitude: lon,
            topDepthM: topDepth,
            bottomDepthM: bottomDepth,
            layerIdx: depthIndexFromTop,
            soilClassification: soilType,
            robertsonIc: synthesizedIc,
            moisturePercent: soilType.typicalMoisturePercent,
            bearingCapacityKPa: soilType.typicalBearingCapacityKPa
          )

          voxels[coord] = voxel
          flatMaterialGrid[(ix * nz * ny) + (iz * ny) + iy] = Int16(soilType.rawValue)
        }
      }
    }

    // Compute local 3D surface positions for CPT borehole pins
    var cptPositions: [SIMD3<Float>] = []
    if !cptPoints.isEmpty {
      for point in cptPoints {
        let normX = (point.coordinate.longitude - minLon) / max(maxLon - minLon, 1e-9)
        let normZ = 1.0 - ((point.coordinate.latitude - minLat) / max(maxLat - minLat, 1e-9))
        let gx = min(max(Int((normX * Double(nx - 1)).rounded()), 0), nx - 1)
        let gz = min(max(Int((normZ * Double(nz - 1)).rounded()), 0), nz - 1)
        let wx = Float(gx) - centerX
        let wz = Float(gz) - centerZ
        cptPositions.append(SIMD3<Float>(wx, 0.0, wz))
      }
    } else {
      // Sample reference CPT borehole markers on active surface cells (matching the 3 white pins in screenshot)
      var candidateCoords: [(Int, Int)] = []
      for ix in stride(from: nx / 4, to: (3 * nx) / 4, by: max(nx / 5, 2)) {
        let iz = nz / 2
        if activeColumns[ix][iz] {
          candidateCoords.append((ix, iz))
        }
      }
      for (ix, iz) in candidateCoords.prefix(3) {
        cptPositions.append(SIMD3<Float>(Float(ix) - centerX, 0.0, Float(iz) - centerZ))
      }
    }

    return SubsurfaceVoxelVolume(
      voxels: voxels,
      flatMaterialGrid: flatMaterialGrid,
      nx: nx,
      ny: ny,
      nz: nz,
      widthXM: Float(rawWidthM),
      depthYM: totalDepthM,
      lengthZM: Float(rawLengthM),
      cellStepXM: stepXM,
      cellStepYM: stepYM,
      cellStepZM: stepZM,
      centerX: centerX,
      centerZ: centerZ,
      cptSurfacePositions: cptPositions
    )
  }

  /// Synthesizes the entire active voxel volume into a single `MeshDescriptor` (1 Draw Call) using:
  /// 1. Neighbor-Aware Internal Face Culling (Manifold Shell Extraction)
  /// 2. 2D Greedy Meshing (Run-Length Quad Merging) across all 6 cardinal directions
  /// 3. Strict Counter-Clockwise (CCW) outward vertex winding with box half-extent `0.5` on a `1.0 m` grid
  /// 4. `.perFace` material indexing (`meshDescriptor.materials = .perFace(...)`)
  @MainActor
  static func synthesizeMesh(
    volume: SubsurfaceVoxelVolume,
    maxSliceX: Int,
    maxSliceZ: Int
  ) -> MeshResource? {
    let nx = volume.nx
    let ny = volume.ny
    let nz = volume.nz
    let clampedSliceX = min(max(maxSliceX, 0), nx - 1)
    let clampedSliceZ = min(max(maxSliceZ, 0), nz - 1)

    let centerX = volume.centerX
    let centerZ = volume.centerZ
    let topYIndex = Float(ny - 1)

    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    var faceMaterials: [UInt32] = []

    positions.reserveCapacity(4096)
    normals.reserveCapacity(4096)
    indices.reserveCapacity(6144)
    faceMaterials.reserveCapacity(2048)

    // Helper that appends a quad with strict CCW winding for outward normal `normal`
    @inline(__always)
    func emitQuad(
      _ v0: SIMD3<Float>,
      _ v1: SIMD3<Float>,
      _ v2: SIMD3<Float>,
      _ v3: SIMD3<Float>,
      normal: SIMD3<Float>,
      materialIndex: UInt32
    ) {
      let base = UInt32(positions.count)
      positions.append(v0)
      positions.append(v1)
      positions.append(v2)
      positions.append(v3)

      normals.append(normal)
      normals.append(normal)
      normals.append(normal)
      normals.append(normal)

      // Triangle 1: (v0, v1, v2), Triangle 2: (v0, v2, v3)
      // Cross product (v1 - v0) x (v2 - v0) points strictly along `normal` (CCW outward winding)
      indices.append(base)
      indices.append(base + 1)
      indices.append(base + 2)

      indices.append(base)
      indices.append(base + 2)
      indices.append(base + 3)

      faceMaterials.append(materialIndex)
      faceMaterials.append(materialIndex)
    }

    // Coordinate conversion helpers:
    // Each voxel at integer index `i` spans `[i - 0.5, i + 0.5]` (box half-extent = 0.5 on 1.0 m grid).
    // Consequently, a merged run from `start` of length `len` spans `[start - 0.5, start + len - 0.5]`.
    @inline(__always)
    func worldX(_ gridEdgeX: Int) -> Float {
      (Float(gridEdgeX) - 0.5) - centerX
    }

    @inline(__always)
    func worldY(_ gridEdgeY: Int) -> Float {
      // Top of surface layer (gridEdgeY == ny) is at Y = 0.0
      (Float(gridEdgeY) - 0.5) - topYIndex - 0.5
    }

    @inline(__always)
    func worldZ(_ gridEdgeZ: Int) -> Float {
      (Float(gridEdgeZ) - 0.5) - centerZ
    }

    // -------------------------------------------------------------------------
    // 1. +Y (Top Face) & -Y (Bottom Face) Slices — Greedy Meshing over (X, Z)
    // Rule: Emit +Y only when (x, y+1, z) is inactive; emit -Y only when (x, y-1, z) is inactive.
    // -------------------------------------------------------------------------
    let activeNX = clampedSliceX + 1
    let activeNZ = clampedSliceZ + 1

    for y in 0 ..< ny {
      // +Y Face (normal = (0, 1, 0))
      var maskPosY = Array(repeating: Int16(-1), count: activeNX * activeNZ)
      var hasPosY = false
      for x in 0 ..< activeNX {
        for z in 0 ..< activeNZ {
          let mat = volume.materialAt(x: x, y: y, z: z, maxSliceX: clampedSliceX, maxSliceZ: clampedSliceZ)
          guard mat >= 0 else { continue }
          let neighborAbove = volume.materialAt(x: x, y: y + 1, z: z, maxSliceX: clampedSliceX, maxSliceZ: clampedSliceZ)
          // Only emit top face when there is no active voxel above (surface layer)
          if neighborAbove < 0 {
            maskPosY[x * activeNZ + z] = mat
            hasPosY = true
          }
        }
      }

      if hasPosY {
        let py = worldY(y + 1)
        greedyMerge2D(width: activeNX, height: activeNZ, mask: &maskPosY) { u0, v0, w, h, mat in
          let x0 = worldX(u0)
          let x1 = worldX(u0 + w)
          let z0 = worldZ(v0)
          let z1 = worldZ(v0 + h)
          // CCW for +Y (0, 1, 0): (x0, py, z0) -> (x0, py, z1) -> (x1, py, z1) -> (x1, py, z0)
          emitQuad(
            SIMD3<Float>(x0, py, z0),
            SIMD3<Float>(x0, py, z1),
            SIMD3<Float>(x1, py, z1),
            SIMD3<Float>(x1, py, z0),
            normal: SIMD3<Float>(0, 1, 0),
            materialIndex: UInt32(mat)
          )
        }
      }

      // -Y Face (normal = (0, -1, 0))
      var maskNegY = Array(repeating: Int16(-1), count: activeNX * activeNZ)
      var hasNegY = false
      for x in 0 ..< activeNX {
        for z in 0 ..< activeNZ {
          let mat = volume.materialAt(x: x, y: y, z: z, maxSliceX: clampedSliceX, maxSliceZ: clampedSliceZ)
          guard mat >= 0 else { continue }
          let neighborBelow = volume.materialAt(x: x, y: y - 1, z: z, maxSliceX: clampedSliceX, maxSliceZ: clampedSliceZ)
          // Only emit bottom face for the deepest bedrock layer (no active voxel below)
          if neighborBelow < 0 {
            maskNegY[x * activeNZ + z] = mat
            hasNegY = true
          }
        }
      }

      if hasNegY {
        let py = worldY(y)
        greedyMerge2D(width: activeNX, height: activeNZ, mask: &maskNegY) { u0, v0, w, h, mat in
          let x0 = worldX(u0)
          let x1 = worldX(u0 + w)
          let z0 = worldZ(v0)
          let z1 = worldZ(v0 + h)
          // CCW for -Y (0, -1, 0): (x0, py, z0) -> (x1, py, z0) -> (x1, py, z1) -> (x0, py, z1)
          emitQuad(
            SIMD3<Float>(x0, py, z0),
            SIMD3<Float>(x1, py, z0),
            SIMD3<Float>(x1, py, z1),
            SIMD3<Float>(x0, py, z1),
            normal: SIMD3<Float>(0, -1, 0),
            materialIndex: UInt32(mat)
          )
        }
      }
    }

    // -------------------------------------------------------------------------
    // 2. +X & -X Vertical Perimeter / Slice Walls — Greedy Meshing over (Z, Y)
    // Rule: Emit side face only at perimeter boundary or active cross-section slice plane.
    // -------------------------------------------------------------------------
    for x in 0 ..< activeNX {
      var maskPosX = Array(repeating: Int16(-1), count: activeNZ * ny)
      var maskNegX = Array(repeating: Int16(-1), count: activeNZ * ny)
      var hasPosX = false
      var hasNegX = false

      for z in 0 ..< activeNZ {
        for y in 0 ..< ny {
          let mat = volume.materialAt(x: x, y: y, z: z, maxSliceX: clampedSliceX, maxSliceZ: clampedSliceZ)
          guard mat >= 0 else { continue }

          if volume.materialAt(x: x + 1, y: y, z: z, maxSliceX: clampedSliceX, maxSliceZ: clampedSliceZ) < 0 {
            maskPosX[z * ny + y] = mat
            hasPosX = true
          }
          if volume.materialAt(x: x - 1, y: y, z: z, maxSliceX: clampedSliceX, maxSliceZ: clampedSliceZ) < 0 {
            maskNegX[z * ny + y] = mat
            hasNegX = true
          }
        }
      }

      if hasPosX {
        let px = worldX(x + 1)
        greedyMerge2D(width: activeNZ, height: ny, mask: &maskPosX) { z0Idx, y0Idx, wZ, hY, mat in
          let z0 = worldZ(z0Idx)
          let z1 = worldZ(z0Idx + wZ)
          let y0 = worldY(y0Idx)
          let y1 = worldY(y0Idx + hY)
          // CCW for +X (1, 0, 0): (px, y0, z1) -> (px, y0, z0) -> (px, y1, z0) -> (px, y1, z1)
          emitQuad(
            SIMD3<Float>(px, y0, z1),
            SIMD3<Float>(px, y0, z0),
            SIMD3<Float>(px, y1, z0),
            SIMD3<Float>(px, y1, z1),
            normal: SIMD3<Float>(1, 0, 0),
            materialIndex: UInt32(mat)
          )
        }
      }

      if hasNegX {
        let px = worldX(x)
        greedyMerge2D(width: activeNZ, height: ny, mask: &maskNegX) { z0Idx, y0Idx, wZ, hY, mat in
          let z0 = worldZ(z0Idx)
          let z1 = worldZ(z0Idx + wZ)
          let y0 = worldY(y0Idx)
          let y1 = worldY(y0Idx + hY)
          // CCW for -X (-1, 0, 0): (px, y0, z0) -> (px, y0, z1) -> (px, y1, z1) -> (px, y1, z0)
          emitQuad(
            SIMD3<Float>(px, y0, z0),
            SIMD3<Float>(px, y0, z1),
            SIMD3<Float>(px, y1, z1),
            SIMD3<Float>(px, y1, z0),
            normal: SIMD3<Float>(-1, 0, 0),
            materialIndex: UInt32(mat)
          )
        }
      }
    }

    // -------------------------------------------------------------------------
    // 3. +Z & -Z Vertical Perimeter / Slice Walls — Greedy Meshing over (X, Y)
    // Rule: Emit side face only at perimeter boundary or active cross-section slice plane.
    // -------------------------------------------------------------------------
    for z in 0 ..< activeNZ {
      var maskPosZ = Array(repeating: Int16(-1), count: activeNX * ny)
      var maskNegZ = Array(repeating: Int16(-1), count: activeNX * ny)
      var hasPosZ = false
      var hasNegZ = false

      for x in 0 ..< activeNX {
        for y in 0 ..< ny {
          let mat = volume.materialAt(x: x, y: y, z: z, maxSliceX: clampedSliceX, maxSliceZ: clampedSliceZ)
          guard mat >= 0 else { continue }

          if volume.materialAt(x: x, y: y, z: z + 1, maxSliceX: clampedSliceX, maxSliceZ: clampedSliceZ) < 0 {
            maskPosZ[x * ny + y] = mat
            hasPosZ = true
          }
          if volume.materialAt(x: x, y: y, z: z - 1, maxSliceX: clampedSliceX, maxSliceZ: clampedSliceZ) < 0 {
            maskNegZ[x * ny + y] = mat
            hasNegZ = true
          }
        }
      }

      if hasPosZ {
        let pz = worldZ(z + 1)
        greedyMerge2D(width: activeNX, height: ny, mask: &maskPosZ) { x0Idx, y0Idx, wX, hY, mat in
          let x0 = worldX(x0Idx)
          let x1 = worldX(x0Idx + wX)
          let y0 = worldY(y0Idx)
          let y1 = worldY(y0Idx + hY)
          // CCW for +Z (0, 0, 1): (x0, y0, pz) -> (x1, y0, pz) -> (x1, y1, pz) -> (x0, y1, pz)
          emitQuad(
            SIMD3<Float>(x0, y0, pz),
            SIMD3<Float>(x1, y0, pz),
            SIMD3<Float>(x1, y1, pz),
            SIMD3<Float>(x0, y1, pz),
            normal: SIMD3<Float>(0, 0, 1),
            materialIndex: UInt32(mat)
          )
        }
      }

      if hasNegZ {
        let pz = worldZ(z)
        greedyMerge2D(width: activeNX, height: ny, mask: &maskNegZ) { x0Idx, y0Idx, wX, hY, mat in
          let x0 = worldX(x0Idx)
          let x1 = worldX(x0Idx + wX)
          let y0 = worldY(y0Idx)
          let y1 = worldY(y0Idx + hY)
          // CCW for -Z (0, 0, -1): (x1, y0, pz) -> (x0, y0, pz) -> (x0, y1, pz) -> (x1, y1, pz)
          emitQuad(
            SIMD3<Float>(x1, y0, pz),
            SIMD3<Float>(x0, y0, pz),
            SIMD3<Float>(x0, y1, pz),
            SIMD3<Float>(x1, y1, pz),
            normal: SIMD3<Float>(0, 0, -1),
            materialIndex: UInt32(mat)
          )
        }
      }
    }

    guard !positions.isEmpty else { return nil }

    var descriptor = MeshDescriptor(name: "SubsurfaceVoxelManifold")
    descriptor.positions = MeshBuffers.Positions(positions)
    descriptor.normals = MeshBuffers.Normals(normals)
    descriptor.primitives = .triangles(indices)
    descriptor.materials = .perFace(faceMaterials)

    return try? MeshResource.generate(from: [descriptor])
  }

  /// Run-Length 2D Greedy Meshing over a `width × height` face mask.
  /// Merges contiguous 1m quads with identical material into single rectangular quads `(w × h)`.
  private static func greedyMerge2D(
    width: Int,
    height: Int,
    mask: inout [Int16],
    emit: (_ u0: Int, _ v0: Int, _ w: Int, _ h: Int, _ material: Int16) -> Void
  ) {
    for u in 0 ..< width {
      var v = 0
      while v < height {
        let mat = mask[u * height + v]
        guard mat >= 0 else {
          v += 1
          continue
        }

        // 1. Expand run along V (height)
        var h = 1
        while (v + h) < height, mask[u * height + (v + h)] == mat {
          h += 1
        }

        // 2. Expand run along U (width) as far as all rows in [v ..< v + h] match `mat`
        var w = 1
        outerExpand: while (u + w) < width {
          let colBase = (u + w) * height
          for dv in 0 ..< h {
            if mask[colBase + v + dv] != mat {
              break outerExpand
            }
          }
          w += 1
        }

        // 3. Emit single merged quad for the (w × h) block
        emit(u, v, w, h, mat)

        // 4. Clear visited cells in mask
        for du in 0 ..< w {
          let colBase = (u + du) * height
          for dv in 0 ..< h {
            mask[colBase + v + dv] = -1
          }
        }

        v += h
      }
    }
  }

  // MARK: - Mathematical Screen-to-Grid Raycasting (Zero Physics Engine Overhead)

  /// Resolves the surface voxel and indicates whether the tap occurred specifically on the top surface plane (`Y = 0`).
  static func pickSurfaceVoxelWithFace(
    rayOrigin: SIMD3<Float>,
    rayDirection: SIMD3<Float>,
    volume: SubsurfaceVoxelVolume,
    maxSliceX: Int,
    maxSliceZ: Int
  ) -> (voxel: SoilVoxel, isTopSurface: Bool, hitPoint: SIMD3<Float>)? {
    let dir = simd_normalize(rayDirection)

    // 1. Analytical intersection with top plane Y = 0:
    if abs(dir.y) > 1e-5 {
      let tTop = -rayOrigin.y / dir.y
      if tTop > 0 {
        let hitPoint = rayOrigin + tTop * dir
        let xGrid = Int((hitPoint.x + volume.centerX).rounded())
        let zGrid = Int((hitPoint.z + volume.centerZ).rounded())

        if xGrid >= 0, xGrid <= maxSliceX,
           zGrid >= 0, zGrid <= maxSliceZ
        {
          let surfaceCoord = GridCoord(x: xGrid, y: volume.ny - 1, z: zGrid)
          if let voxel = volume.voxels[surfaceCoord] {
            return (voxel: voxel, isTopSurface: true, hitPoint: SIMD3<Float>(hitPoint.x, 0.0, hitPoint.z))
          }
        }
      }
    }

    // 2. Fallback: Ray-box slab intersection with the sliced 3D bounding box for side-wall taps
    if let voxel = pickSurfaceVoxel(
      rayOrigin: rayOrigin,
      rayDirection: rayDirection,
      volume: volume,
      maxSliceX: maxSliceX,
      maxSliceZ: maxSliceZ
    ) {
      let pos = volume.worldPosition(for: voxel.coord)
      return (voxel: voxel, isTopSurface: voxel.coord.y == volume.ny - 1, hitPoint: pos)
    }

    return nil
  }

  /// Analytically intersects a ray in the voxel root entity's local space with the top surface plane `Y = 0`
  /// (and active sliced volume bounds), resolving the discrete `SoilVoxel` in `O(1)` time from `[GridCoord: SoilVoxel]`.
  static func pickSurfaceVoxel(
    rayOrigin: SIMD3<Float>,
    rayDirection: SIMD3<Float>,
    volume: SubsurfaceVoxelVolume,
    maxSliceX: Int,
    maxSliceZ: Int
  ) -> SoilVoxel? {
    let dir = simd_normalize(rayDirection)

    // 1. Analytical intersection with top plane Y = 0:
    //    P(t) = rayOrigin + t * dir, solve P_y(t) = 0 -> t = -rayOrigin.y / dir.y
    if abs(dir.y) > 1e-5 {
      let tTop = -rayOrigin.y / dir.y
      if tTop > 0 {
        let hitPoint = rayOrigin + tTop * dir
        // Apply exact analytical formula:
        // X_grid = round(P_x + centerX), Z_grid = round(P_z + centerZ)
        let xGrid = Int((hitPoint.x + volume.centerX).rounded())
        let zGrid = Int((hitPoint.z + volume.centerZ).rounded())

        if xGrid >= 0, xGrid <= maxSliceX,
           zGrid >= 0, zGrid <= maxSliceZ
        {
          let surfaceCoord = GridCoord(x: xGrid, y: volume.ny - 1, z: zGrid)
          if let voxel = volume.voxels[surfaceCoord] {
            return voxel
          }
        }
      }
    }

    // 2. Fallback: Ray-box slab intersection with the sliced 3D bounding box for side-wall taps
    let minBound = SIMD3<Float>(
      -0.5 - volume.centerX,
      -Float(volume.ny),
      -0.5 - volume.centerZ
    )
    let maxBound = SIMD3<Float>(
      Float(maxSliceX) + 0.5 - volume.centerX,
      0.0,
      Float(maxSliceZ) + 0.5 - volume.centerZ
    )

    let invDir = SIMD3<Float>(
      abs(dir.x) > 1e-6 ? 1.0 / dir.x : .greatestFiniteMagnitude,
      abs(dir.y) > 1e-6 ? 1.0 / dir.y : .greatestFiniteMagnitude,
      abs(dir.z) > 1e-6 ? 1.0 / dir.z : .greatestFiniteMagnitude
    )

    let t1 = (minBound - rayOrigin) * invDir
    let t2 = (maxBound - rayOrigin) * invDir
    let tMinVec = simd_min(t1, t2)
    let tMaxVec = simd_max(t1, t2)

    let tNear = max(tMinVec.x, max(tMinVec.y, tMinVec.z))
    let tFar = min(tMaxVec.x, min(tMaxVec.y, tMaxVec.z))

    guard tNear <= tFar, tFar > 0 else { return nil }

    let totalSteps = 32
    let startT = max(tNear, 0.0)
    let stepT = (tFar - startT) / Float(totalSteps)

    for i in 0 ... totalSteps {
      let p = rayOrigin + (startT + Float(i) * stepT) * dir
      let xGrid = Int((p.x + volume.centerX).rounded())
      let zGrid = Int((p.z + volume.centerZ).rounded())
      let yGrid = min(max(Int((p.y + Float(volume.ny - 1) + 0.5).rounded()), 0), volume.ny - 1)

      if xGrid >= 0, xGrid <= maxSliceX,
         zGrid >= 0, zGrid <= maxSliceZ
      {
        let coord = GridCoord(x: xGrid, y: yGrid, z: zGrid)
        if let voxel = volume.voxels[coord] {
          return voxel
        }
      }
    }

    return nil
  }

  // MARK: - Helpers

  private static func stratifiedLayer(forAdjustedDepth d: Double) -> SoilLayerType {
    switch d {
    case ..<0.12:
      .sensitiveFineGrained
    case 0.12 ..< 0.24:
      .organicClay
    case 0.24 ..< 0.37:
      .clayToSiltyClay
    case 0.37 ..< 0.50:
      .siltMixtures
    case 0.50 ..< 0.63:
      .sandMixtures
    case 0.63 ..< 0.76:
      .cleanSands
    case 0.76 ..< 0.89:
      .denseSandToGravelly
    default:
      .stiffSandToClayey
    }
  }

  private static func isPointInPolygon(
    x: Double,
    z: Double,
    polygon: [(x: Double, z: Double)]
  ) -> Bool {
    guard polygon.count >= 3 else { return true }
    var inside = false
    var j = polygon.count - 1
    for i in 0 ..< polygon.count {
      let xi = polygon[i].x, zi = polygon[i].z
      let xj = polygon[j].x, zj = polygon[j].z
      let intersect = ((zi > z) != (zj > z)) &&
        (x < (xj - xi) * (z - zi) / ((zj - zi) == 0 ? 1e-12 : (zj - zi)) + xi)
      if intersect {
        inside.toggle()
      }
      j = i
    }
    return inside
  }
}
