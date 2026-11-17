import CoreLocation
import Foundation
import RealityKit
import simd
import UIKit

/// Master 4-class geotechnical texture categories mapped to macro photo assets.
enum SoilTextureCategory: String, CaseIterable, Sendable {
  case clay
  case silt
  case sand
  case gravel
}

extension SoilLayerType {
  var textureCategory: SoilTextureCategory {
    switch self {
    case .sensitiveFineGrained, .organicClay, .clayToSiltyClay, .stiffFineGrained:
      return .clay
    case .siltMixtures:
      return .silt
    case .sandMixtures, .cleanSands, .stiffSandToClayey:
      return .sand
    case .denseSandToGravelly:
      return .gravel
    }
  }

  var typicalRoughness: Float {
    switch self {
    case .sensitiveFineGrained, .organicClay:
      return 0.74
    case .clayToSiltyClay, .stiffFineGrained:
      return 0.82
    case .siltMixtures:
      return 0.88
    case .sandMixtures, .stiffSandToClayey:
      return 0.93
    case .cleanSands:
      return 0.95
    case .denseSandToGravelly:
      return 0.98
    }
  }
}

/// In-memory caching manager for geotechnical macro photo textures.
@MainActor
final class SoilTextureManager {
  static let shared = SoilTextureManager()
  private var cachedTextures: [SoilTextureCategory: TextureResource] = [:]

  func texture(for category: SoilTextureCategory) -> TextureResource? {
    if let cached = cachedTextures[category] {
      return cached
    }

    let name = "soil_\(category.rawValue)"

    // 1. Check main bundle / Assets.xcassets
    if let res = try? TextureResource.load(named: name) {
      cachedTextures[category] = res
      return res
    }

    // 2. Check direct file paths in Resources/Textures
    let candidates = [
      Bundle.main.path(forResource: name, ofType: "png"),
      Bundle.main.path(forResource: name, ofType: "jpg"),
      "/Users/royyan/Developments/ada/challenge-6/GeoSome/GeoSome/Resources/Textures/\(name).png",
      "/Users/royyan/Developments/ada/challenge-6/GeoSome/GeoSome/Resources/Textures/\(name).jpg"
    ].compactMap { $0 }

    for path in candidates {
      if let image = UIImage(contentsOfFile: path), let cgImage = image.cgImage {
        if let res = try? TextureResource(image: cgImage, options: .init(semantic: .color)) {
          cachedTextures[category] = res
          return res
        }
      }
    }

    return nil
  }
}

enum VoxelMeshSynthesizer {
  /// Builds the shared palette of materials corresponding to `SoilLayerType.allCases`.
  /// Uses photo-macro textures tinted with `layer.uiColor` and physically-based roughness
  /// with `meshDescriptor.materials = .perFace(...)` so the entire voxel volume renders in 1 draw call.
  @MainActor
  static func makeMaterialPalette() -> [SimpleMaterial] {
    let textureManager = SoilTextureManager.shared
    return SoilLayerType.allCases.map { layer in
      var material = SimpleMaterial()
      if let tex = textureManager.texture(for: layer.textureCategory) {
        material.color = .init(tint: layer.uiColor, texture: .init(tex))
      } else {
        material.color = .init(tint: layer.uiColor)
      }
      material.roughness = .init(floatLiteral: layer.typicalRoughness)
      material.metallic = .init(floatLiteral: 0.0)
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

    // SchemaGAN 3D reconstruction when CPT points exist
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

    let stepXM = Float(rawWidthM) / Float(max(nx - 1, 1))
    let stepZM = Float(rawLengthM) / Float(max(nz - 1, 1))
    let maxObservedDepth = cptPoints.flatMap(\.rows).map(\.depth).max() ?? 15.0
    let totalDepthM: Float
    if let g = schemaGrid {
      let gridDepthM = Double(max(g.nz - 1, 1)) * g.dzM
      totalDepthM = Float(max(gridDepthM, maxObservedDepth, 5.0))
    } else {
      totalDepthM = Float(max(maxObservedDepth, 12.0))
    }
    let stepYM = totalDepthM / Float(ny)

    // Project boundary vertices into normalized UV [0 ... 1] and grid space [0 ... nx-1] x [0 ... nz-1]
    // Note: Z in 3D space corresponds to North (-Z, v=0) -> South (+Z, v=1).
    let boundaryUVs: [SIMD2<Float>] = polygon.map { coord in
      let normX = Float((coord.longitude - minLon) / max(maxLon - minLon, 1e-9))
      let normZ = Float(1.0 - ((coord.latitude - minLat) / max(maxLat - minLat, 1e-9)))
      return SIMD2<Float>(min(max(normX, 0.0), 1.0), min(max(normZ, 0.0), 1.0))
    }

    let polyGridXZ: [(x: Double, z: Double)] = boundaryUVs.map { uv in
      (Double(uv.x) * Double(nx - 1), Double(uv.y) * Double(nz - 1))
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

    let centerX = Float(nx - 1) * 0.5
    let centerZ = Float(nz - 1) * 0.5

    var voxels: [GridCoord: SoilVoxel] = [:]
    voxels.reserveCapacity(nx * nz * ny)
    var bearingVoxels: [ColumnCoord: BearingLayerVoxel] = [:]
    bearingVoxels.reserveCapacity(nx * nz)
    var flatMaterialGrid = Array(repeating: Int16(-1), count: nx * nz * ny)

    for ix in 0 ..< nx {
      let fx = Double(ix) / Double(max(nx - 1, 1))
      let lon = minLon + fx * (maxLon - minLon)

      for iz in 0 ..< nz where activeColumns[ix][iz] {
        let fz = Double(iz) / Double(max(nz - 1, 1))
        let fy = 1.0 - fz // South (0.0) -> North (1.0) in SchemaGAN grid space
        let lat = maxLat - fz * (maxLat - minLat)

        if let g = schemaGrid, let r = schemaRecon {
          // 1. Sample full vertical SchemaGAN Ic profile for this (ix, iz) column
          var columnIcs = [Double](repeating: 2.5, count: ny)
          var firstBearingDepthM: Float?
          var minColumnIc = Double.greatestFiniteMagnitude
          var minColumnIcDepthM: Float = totalDepthM * 0.5

          for depthIndexFromTop in 0 ..< ny {
            let normalizedDepth = (Double(depthIndexFromTop) + 0.5) / Double(ny)
            let icVal = sampleReconstructedIc(
              recon: r.reconstructedIc,
              grid: g,
              fx: fx,
              fy: fy,
              fzDepth: normalizedDepth
            )
            columnIcs[depthIndexFromTop] = icVal
            let centerDepthM = (Float(depthIndexFromTop) + 0.5) * stepYM
            if icVal < minColumnIc {
              minColumnIc = icVal
              minColumnIcDepthM = centerDepthM
            }
            if firstBearingDepthM == nil, icVal <= 2.05 {
              firstBearingDepthM = centerDepthM
            }
          }

          let midIc = columnIcs[ny / 2]
          let reconBias = (midIc - 2.65) * 0.04
          let uNorm = Float(fx)
          let vNorm = Float(fz)
          let fallbackRatio = evaluateBearingDepthRatio(u: uNorm, v: vNorm, bias: Float(reconBias))
          let predictedBearingDepthM = firstBearingDepthM
            ?? min(max(minColumnIcDepthM, 2.7), max(totalDepthM * 0.85, 4.9))
          let normalizedBearingRatio = min(max((predictedBearingDepthM - 2.7) / max(totalDepthM - 2.7, 2.2), 0.0), 1.0)
          let blendedRatio = 0.65 * normalizedBearingRatio + 0.35 * fallbackRatio

          let colCoord = ColumnCoord(x: ix, z: iz)
          bearingVoxels[colCoord] = BearingLayerVoxel(
            coord: colCoord,
            latitude: lat,
            longitude: lon,
            bearingDepthM: predictedBearingDepthM,
            normalizedDepthRatio: blendedRatio,
            coneResistanceMPa: 15.0 + (1.0 - blendedRatio) * 9.5,
            soilBehaviorIndexIc: Float(min(max(minColumnIc, 1.30), 2.20)),
            layerThicknessM: 1.1 + (1.0 - blendedRatio) * 1.4,
            uncertaintyPercent: 9.0 + vNorm * 6.0
          )

          // 2. Populate vertical column directly from SchemaGAN 3D reconstructed Ic
          for iy in 0 ..< ny {
            let depthIndexFromTop = (ny - 1) - iy
            let normalizedDepth = (Double(depthIndexFromTop) + 0.5) / Double(ny)
            let voxelIc = columnIcs[depthIndexFromTop]
            let soilType = SoilLayerType.fromRobertsonIc(voxelIc, depthRatio: normalizedDepth)
            let topDepth = Float(depthIndexFromTop) * stepYM
            let bottomDepth = Float(depthIndexFromTop + 1) * stepYM
            let coord = GridCoord(x: ix, y: iy, z: iz)

            let voxel = SoilVoxel(
              coord: coord,
              latitude: lat,
              longitude: lon,
              topDepthM: topDepth,
              bottomDepthM: bottomDepth,
              layerIdx: depthIndexFromTop,
              soilClassification: soilType,
              robertsonIc: Float(voxelIc),
              moisturePercent: soilType.typicalMoisturePercent,
              bearingCapacityKPa: soilType.typicalBearingCapacityKPa,
              bearingLayerDepthM: predictedBearingDepthM
            )

            voxels[coord] = voxel
            flatMaterialGrid[(ix * nz * ny) + (iz * ny) + iy] = Int16(soilType.rawValue)
          }
        } else {
          // Fallback synthetic stratigraphy when no CPT points exist (e.g. Xcode Previews)
          let wave1 = sin(fx * .pi * 2.1 + fz * 1.4) * 0.055
          let wave2 = cos(fz * .pi * 1.8 - fx * 1.1) * 0.045
          let dip = (fx * 0.06) - (fz * 0.04)
          let horizonShift = wave1 + wave2 + dip

          let uNorm = Float(fx)
          let vNorm = Float(fz)
          let rawDepthRatio = evaluateBearingDepthRatio(u: uNorm, v: vNorm, bias: 0.0)
          let predictedBearingDepthM = 2.7 + rawDepthRatio * (4.9 - 2.7)
          let colCoord = ColumnCoord(x: ix, z: iz)
          bearingVoxels[colCoord] = BearingLayerVoxel(
            coord: colCoord,
            latitude: lat,
            longitude: lon,
            bearingDepthM: predictedBearingDepthM,
            normalizedDepthRatio: rawDepthRatio,
            coneResistanceMPa: 15.0 + (1.0 - rawDepthRatio) * 9.5,
            soilBehaviorIndexIc: 1.42 + rawDepthRatio * 0.36,
            layerThicknessM: 1.1 + (1.0 - rawDepthRatio) * 1.4,
            uncertaintyPercent: 9.0 + vNorm * 6.0
          )

          for iy in 0 ..< ny {
            let depthIndexFromTop = (ny - 1) - iy
            let normalizedDepth = (Double(depthIndexFromTop) + 0.5) / Double(ny)
            let adjustedDepth = min(max(normalizedDepth + horizonShift, 0.0), 0.999)

            let soilType = stratifiedLayer(forAdjustedDepth: adjustedDepth)
            let topDepth = Float(depthIndexFromTop) * stepYM
            let bottomDepth = Float(depthIndexFromTop + 1) * stepYM
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
              bearingCapacityKPa: soilType.typicalBearingCapacityKPa,
              bearingLayerDepthM: predictedBearingDepthM
            )

            voxels[coord] = voxel
            flatMaterialGrid[(ix * nz * ny) + (iz * ny) + iy] = Int16(soilType.rawValue)
          }
        }
      }
    }

    // Compute local 3D surface positions (grid units & true metric meters) and normalized UVs for CPT borehole pins
    var cptPositions: [SIMD3<Float>] = []
    var cptMetricPositions: [SIMD3<Float>] = []
    var cptUVs: [SIMD2<Float>] = []
    if !cptPoints.isEmpty {
      for point in cptPoints {
        let normX = min(max((point.coordinate.longitude - minLon) / max(maxLon - minLon, 1e-9), 0.04), 0.96)
        let normZ = min(max(1.0 - ((point.coordinate.latitude - minLat) / max(maxLat - minLat, 1e-9)), 0.04), 0.96)
        let continuousGX = Float(normX * Double(nx - 1))
        let continuousGZ = Float(normZ * Double(nz - 1))
        let gx = min(max(Int(continuousGX.rounded()), 0), nx - 1)
        let gz = min(max(Int(continuousGZ.rounded()), 0), nz - 1)
        let wx = Float(gx) - centerX
        let wz = Float(gz) - centerZ
        cptPositions.append(SIMD3<Float>(wx, 0.0, wz))
        let metricWX = (continuousGX - centerX) * stepXM
        let metricWZ = (continuousGZ - centerZ) * stepZM
        cptMetricPositions.append(SIMD3<Float>(metricWX, 0.0, metricWZ))
        cptUVs.append(SIMD2<Float>(Float(normX), Float(normZ)))
      }
    } else {
      // Sample 3 reference CPT borehole markers strictly inside the active boundary polygon
      let targetFractions: [Double] = [0.27, 0.58, 0.85]
      for frac in targetFractions {
        let targetIX = min(max(Int((frac * Double(nx - 1)).rounded()), 1), nx - 2)
        // Find active Z span at targetIX (or nearest active column)
        var bestIX = targetIX
        var activeZs: [Int] = []
        for radius in 0 ..< nx {
          let candidates = radius == 0 ? [targetIX] : [targetIX - radius, targetIX + radius]
          for cix in candidates where cix >= 0 && cix < nx {
            let zs = (0 ..< nz).filter { activeColumns[cix][$0] }
            if !zs.isEmpty {
              bestIX = cix
              activeZs = zs
              break
            }
          }
          if !activeZs.isEmpty { break }
        }
        let chosenIZ = activeZs.isEmpty ? (nz / 2) : activeZs[activeZs.count / 2]
        let wx = Float(bestIX) - centerX
        let wz = Float(chosenIZ) - centerZ
        cptPositions.append(SIMD3<Float>(wx, 0.0, wz))
        cptMetricPositions.append(SIMD3<Float>(wx * stepXM, 0.0, wz * stepZM))
        let u = Float(bestIX) / Float(max(nx - 1, 1))
        let v = Float(chosenIZ) / Float(max(nz - 1, 1))
        cptUVs.append(SIMD2<Float>(u, v))
      }
    }

    return SubsurfaceVoxelVolume(
      voxels: voxels,
      bearingVoxels: bearingVoxels,
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
      cptSurfacePositions: cptPositions,
      cptMetricSurfacePositions: cptMetricPositions,
      minLatitude: minLat,
      maxLatitude: maxLat,
      minLongitude: minLon,
      maxLongitude: maxLon,
      boundaryPolygonUV: boundaryUVs,
      cptNormalizedUVs: cptUVs
    )
  }

  /// Synthesizes the active subsurface geological volume into a single `MeshDescriptor` (1 Draw Call) using:
  /// 1. Smooth Clipped Polygon Extrusion matching the exact user-drawn property boundary (Option 1)
  /// 2. Sutherland-Hodgman clipping against active slicing thresholds (`maxSliceX`, `maxSliceZ`)
  /// 3. Ear-Clipping triangulation for flat top (`Y = 0`) and bottom (`Y = -depthYM`) surface caps
  /// 4. Continuous side-wall stratigraphy extruded vertically along perimeter and slice boundaries
  /// 5. `.perFace` material indexing (`meshDescriptor.materials = .perFace(...)`)
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
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []
    var faceMaterials: [UInt32] = []

    positions.reserveCapacity(4096)
    normals.reserveCapacity(4096)
    uvs.reserveCapacity(4096)
    indices.reserveCapacity(6144)
    faceMaterials.reserveCapacity(2048)

    let uvScale: Float = 0.5 // 1 texture tile every 2.0 meters for realistic macro soil grain scale

    // Helper that appends a quad with strict CCW winding for outward normal `normal`
    @inline(__always)
    func emitQuad(
      _ v0: SIMD3<Float>,
      _ v1: SIMD3<Float>,
      _ v2: SIMD3<Float>,
      _ v3: SIMD3<Float>,
      uv0: SIMD2<Float>,
      uv1: SIMD2<Float>,
      uv2: SIMD2<Float>,
      uv3: SIMD2<Float>,
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

      uvs.append(uv0)
      uvs.append(uv1)
      uvs.append(uv2)
      uvs.append(uv3)

      // Triangle 1: (v0, v1, v2), Triangle 2: (v0, v2, v3)
      indices.append(base)
      indices.append(base + 1)
      indices.append(base + 2)

      indices.append(base)
      indices.append(base + 2)
      indices.append(base + 3)

      faceMaterials.append(materialIndex)
      faceMaterials.append(materialIndex)
    }

    // Coordinate conversion helpers (True Metric Space: 1 unit = 1 meter):
    let stepXM = volume.cellStepXM
    let stepYM = volume.cellStepYM
    let stepZM = volume.cellStepZM

    @inline(__always)
    func worldY(_ gridEdgeY: Int) -> Float {
      ((Float(gridEdgeY) - 0.5) - topYIndex - 0.5) * stepYM
    }

    @inline(__always)
    func sampleMaterial(xM: Float, zM: Float, layerY: Int) -> UInt32 {
      let (fx, fz) = volume.continuousGridCoordinates(forMetricX: xM, zM: zM)
      let gx = min(max(Int(fx.rounded()), 0), nx - 1)
      let gz = min(max(Int(fz.rounded()), 0), nz - 1)
      let clampedY = min(max(layerY, 0), ny - 1)
      let rawMat = volume.materialAt(x: gx, y: clampedY, z: gz, maxSliceX: clampedSliceX, maxSliceZ: clampedSliceZ)
      if rawMat >= 0 {
        return UInt32(rawMat)
      }
      for r in 1 ... 3 {
        for dx in -r ... r {
          for dz in -r ... r {
            let nMat = volume.materialAt(x: gx + dx, y: clampedY, z: gz + dz, maxSliceX: clampedSliceX, maxSliceZ: clampedSliceZ)
            if nMat >= 0 { return UInt32(nMat) }
          }
        }
      }
      return 0
    }

    // 1. Build initial metric 2D boundary polygon from `volume.boundaryPolygonUV`
    var rawPolygon: [SIMD2<Float>] = []
    let halfWidthM = volume.widthXM * 0.5
    let halfLengthM = volume.lengthZM * 0.5

    if volume.boundaryPolygonUV.count >= 3 {
      rawPolygon = volume.boundaryPolygonUV.map { uv in
        SIMD2<Float>(
          (uv.x - 0.5) * volume.widthXM,
          (uv.y - 0.5) * volume.lengthZM
        )
      }
    } else {
      rawPolygon = [
        SIMD2<Float>(-halfWidthM, -halfLengthM),
        SIMD2<Float>(halfWidthM, -halfLengthM),
        SIMD2<Float>(halfWidthM, halfLengthM),
        SIMD2<Float>(-halfWidthM, halfLengthM)
      ]
    }

    rawPolygon = cleanPolygonVertices(rawPolygon)
    guard rawPolygon.count >= 3 else { return nil }

    // Ensure CCW winding (signedArea > 0)
    if polygonSignedArea(rawPolygon) < 0 {
      rawPolygon.reverse()
    }

    // 2. Compute slicing limits in metric coordinates
    let xCut = (Float(clampedSliceX) + 0.5 - centerX) * stepXM
    let zCut = (Float(clampedSliceZ) + 0.5 - centerZ) * stepZM
    let xMin = (-0.5 - centerX) * stepXM
    let zMin = (-0.5 - centerZ) * stepZM

    // 3. Sutherland-Hodgman clipping against active slicing box
    var clippedPoly = rawPolygon

    // Clip X <= xCut
    clippedPoly = clipPolygon(clippedPoly, inside: { $0.x <= xCut + 1e-4 }) { p1, p2 in
      let denom = p2.x - p1.x
      let t = abs(denom) > 1e-7 ? (xCut - p1.x) / denom : 0.0
      return SIMD2<Float>(xCut, p1.y + t * (p2.y - p1.y))
    }

    // Clip Z <= zCut
    clippedPoly = clipPolygon(clippedPoly, inside: { $0.y <= zCut + 1e-4 }) { p1, p2 in
      let denom = p2.y - p1.y
      let t = abs(denom) > 1e-7 ? (zCut - p1.y) / denom : 0.0
      return SIMD2<Float>(p1.x + t * (p2.x - p1.x), zCut)
    }

    // Clip X >= xMin
    clippedPoly = clipPolygon(clippedPoly, inside: { $0.x >= xMin - 1e-4 }) { p1, p2 in
      let denom = p2.x - p1.x
      let t = abs(denom) > 1e-7 ? (xMin - p1.x) / denom : 0.0
      return SIMD2<Float>(xMin, p1.y + t * (p2.y - p1.y))
    }

    // Clip Z >= zMin
    clippedPoly = clipPolygon(clippedPoly, inside: { $0.y >= zMin - 1e-4 }) { p1, p2 in
      let denom = p2.y - p1.y
      let t = abs(denom) > 1e-7 ? (zMin - p1.y) / denom : 0.0
      return SIMD2<Float>(p1.x + t * (p2.x - p1.x), zMin)
    }

    clippedPoly = cleanPolygonVertices(clippedPoly)
    guard clippedPoly.count >= 3 else { return nil }

    if polygonSignedArea(clippedPoly) < 0 {
      clippedPoly.reverse()
    }

    // 4. Subdivide long edges so strata variations are sampled faithfully
    let maxEdgeLen = max(stepXM, stepZM) * 1.5
    var subdividedPoly: [SIMD2<Float>] = []
    subdividedPoly.reserveCapacity(clippedPoly.count * 4)

    for i in 0 ..< clippedPoly.count {
      let p0 = clippedPoly[i]
      let p1 = clippedPoly[(i + 1) % clippedPoly.count]
      let edgeVec = p1 - p0
      let edgeLen = simd_length(edgeVec)

      subdividedPoly.append(p0)
      if edgeLen > maxEdgeLen {
        let subs = Int(ceil(edgeLen / maxEdgeLen))
        for s in 1 ..< subs {
          let t = Float(s) / Float(subs)
          subdividedPoly.append(p0 + t * edgeVec)
        }
      }
    }
    subdividedPoly = cleanPolygonVertices(subdividedPoly)
    guard subdividedPoly.count >= 3 else { return nil }

    // 5. Triangulate the 2D polygon with Ear Clipping for Top and Bottom surface caps
    let capTriangles = triangulateConvexOrConcavePolygon(subdividedPoly)

    // 5a. Top Surface Cap (Y = 0, normal = (0, 1, 0))
    for tri in capTriangles {
      let a = tri.0
      let b = tri.1
      let c = tri.2
      let centroid = (a + b + c) / 3.0
      let mat = sampleMaterial(xM: centroid.x, zM: centroid.y, layerY: ny - 1)

      let base = UInt32(positions.count)
      // CCW for +Y: (a, c, b)
      positions.append(SIMD3<Float>(a.x, 0.0, a.y))
      positions.append(SIMD3<Float>(c.x, 0.0, c.y))
      positions.append(SIMD3<Float>(b.x, 0.0, b.y))

      normals.append(SIMD3<Float>(0, 1, 0))
      normals.append(SIMD3<Float>(0, 1, 0))
      normals.append(SIMD3<Float>(0, 1, 0))

      uvs.append(SIMD2<Float>(a.x * uvScale, a.y * uvScale))
      uvs.append(SIMD2<Float>(c.x * uvScale, c.y * uvScale))
      uvs.append(SIMD2<Float>(b.x * uvScale, b.y * uvScale))

      indices.append(base)
      indices.append(base + 1)
      indices.append(base + 2)

      faceMaterials.append(mat)
    }

    // 5b. Bottom Bedrock Cap (Y = -totalDepthM, normal = (0, -1, 0))
    let bottomY = worldY(0)
    for tri in capTriangles {
      let a = tri.0
      let b = tri.1
      let c = tri.2
      let centroid = (a + b + c) / 3.0
      let mat = sampleMaterial(xM: centroid.x, zM: centroid.y, layerY: 0)

      let base = UInt32(positions.count)
      // CCW for -Y: (a, b, c)
      positions.append(SIMD3<Float>(a.x, bottomY, a.y))
      positions.append(SIMD3<Float>(b.x, bottomY, b.y))
      positions.append(SIMD3<Float>(c.x, bottomY, c.y))

      normals.append(SIMD3<Float>(0, -1, 0))
      normals.append(SIMD3<Float>(0, -1, 0))
      normals.append(SIMD3<Float>(0, -1, 0))

      uvs.append(SIMD2<Float>(a.x * uvScale, a.y * uvScale))
      uvs.append(SIMD2<Float>(b.x * uvScale, b.y * uvScale))
      uvs.append(SIMD2<Float>(c.x * uvScale, c.y * uvScale))

      indices.append(base)
      indices.append(base + 1)
      indices.append(base + 2)

      faceMaterials.append(mat)
    }

    // 6. Extrude vertical perimeter and slicing walls along all 2D edges
    let inwardNudge = 0.25 * min(stepXM, stepZM)
    var cumDist: Float = 0.0

    for i in 0 ..< subdividedPoly.count {
      let p0 = subdividedPoly[i]
      let p1 = subdividedPoly[(i + 1) % subdividedPoly.count]
      let dx = p1.x - p0.x
      let dz = p1.y - p0.y
      let len = sqrt(dx * dx + dz * dz)
      guard len > 1e-4 else { continue }
      defer { cumDist += len }

      let normX = dz / len
      let normZ = -dx / len

      // Filter out internal bridge edges from concave polygon clipping:
      // A cut along X = xCut must face outward (+X); a cut along Z = zCut must face outward (+Z).
      if abs(p0.x - xCut) < 1e-3, abs(p1.x - xCut) < 1e-3, normX < 0.2 {
        continue
      }
      if abs(p0.y - zCut) < 1e-3, abs(p1.y - zCut) < 1e-3, normZ < 0.2 {
        continue
      }

      let wallNormal = SIMD3<Float>(normX, 0.0, normZ)
      let midX = (p0.x + p1.x) * 0.5
      let midZ = (p0.y + p1.y) * 0.5
      let sampleX = midX - normX * inwardNudge
      let sampleZ = midZ - normZ * inwardNudge

      let u0 = cumDist * uvScale
      let u1 = (cumDist + len) * uvScale

      var y = 0
      while y < ny {
        let mat = sampleMaterial(xM: sampleX, zM: sampleZ, layerY: y)
        var hY = 1
        while y + hY < ny, sampleMaterial(xM: sampleX, zM: sampleZ, layerY: y + hY) == mat {
          hY += 1
        }

        let yBot = worldY(y)
        let yTop = worldY(y + hY)

        let v0 = SIMD3<Float>(p0.x, yBot, p0.y)
        let v1 = SIMD3<Float>(p0.x, yTop, p0.y)
        let v2 = SIMD3<Float>(p1.x, yTop, p1.y)
        let v3 = SIMD3<Float>(p1.x, yBot, p1.y)

        let uv0 = SIMD2<Float>(u0, yBot * uvScale)
        let uv1 = SIMD2<Float>(u0, yTop * uvScale)
        let uv2 = SIMD2<Float>(u1, yTop * uvScale)
        let uv3 = SIMD2<Float>(u1, yBot * uvScale)

        emitQuad(v0, v1, v2, v3, uv0: uv0, uv1: uv1, uv2: uv2, uv3: uv3, normal: wallNormal, materialIndex: mat)
        y += hY
      }
    }

    guard !positions.isEmpty else { return nil }

    var descriptor = MeshDescriptor(name: "SubsurfaceVoxelManifold")
    descriptor.positions = MeshBuffers.Positions(positions)
    descriptor.normals = MeshBuffers.Normals(normals)
    descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
    descriptor.primitives = .triangles(indices)
    descriptor.materials = .perFace(faceMaterials)

    return try? MeshResource.generate(from: [descriptor])
  }

  // MARK: - 2D Computational Geometry Helpers for Option 1 Visual Mesh Smoothing

  @inline(__always)
  private static func polygonSignedArea(_ polygon: [SIMD2<Float>]) -> Float {
    guard polygon.count >= 3 else { return 0 }
    var area: Float = 0
    let count = polygon.count
    for i in 0 ..< count {
      let j = (i + 1) % count
      area += (polygon[i].x * polygon[j].y) - (polygon[j].x * polygon[i].y)
    }
    return area * 0.5
  }

  private static func cleanPolygonVertices(_ polygon: [SIMD2<Float>]) -> [SIMD2<Float>] {
    guard polygon.count >= 2 else { return polygon }
    var result: [SIMD2<Float>] = []
    result.reserveCapacity(polygon.count)

    for p in polygon {
      if let last = result.last {
        if simd_distance(p, last) > 1e-4 {
          result.append(p)
        }
      } else {
        result.append(p)
      }
    }

    if result.count > 2, let first = result.first, let last = result.last, simd_distance(first, last) <= 1e-4 {
      result.removeLast()
    }
    return result
  }

  private static func clipPolygon(
    _ polygon: [SIMD2<Float>],
    inside: (SIMD2<Float>) -> Bool,
    intersection: (SIMD2<Float>, SIMD2<Float>) -> SIMD2<Float>
  ) -> [SIMD2<Float>] {
    guard polygon.count >= 3 else { return [] }
    var output: [SIMD2<Float>] = []
    output.reserveCapacity(polygon.count + 4)

    var prev = polygon[polygon.count - 1]
    var prevInside = inside(prev)

    for curr in polygon {
      let currInside = inside(curr)
      if currInside {
        if !prevInside {
          output.append(intersection(prev, curr))
        }
        output.append(curr)
      } else if prevInside {
        output.append(intersection(prev, curr))
      }
      prev = curr
      prevInside = currInside
    }
    return output
  }

  private static func triangulateConvexOrConcavePolygon(
    _ poly: [SIMD2<Float>]
  ) -> [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] {
    guard poly.count >= 3 else { return [] }
    if poly.count == 3 {
      return [(poly[0], poly[1], poly[2])]
    }

    var vertices = poly
    var triangles: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = []
    triangles.reserveCapacity(vertices.count - 2)

    var count = vertices.count
    var iterations = 0
    let maxIterations = count * count * 2

    var i = 0
    while count > 3 && iterations < maxIterations {
      iterations += 1
      let prev = (i + count - 1) % count
      let curr = i
      let next = (i + 1) % count

      let a = vertices[prev]
      let b = vertices[curr]
      let c = vertices[next]

      let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
      if cross > 1e-6 {
        var isEar = true
        for k in 0 ..< count where k != prev && k != curr && k != next {
          if isPointInTriangle2D(p: vertices[k], a: a, b: b, c: c) {
            isEar = false
            break
          }
        }

        if isEar {
          triangles.append((a, b, c))
          vertices.remove(at: curr)
          count -= 1
          i = prev % count
          continue
        }
      }

      i = (i + 1) % count
    }

    if vertices.count == 3 {
      triangles.append((vertices[0], vertices[1], vertices[2]))
    }

    return triangles
  }

  @inline(__always)
  private static func isPointInTriangle2D(
    p: SIMD2<Float>,
    a: SIMD2<Float>,
    b: SIMD2<Float>,
    c: SIMD2<Float>
  ) -> Bool {
    let cp1 = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
    let cp2 = (c.x - b.x) * (p.y - b.y) - (c.y - b.y) * (p.x - b.x)
    let cp3 = (a.x - c.x) * (p.y - c.y) - (a.y - c.y) * (p.x - c.x)
    return (cp1 > 1e-6 && cp2 > 1e-6 && cp3 > 1e-6) || (cp1 < -1e-6 && cp2 < -1e-6 && cp3 < -1e-6)
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

  // MARK: - Mathematical Screen-to-Metric-Grid Raycasting (Zero Physics Engine Overhead)

  /// Resolves the surface voxel and exact metric `(x, 0, z)` hit coordinate in meters (`1 unit = 1 meter`),
  /// indicating whether the tap occurred on the top surface plane (`Y = 0`) or a sliced side wall.
  static func pickSurfaceVoxelWithFace(
    rayOrigin: SIMD3<Float>,
    rayDirection: SIMD3<Float>,
    volume: SubsurfaceVoxelVolume,
    maxSliceX: Int,
    maxSliceZ: Int
  ) -> (voxel: SoilVoxel, isTopSurface: Bool, hitPoint: SIMD3<Float>)? {
    let dir = simd_normalize(rayDirection)

    // 1. Analytical intersection with top plane Y = 0 in metric space:
    if abs(dir.y) > 1e-5 {
      let tTop = -rayOrigin.y / dir.y
      if tTop > 0 {
        let hitPoint = rayOrigin + tTop * dir
        if volume.isMetricPointInsideActiveArea(
          xM: hitPoint.x,
          zM: hitPoint.z,
          maxSliceX: maxSliceX,
          maxSliceZ: maxSliceZ
        ) {
          let (fx, fz) = volume.continuousGridCoordinates(forMetricX: hitPoint.x, zM: hitPoint.z)
          let xGrid = min(max(Int(fx.rounded()), 0), volume.nx - 1)
          let zGrid = min(max(Int(fz.rounded()), 0), volume.nz - 1)
          let surfaceCoord = GridCoord(x: xGrid, y: volume.ny - 1, z: zGrid)
          if let voxel = volume.voxels[surfaceCoord] {
            return (
              voxel: voxel,
              isTopSurface: true,
              hitPoint: SIMD3<Float>(hitPoint.x, 0.0, hitPoint.z)
            )
          } else {
            for r in 1 ... 3 {
              for dx in -r ... r {
                for dz in -r ... r {
                  let altCoord = GridCoord(
                    x: min(max(xGrid + dx, 0), volume.nx - 1),
                    y: volume.ny - 1,
                    z: min(max(zGrid + dz, 0), volume.nz - 1)
                  )
                  if let altVoxel = volume.voxels[altCoord] {
                    return (
                      voxel: altVoxel,
                      isTopSurface: true,
                      hitPoint: SIMD3<Float>(hitPoint.x, 0.0, hitPoint.z)
                    )
                  }
                }
              }
            }
          }
        }
      }
    }

    // 2. Fallback: Ray-box slab intersection with the sliced 3D metric bounding box for side-wall taps
    if let hit = pickSurfaceVoxelWithMetricPoint(
      rayOrigin: rayOrigin,
      rayDirection: rayDirection,
      volume: volume,
      maxSliceX: maxSliceX,
      maxSliceZ: maxSliceZ
    ) {
      return (
        voxel: hit.voxel,
        isTopSurface: hit.voxel.coord.y == volume.ny - 1,
        hitPoint: SIMD3<Float>(hit.metricPoint.x, 0.0, hit.metricPoint.z)
      )
    }

    return nil
  }

  /// Analytically intersects a ray in metric world space (`1 unit = 1 meter`) with the top surface plane `Y = 0`
  /// and active sliced volume bounds, resolving the discrete `SoilVoxel` and exact metric hit location.
  static func pickSurfaceVoxel(
    rayOrigin: SIMD3<Float>,
    rayDirection: SIMD3<Float>,
    volume: SubsurfaceVoxelVolume,
    maxSliceX: Int,
    maxSliceZ: Int
  ) -> SoilVoxel? {
    pickSurfaceVoxelWithMetricPoint(
      rayOrigin: rayOrigin,
      rayDirection: rayDirection,
      volume: volume,
      maxSliceX: maxSliceX,
      maxSliceZ: maxSliceZ
    )?.voxel
  }

  private static func pickSurfaceVoxelWithMetricPoint(
    rayOrigin: SIMD3<Float>,
    rayDirection: SIMD3<Float>,
    volume: SubsurfaceVoxelVolume,
    maxSliceX: Int,
    maxSliceZ: Int
  ) -> (voxel: SoilVoxel, metricPoint: SIMD3<Float>)? {
    let dir = simd_normalize(rayDirection)
    let stepXM = max(volume.cellStepXM, 1e-4)
    let stepYM = max(volume.cellStepYM, 1e-4)
    let stepZM = max(volume.cellStepZM, 1e-4)

    // 1. Analytical intersection with top plane Y = 0:
    if abs(dir.y) > 1e-5 {
      let tTop = -rayOrigin.y / dir.y
      if tTop > 0 {
        let hitPoint = rayOrigin + tTop * dir
        let xGrid = Int(((hitPoint.x / stepXM) + volume.centerX).rounded())
        let zGrid = Int(((hitPoint.z / stepZM) + volume.centerZ).rounded())

        if xGrid >= 0, xGrid <= maxSliceX,
           zGrid >= 0, zGrid <= maxSliceZ
        {
          let surfaceCoord = GridCoord(x: xGrid, y: volume.ny - 1, z: zGrid)
          if let voxel = volume.voxels[surfaceCoord] {
            return (voxel, hitPoint)
          }
        }
      }
    }

    // 2. Fallback: Ray-box slab intersection with the sliced 3D metric bounding box for side-wall taps
    let minBound = SIMD3<Float>(
      (-0.5 - volume.centerX) * stepXM,
      -Float(volume.ny) * stepYM,
      (-0.5 - volume.centerZ) * stepZM
    )
    let maxBound = SIMD3<Float>(
      (Float(maxSliceX) + 0.5 - volume.centerX) * stepXM,
      0.0,
      (Float(maxSliceZ) + 0.5 - volume.centerZ) * stepZM
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

    let totalSteps = 48
    let startT = max(tNear, 0.0)
    let stepT = (tFar - startT) / Float(totalSteps)

    for i in 0 ... totalSteps {
      let p = rayOrigin + (startT + Float(i) * stepT) * dir
      let xGrid = Int(((p.x / stepXM) + volume.centerX).rounded())
      let zGrid = Int(((p.z / stepZM) + volume.centerZ).rounded())
      let yGrid = min(max(Int(((p.y / stepYM) + Float(volume.ny - 1) + 0.5).rounded()), 0), volume.ny - 1)

      if xGrid >= 0, xGrid <= maxSliceX,
         zGrid >= 0, zGrid <= maxSliceZ
      {
        let coord = GridCoord(x: xGrid, y: yGrid, z: zGrid)
        if let voxel = volume.voxels[coord] {
          return (voxel, p)
        }
      }
    }

    return nil
  }

  // MARK: - Bearing Layer 1m² Voxel Surface & Border Mesh Synthesis

  /// Synthesizes the flat 3D Bearing Layer surface mesh directly from the active 1m² voxels (`volume.bearingVoxels`)
  /// using the exact same `nx × nz` 1m² horizontal grid (`centerX`, `centerZ`) and boundary shape as the 3D Layer.
  @MainActor
  static func synthesizeBearingVoxelSurfaceMesh(volume: SubsurfaceVoxelVolume) -> MeshResource? {
    let nx = volume.nx
    let nz = volume.nz
    let centerX = volume.centerX
    let centerZ = volume.centerZ

    @inline(__always)
    func worldX(_ gridEdgeX: Int) -> Float {
      (Float(gridEdgeX) - 0.5) - centerX
    }

    @inline(__always)
    func worldZ(_ gridEdgeZ: Int) -> Float {
      (Float(gridEdgeZ) - 0.5) - centerZ
    }

    @inline(__always)
    func uvAt(gridEdgeX: Int, gridEdgeZ: Int) -> SIMD2<Float> {
      let u = Float(gridEdgeX) / Float(max(nx, 1))
      let v = Float(gridEdgeZ) / Float(max(nz, 1))
      return SIMD2<Float>(min(max(u, 0.0), 1.0), 1.0 - min(max(v, 0.0), 1.0))
    }

    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    let activeCount = max(volume.bearingVoxels.count, 1)
    positions.reserveCapacity(activeCount * 8)
    normals.reserveCapacity(activeCount * 8)
    uvs.reserveCapacity(activeCount * 8)
    indices.reserveCapacity(activeCount * 12)

    for ix in 0 ..< nx {
      for iz in 0 ..< nz {
        guard volume.bearingVoxels[ColumnCoord(x: ix, z: iz)] != nil else { continue }

        let x0 = worldX(ix)
        let x1 = worldX(ix + 1)
        let z0 = worldZ(iz)
        let z1 = worldZ(iz + 1)

        let uv00 = uvAt(gridEdgeX: ix, gridEdgeZ: iz)
        let uv01 = uvAt(gridEdgeX: ix, gridEdgeZ: iz + 1)
        let uv11 = uvAt(gridEdgeX: ix + 1, gridEdgeZ: iz + 1)
        let uv10 = uvAt(gridEdgeX: ix + 1, gridEdgeZ: iz)

        // Top 1m² voxel face (+Y normal, CCW winding)
        let baseTop = UInt32(positions.count)
        positions.append(SIMD3<Float>(x0, 0.0, z0))
        positions.append(SIMD3<Float>(x0, 0.0, z1))
        positions.append(SIMD3<Float>(x1, 0.0, z1))
        positions.append(SIMD3<Float>(x1, 0.0, z0))
        normals.append(contentsOf: [
          SIMD3<Float>(0, 1, 0),
          SIMD3<Float>(0, 1, 0),
          SIMD3<Float>(0, 1, 0),
          SIMD3<Float>(0, 1, 0)
        ])
        uvs.append(contentsOf: [uv00, uv01, uv11, uv10])
        indices.append(contentsOf: [
          baseTop, baseTop + 1, baseTop + 2,
          baseTop, baseTop + 2, baseTop + 3
        ])

        // Bottom 1m² voxel face (-Y normal) so surface is visible from any orbit angle
        let baseBot = UInt32(positions.count)
        positions.append(SIMD3<Float>(x0, -0.08, z0))
        positions.append(SIMD3<Float>(x1, -0.08, z0))
        positions.append(SIMD3<Float>(x1, -0.08, z1))
        positions.append(SIMD3<Float>(x0, -0.08, z1))
        normals.append(contentsOf: [
          SIMD3<Float>(0, -1, 0),
          SIMD3<Float>(0, -1, 0),
          SIMD3<Float>(0, -1, 0),
          SIMD3<Float>(0, -1, 0)
        ])
        uvs.append(contentsOf: [uv00, uv10, uv11, uv01])
        indices.append(contentsOf: [
          baseBot, baseBot + 1, baseBot + 2,
          baseBot, baseBot + 2, baseBot + 3
        ])
      }
    }

    guard !positions.isEmpty else { return nil }

    var descriptor = MeshDescriptor(name: "Bearing1mVoxelSurfaceManifold")
    descriptor.positions = MeshBuffers.Positions(positions)
    descriptor.normals = MeshBuffers.Normals(normals)
    descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
    descriptor.primitives = .triangles(indices)

    return try? MeshResource.generate(from: [descriptor])
  }

  /// Synthesizes a single batched dark border mesh framing the perimeter of the active 1m² bearing voxels.
  @MainActor
  static func synthesizeBearingVoxelBorderMesh(volume: SubsurfaceVoxelVolume) -> MeshResource? {
    let nx = volume.nx
    let nz = volume.nz
    let centerX = volume.centerX
    let centerZ = volume.centerZ

    @inline(__always)
    func worldX(_ gridEdgeX: Int) -> Float {
      (Float(gridEdgeX) - 0.5) - centerX
    }

    @inline(__always)
    func worldZ(_ gridEdgeZ: Int) -> Float {
      (Float(gridEdgeZ) - 0.5) - centerZ
    }

    @inline(__always)
    func isActive(_ x: Int, _ z: Int) -> Bool {
      guard x >= 0, x < nx, z >= 0, z < nz else { return false }
      return volume.bearingVoxels[ColumnCoord(x: x, z: z)] != nil
    }

    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    let halfThick: Float = 0.09
    let yTop: Float = 0.04
    let yBot: Float = -0.10

    func emitBox(minX: Float, maxX: Float, minZ: Float, maxZ: Float) {
      // Top quad (+Y)
      let b0 = UInt32(positions.count)
      positions.append(contentsOf: [
        SIMD3<Float>(minX, yTop, minZ),
        SIMD3<Float>(minX, yTop, maxZ),
        SIMD3<Float>(maxX, yTop, maxZ),
        SIMD3<Float>(maxX, yTop, minZ)
      ])
      normals.append(contentsOf: Array(repeating: SIMD3<Float>(0, 1, 0), count: 4))
      indices.append(contentsOf: [b0, b0 + 1, b0 + 2, b0, b0 + 2, b0 + 3])

      // Front quad (+Z)
      let b1 = UInt32(positions.count)
      positions.append(contentsOf: [
        SIMD3<Float>(minX, yBot, maxZ),
        SIMD3<Float>(maxX, yBot, maxZ),
        SIMD3<Float>(maxX, yTop, maxZ),
        SIMD3<Float>(minX, yTop, maxZ)
      ])
      normals.append(contentsOf: Array(repeating: SIMD3<Float>(0, 0, 1), count: 4))
      indices.append(contentsOf: [b1, b1 + 1, b1 + 2, b1, b1 + 2, b1 + 3])

      // Back quad (-Z)
      let b2 = UInt32(positions.count)
      positions.append(contentsOf: [
        SIMD3<Float>(maxX, yBot, minZ),
        SIMD3<Float>(minX, yBot, minZ),
        SIMD3<Float>(minX, yTop, minZ),
        SIMD3<Float>(maxX, yTop, minZ)
      ])
      normals.append(contentsOf: Array(repeating: SIMD3<Float>(0, 0, -1), count: 4))
      indices.append(contentsOf: [b2, b2 + 1, b2 + 2, b2, b2 + 2, b2 + 3])

      // Right quad (+X)
      let b3 = UInt32(positions.count)
      positions.append(contentsOf: [
        SIMD3<Float>(maxX, yBot, maxZ),
        SIMD3<Float>(maxX, yBot, minZ),
        SIMD3<Float>(maxX, yTop, minZ),
        SIMD3<Float>(maxX, yTop, maxZ)
      ])
      normals.append(contentsOf: Array(repeating: SIMD3<Float>(1, 0, 0), count: 4))
      indices.append(contentsOf: [b3, b3 + 1, b3 + 2, b3, b3 + 2, b3 + 3])

      // Left quad (-X)
      let b4 = UInt32(positions.count)
      positions.append(contentsOf: [
        SIMD3<Float>(minX, yBot, minZ),
        SIMD3<Float>(minX, yBot, maxZ),
        SIMD3<Float>(minX, yTop, maxZ),
        SIMD3<Float>(minX, yTop, minZ)
      ])
      normals.append(contentsOf: Array(repeating: SIMD3<Float>(-1, 0, 0), count: 4))
      indices.append(contentsOf: [b4, b4 + 1, b4 + 2, b4, b4 + 2, b4 + 3])
    }

    for ix in 0 ..< nx {
      for iz in 0 ..< nz where isActive(ix, iz) {
        let x0 = worldX(ix)
        let x1 = worldX(ix + 1)
        let z0 = worldZ(iz)
        let z1 = worldZ(iz + 1)

        if !isActive(ix - 1, iz) {
          emitBox(minX: x0 - halfThick, maxX: x0 + halfThick, minZ: z0 - halfThick, maxZ: z1 + halfThick)
        }
        if !isActive(ix + 1, iz) {
          emitBox(minX: x1 - halfThick, maxX: x1 + halfThick, minZ: z0 - halfThick, maxZ: z1 + halfThick)
        }
        if !isActive(ix, iz - 1) {
          emitBox(minX: x0 - halfThick, maxX: x1 + halfThick, minZ: z0 - halfThick, maxZ: z0 + halfThick)
        }
        if !isActive(ix, iz + 1) {
          emitBox(minX: x0 - halfThick, maxX: x1 + halfThick, minZ: z1 - halfThick, maxZ: z1 + halfThick)
        }
      }
    }

    guard !positions.isEmpty else { return nil }

    var descriptor = MeshDescriptor(name: "Bearing1mVoxelBorderManifold")
    descriptor.positions = MeshBuffers.Positions(positions)
    descriptor.normals = MeshBuffers.Normals(normals)
    descriptor.primitives = .triangles(indices)

    return try? MeshResource.generate(from: [descriptor])
  }

  /// Evaluates normalized bearing-layer depth ratio in `[0, 1]` for a 1m² voxel at `(u, v)`.
  static func evaluateBearingDepthRatio(u: Float, v: Float, bias: Float = 0.0) -> Float {
    var val: Float = 0.48 + bias

    // Deep blue basins (+ values)
    val += 0.56 * gaussian2D(u: u, v: v, cx: 0.43, cy: 0.16, sx: 0.17, sy: 0.22)
    val += 0.58 * gaussian2D(u: u, v: v, cx: 0.47, cy: 0.88, sx: 0.16, sy: 0.24)
    val += 0.26 * gaussian2D(u: u, v: v, cx: 0.68, cy: 0.68, sx: 0.18, sy: 0.20)
    val += 0.20 * gaussian2D(u: u, v: v, cx: 0.25, cy: 0.85, sx: 0.14, sy: 0.18)

    // Shallow orange/yellow highs (- values)
    val -= 0.58 * gaussian2D(u: u, v: v, cx: 0.89, cy: 0.14, sx: 0.18, sy: 0.22)
    val -= 0.52 * gaussian2D(u: u, v: v, cx: 0.90, cy: 0.94, sx: 0.16, sy: 0.18)
    val -= 0.54 * gaussian2D(u: u, v: v, cx: 0.10, cy: 0.60, sx: 0.14, sy: 0.25)
    val -= 0.26 * gaussian2D(u: u, v: v, cx: 0.23, cy: 0.28, sx: 0.12, sy: 0.18)

    // Gentle wave modulation for natural geological contour curvature
    val += 0.04 * sin(u * 9.5 + v * 4.2) * cos(v * 6.0 - u * 3.5)

    return min(max(val, 0.0), 1.0)
  }

  private static func gaussian2D(
    u: Float,
    v: Float,
    cx: Float,
    cy: Float,
    sx: Float,
    sy: Float
  ) -> Float {
    let dx = (u - cx) / sx
    let dy = (v - cy) / sy
    return exp(-0.5 * (dx * dx + dy * dy))
  }

  // MARK: - Helpers

  /// Trilinearly interpolates `SchemaGAN` reconstructed $I_c$ (`[gx][gy][gz]`) at normalized coordinates:
  /// - `fx`: West (`0.0`) -> East (`1.0`)
  /// - `fy`: South (`0.0`) -> North (`1.0`)
  /// - `fzDepth`: Surface (`0.0`) -> Bottom depth (`1.0`)
  private static func sampleReconstructedIc(
    recon: [[[Double]]],
    grid: CPTGridConfig,
    fx: Double,
    fy: Double,
    fzDepth: Double
  ) -> Double {
    let maxX = max(grid.nx - 1, 0)
    let maxY = max(grid.ny - 1, 0)
    let maxZ = max(grid.nz - 1, 0)

    let x = min(max(fx, 0.0), 1.0) * Double(maxX)
    let y = min(max(fy, 0.0), 1.0) * Double(maxY)
    let z = min(max(fzDepth, 0.0), 1.0) * Double(maxZ)

    let x0 = min(max(Int(floor(x)), 0), maxX)
    let x1 = min(x0 + 1, maxX)
    let tx = x - Double(x0)

    let y0 = min(max(Int(floor(y)), 0), maxY)
    let y1 = min(y0 + 1, maxY)
    let ty = y - Double(y0)

    let z0 = min(max(Int(floor(z)), 0), maxZ)
    let z1 = min(z0 + 1, maxZ)
    let tz = z - Double(z0)

    let c000 = recon[x0][y0][z0]
    let c100 = recon[x1][y0][z0]
    let c010 = recon[x0][y1][z0]
    let c110 = recon[x1][y1][z0]
    let c001 = recon[x0][y0][z1]
    let c101 = recon[x1][y0][z1]
    let c011 = recon[x0][y1][z1]
    let c111 = recon[x1][y1][z1]

    let c00 = c000 * (1.0 - tx) + c100 * tx
    let c10 = c010 * (1.0 - tx) + c110 * tx
    let c01 = c001 * (1.0 - tx) + c101 * tx
    let c11 = c011 * (1.0 - tx) + c111 * tx

    let c0 = c00 * (1.0 - ty) + c10 * ty
    let c1 = c01 * (1.0 - ty) + c11 * ty

    return c0 * (1.0 - tz) + c1 * tz
  }

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
