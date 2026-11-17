import RealityKit
import simd
import SwiftUI
import UIKit

struct ResultBearingSurfaceRealityView: View {
  let volume: SubsurfaceVoxelVolume
  let bearingOutput: BearingRuleOutput?
  let bearingRevision: Int
  let measuredCPTCount: Int
  let selectedCell: (x: Int, y: Int)?
  @Binding var cameraYaw: Float
  @Binding var cameraPitch: Float
  @Binding var cameraZoom: Float
  @Binding var isBearingPopoverPresented: Bool
  @Binding var bearingPopoverLocation: CGPoint?
  var bearingPopoverTitle: String = "Bearing Layer - 02"
  var bearingPopoverDepthText: String = "4.72 m"
  var bearingPopoverNorthingText: String = "9,312,450 m"
  var bearingPopoverEastingText: String = "699,250 m"
  var isBearingCompared: Bool = false
  var comparedPoints: [ComparedBearingPointItem] = []
  var onAddToCompare: (() -> Void)? = nil
  var onTapBearingSurface: ((CGPoint, BearingLayerVoxel?, Int, Int) -> Void)? = nil
  var onSelectBearingVoxel: ((BearingLayerVoxel?) -> Void)? = nil

  @State private var panOffset = SIMD2<Float>(repeating: 0)
  @State private var panStart: SIMD2<Float>?
  @State private var pinchStartZoom: Float?
  @State private var pinchStartPan: SIMD2<Float>?
  @State private var lastBuiltVolumeID: UUID?
  @State private var lastBuiltBearingRevision: Int = -1

  // Cached textures so they are synthesized only once
  @MainActor private static var cachedBadgeTextures: [String: TextureResource] = [:]
  @MainActor private static var cachedComparisonBadgeTextures: [String: TextureResource] = [:]

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        RealityView { content in
          content.camera = .virtual

          let rootAnchor = Entity()
          rootAnchor.name = "BearingSurfaceRootAnchor"

          let pivotEntity = Entity()
          pivotEntity.name = "BearingSurfacePivot"
          pivotEntity.position = sceneOffsetWithPan()
          pivotEntity.orientation = makeOrbitOrientation(yaw: cameraYaw, pitch: cameraPitch)
          let scale = computeNormalizedScale(for: volume) * cameraZoom
          pivotEntity.scale = SIMD3<Float>(repeating: scale)
          rootAnchor.addChild(pivotEntity)

          populatePivotScene(pivotEntity: pivotEntity, volume: volume)

          content.add(rootAnchor)
        } update: { content in
          guard let rootAnchor = content.entities.first(where: { $0.name == "BearingSurfaceRootAnchor" }),
                let pivotEntity = rootAnchor.findEntity(named: "BearingSurfacePivot")
          else {
            return
          }

          pivotEntity.position = sceneOffsetWithPan()
          pivotEntity.orientation = makeOrbitOrientation(yaw: cameraYaw, pitch: cameraPitch)
          let scale = computeNormalizedScale(for: volume) * cameraZoom
          pivotEntity.scale = SIMD3<Float>(repeating: scale)

          if lastBuiltVolumeID != volume.id || lastBuiltBearingRevision != bearingRevision {
            populatePivotScene(pivotEntity: pivotEntity, volume: volume)
            Task { @MainActor in
              lastBuiltVolumeID = volume.id
              lastBuiltBearingRevision = bearingRevision
            }
          }

          updateComparisonMarkers(on: pivotEntity)
          updateInspectionMarker(on: pivotEntity)
        }
        .gesture(panDragGesture(viewport: proxy.size))
        .simultaneousGesture(inspectionMarkerDragGesture)
        .simultaneousGesture(zoomMagnifyGesture(viewport: proxy.size))
        .simultaneousGesture(targetedTapGesture)
        .simultaneousGesture(doubleTapZoomGesture(viewport: proxy.size))
        .onChange(of: volume.id) { _, _ in panOffset = .zero }

        // Native-looking Bearing Popover Overlay
        if isBearingPopoverPresented, let tapLoc = bearingPopoverLocation {
          let popoverWidth: CGFloat = 250
          let popoverHeight: CGFloat = 160
          let isAbove = tapLoc.y >= 200
          let arrowPos: BearingPopoverBubbleShape.ArrowPosition = isAbove ? .bottom : .top

          let originX = min(max(tapLoc.x - popoverWidth * 0.5, 16), proxy.size.width - popoverWidth - 16)
          let centerY = isAbove ? (tapLoc.y - popoverHeight * 0.5 - 2) : (tapLoc.y + popoverHeight * 0.5 + 2)
          let localArrowX = min(max(tapLoc.x - originX, 24), popoverWidth - 24)

          ResultBearingPointPopoverView(
            title: bearingPopoverTitle,
            depthText: bearingPopoverDepthText,
            northingText: bearingPopoverNorthingText,
            eastingText: bearingPopoverEastingText,
            isCompared: isBearingCompared,
            onAddToCompare: onAddToCompare
          )
          .padding(.bottom, isAbove ? 10 : 0)
          .padding(.top, isAbove ? 0 : 10)
          .frame(width: popoverWidth)
          .background {
            BearingPopoverBubbleShape(
              arrowPosition: arrowPos,
              arrowX: localArrowX,
              cornerRadius: 18,
              arrowWidth: 16,
              arrowHeight: 10
            )
            .fill(Color(.systemBackground).opacity(0.96))
            .overlay {
              BearingPopoverBubbleShape(
                arrowPosition: arrowPos,
                arrowX: localArrowX,
                cornerRadius: 18,
                arrowWidth: 16,
                arrowHeight: 10
              )
              .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 6)
            .allowsHitTesting(false)
          }
          .position(x: originX + popoverWidth * 0.5, y: centerY)
          .transition(.scale(scale: 0.95).combined(with: .opacity))
          .zIndex(100)
        }
      }
    }
  }

  // MARK: - Scene Population (1m² Voxel Grid Matching 3D Layer)

  @MainActor
  private func populatePivotScene(pivotEntity: Entity, volume: SubsurfaceVoxelVolume) {
    pivotEntity.children.removeAll()

    // Restore the original flat contour heatmap; only evaluated columns are drawn.
    if let bearingOutput, let surfaceEntity = makeBearingSurfaceEntity(for: volume, output: bearingOutput) {
      surfaceEntity.name = "BearingSurfacePlane"
      pivotEntity.addChild(surfaceEntity)
      let borderEntity = makeSurfaceBorderEntity(for: volume, output: bearingOutput)
      borderEntity.name = "BearingSurfaceBorder"
      pivotEntity.addChild(borderEntity)
    }

    // 3. CPT Markers on 1m² Voxel Surface (CPT-01, CPT-02, CPT-03...)
    let cptMarkersEntity = makeCPTMarkersContainer(for: volume)
    cptMarkersEntity.name = "BearingCPTMarkers"
    pivotEntity.addChild(cptMarkersEntity)

    // 4. Comparison Markers (B-1, B-2, B-3...)
    updateComparisonMarkers(on: pivotEntity)
    updateInspectionMarker(on: pivotEntity)

    // 5. Perimeter Ruler Axes: X (m) along front edge, Y (m) along right edge
    let axesEntity = makeRulerAxesEntity(for: volume)
    axesEntity.name = "BearingRulerAxes"
    pivotEntity.addChild(axesEntity)
  }

  // MARK: - Comparison Markers (B-1, B-2, B-3...)

  @MainActor
  private func updateComparisonMarkers(on pivotEntity: Entity) {
    if let existing = pivotEntity.findEntity(named: "BearingComparisonMarkers") {
      existing.removeFromParent()
    }

    guard !comparedPoints.isEmpty else { return }

    let container = Entity()
    container.name = "BearingComparisonMarkers"

    let dotMesh = MeshResource.generateCylinder(height: 0.10, radius: 0.35)
    let whiteDotMat = UnlitMaterial(color: .white)
    let badgePlaneMesh = MeshResource.generatePlane(width: 2.4, depth: 1.2, cornerRadius: 0.6)

    for item in comparedPoints {
      let group = Entity()
      group.name = "ComparisonMarker_\(item.label)"
      group.position = SIMD3<Float>(item.worldX, 0.03, item.worldZ)

      // Surface white dot
      let dot = ModelEntity(mesh: dotMesh, materials: [whiteDotMat])
      dot.position = SIMD3<Float>(0, 0.02, 0)
      group.addChild(dot)

      // White pill badge with dark text "B-1", "B-2", etc.
      var badgeMat = UnlitMaterial()
      if let badgeTex = Self.getOrCreateComparisonBadgeTexture(label: item.label) {
        badgeMat.color = .init(tint: .white, texture: .init(badgeTex))
      } else {
        badgeMat.color = .init(tint: .white)
      }
      let badgeEntity = ModelEntity(mesh: badgePlaneMesh, materials: [badgeMat])
      badgeEntity.position = SIMD3<Float>(0.0, 0.35, -1.0)
      badgeEntity.orientation = simd_quatf(angle: 0.22, axis: SIMD3<Float>(1, 0, 0))
      group.addChild(badgeEntity)

      container.addChild(group)
    }

    pivotEntity.addChild(container)
  }

  @MainActor
  private func updateInspectionMarker(on pivotEntity: Entity) {
    guard let output = bearingOutput, let selectedCell,
          (0..<output.grid.nx).contains(selectedCell.x),
          (0..<output.grid.ny).contains(selectedCell.y),
          output.topDepthMXY[output.grid.column(selectedCell.x, selectedCell.y)] != nil else {
      pivotEntity.findEntity(named: "BearingInspectionMarker")?.removeFromParent()
      return
    }
    let marker: Entity
    if let existing = pivotEntity.findEntity(named: "BearingInspectionMarker") {
      marker = existing
    } else {
      let entity = Entity()
      entity.name = "BearingInspectionMarker"
      let dot = ModelEntity(mesh: .generateSphere(radius: 0.47), materials: [UnlitMaterial(color: .white)])
      dot.name = "BearingInspectionMarkerDot"
      entity.addChild(dot)
      entity.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.8)]))
      entity.components.set(InputTargetComponent())
      pivotEntity.addChild(entity)
      marker = entity
    }
    marker.position = [
      BearingCandidateGeometry.localX(Double(selectedCell.x), output: output, volume: volume),
      0.55,
      BearingCandidateGeometry.localZ(Double(selectedCell.y), output: output, volume: volume)
    ]
  }

  @MainActor
  private static func getOrCreateComparisonBadgeTexture(label: String) -> TextureResource? {
    if let cached = cachedComparisonBadgeTextures[label] {
      return cached
    }

    let size = CGSize(width: 200, height: 100)
    let renderer = UIGraphicsImageRenderer(size: size)
    let img = renderer.image { _ in
      let rect = CGRect(origin: .zero, size: size)
      let pillPath = UIBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), cornerRadius: 46)
      UIColor.white.setFill()
      pillPath.fill()
      UIColor(white: 0.2, alpha: 0.4).setStroke()
      pillPath.lineWidth = 2.5
      pillPath.stroke()

      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      let attrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 42, weight: .bold),
        .foregroundColor: UIColor(white: 0.12, alpha: 1.0),
        .paragraphStyle: paragraph
      ]
      let textSize = (label as NSString).size(withAttributes: attrs)
      let textRect = CGRect(
        x: 0,
        y: (size.height - textSize.height) * 0.5,
        width: size.width,
        height: textSize.height
      )
      (label as NSString).draw(in: textRect, withAttributes: attrs)
    }

    guard let cgImg = img.cgImage,
          let tex = try? TextureResource(image: cgImg, options: .init(semantic: .color))
    else {
      return nil
    }
    cachedComparisonBadgeTextures[label] = tex
    return tex
  }

  // MARK: - Gestures

  private func panDragGesture(viewport: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 4)
      .targetedToAnyEntity()
      .onChanged { value in
        guard value.entity.name == "BearingSurfacePlane" else { return }
        if panStart == nil { panStart = panOffset }
        let base = panStart ?? panOffset
        let scale = Float(1.4 / max(min(viewport.width, viewport.height), 1))
        panOffset = base + SIMD2(Float(value.translation.width) * scale, -Float(value.translation.height) * scale)
      }
      .onEnded { _ in
        panStart = nil
      }
  }

  private func zoomMagnifyGesture(viewport: CGSize) -> some Gesture {
    MagnifyGesture()
      .onChanged { value in
        if pinchStartZoom == nil {
          pinchStartZoom = cameraZoom
          pinchStartPan = panOffset
        }
        let baseZoom = pinchStartZoom ?? cameraZoom
        let updated = baseZoom * Float(value.magnification)
        let nextZoom = min(max(updated, 0.65), 10.0)
        let ratio = nextZoom / max(baseZoom, 0.001)
        let scale = Float(1.4 / max(min(viewport.width, viewport.height), 1))
        let anchor = SIMD2<Float>(
          Float(value.startLocation.x - viewport.width * 0.5) * scale,
          -Float(value.startLocation.y - viewport.height * 0.5) * scale
        )
        let startingPan = pinchStartPan ?? panOffset
        panOffset = startingPan + (anchor - startingPan) * (1 - ratio)
        cameraZoom = nextZoom
      }
      .onEnded { _ in
        pinchStartZoom = nil
        pinchStartPan = nil
      }
  }

  private func doubleTapZoomGesture(viewport: CGSize) -> some Gesture {
    SpatialTapGesture(count: 2)
      .onEnded { value in
        let nextZoom = min(cameraZoom * 2, 10.0)
        let ratio = nextZoom / max(cameraZoom, 0.001)
        let scale = Float(1.4 / max(min(viewport.width, viewport.height), 1))
        let anchor = SIMD2<Float>(
          Float(value.location.x - viewport.width * 0.5) * scale,
          -Float(value.location.y - viewport.height * 0.5) * scale
        )
        panOffset += (anchor - panOffset) * (1 - ratio)
        cameraZoom = nextZoom
      }
  }

  private var inspectionMarkerDragGesture: some Gesture {
    DragGesture(minimumDistance: 0)
      .targetedToAnyEntity()
      .onChanged { value in
        guard value.entity.name == "BearingInspectionMarker" ||
                value.entity.name == "BearingInspectionMarkerDot",
              let output = bearingOutput,
              let pivot = findPivotEntity(from: value.entity) else { return }
        guard let surface = pivot.findEntity(named: "BearingSurfacePlane"),
              let hit = value.hitTest(point: value.location, in: .local).first(where: { $0.entity === surface }) else { return }
        let localPoint = pivot.convert(position: hit.position, from: nil)
        guard let cell = nearestCandidateCell(localX: localPoint.x, localZ: localPoint.z, output: output) else { return }
        bearingPopoverLocation = value.location
        if selectedCell?.x != cell.x || selectedCell?.y != cell.y {
          onTapBearingSurface?(value.location, nil, cell.x, cell.y)
        }
      }
      .onEnded { _ in }
  }

  private func nearestCandidateCell(localX: Float, localZ: Float, output: BearingRuleOutput) -> (x: Int, y: Int)? {
    var best: (x: Int, y: Int)?
    var bestDistance = Float.greatestFiniteMagnitude
    for x in 0..<output.grid.nx {
      for y in 0..<output.grid.ny where output.topDepthMXY[output.grid.column(x, y)] != nil {
        let dx = localX - BearingCandidateGeometry.localX(Double(x), output: output, volume: volume)
        let dz = localZ - BearingCandidateGeometry.localZ(Double(y), output: output, volume: volume)
        let distance = dx * dx + dz * dz
        if distance < bestDistance { best = (x, y); bestDistance = distance }
      }
    }
    return best
  }

  private var targetedTapGesture: some Gesture {
    SpatialTapGesture()
      .targetedToAnyEntity()
      .onEnded { value in
        guard let output = bearingOutput else { return }
        let name = value.entity.name
        if name.hasPrefix("BearingCPT_"),
           let idxStr = name.split(separator: "_").last,
           let idx = Int(idxStr)
        {
          if idx < measuredCPTCount, idx < volume.cptSurfacePositions.count {
            let pos = volume.cptSurfacePositions[idx]
            if let cell = BearingCandidateGeometry.gridXY(localX: pos.x, localZ: pos.z, output: output, volume: volume),
               output.intervalCountXY[output.grid.column(cell.x, cell.y)] > 0 {
              onSelectBearingVoxel?(nil)
              onTapBearingSurface?(value.location, nil, cell.x, cell.y)
            }
          }
        } else {
          guard name == "BearingSurfacePlane" else { return }
          let hits = value.hitTest(point: value.location, in: .local)
          if let firstHit = hits.first,
             let pivot = findPivotEntity(from: value.entity)
          {
            let localPt = pivot.convert(position: firstHit.position, from: nil)
            if let cell = BearingCandidateGeometry.gridXY(localX: localPt.x, localZ: localPt.z, output: output, volume: volume),
               output.intervalCountXY[output.grid.column(cell.x, cell.y)] > 0 {
              onSelectBearingVoxel?(nil)
              onTapBearingSurface?(value.location, nil, cell.x, cell.y)
            }
          }
        }
      }
  }

  private func findPivotEntity(from entity: Entity) -> Entity? {
    var current: Entity? = entity
    while let c = current {
      if c.name == "BearingSurfacePivot" { return c }
      current = c.parent
    }
    return nil
  }

  // MARK: - Transform Helpers (Identical 1m² Grid Scale to 3D Layer)

  private func computeNormalizedScale(for volume: SubsurfaceVoxelVolume) -> Float {
    let maxSpan = max(Float(volume.nx), Float(volume.nz), 16.0)
    return 0.92 / maxSpan
  }

  private func computeSceneOffset() -> SIMD3<Float> {
    SIMD3<Float>(0.18, -0.02, -1.75)
  }

  private func sceneOffsetWithPan() -> SIMD3<Float> {
    computeSceneOffset() + SIMD3(panOffset.x, panOffset.y, 0)
  }

  private func makeOrbitOrientation(yaw: Float, pitch: Float) -> simd_quatf {
    let pitchQuat = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
    let yawQuat = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
    return simd_mul(pitchQuat, yawQuat)
  }

  // MARK: - 1. Flat 3D 1m² Voxel Surface Mesh with Contour Heatmap

  @MainActor
  private func makeBearingSurfaceEntity(for volume: SubsurfaceVoxelVolume, output: BearingRuleOutput) -> ModelEntity? {
    guard let mesh = makeFlatHeatmapMesh(for: volume, output: output) else { return nil }

    var material = UnlitMaterial()
    if let tex = Self.makeCandidateHeatmapTexture(output: output) {
      material.color = .init(tint: .white, texture: .init(tex))
    } else {
      material.color = .init(tint: UIColor(red: 0.14, green: 0.62, blue: 0.68, alpha: 1.0))
    }

    let entity = ModelEntity(mesh: mesh, materials: [material])
    entity.position = .zero
    let cellWidth = Float(output.grid.dxM) / volume.cellStepXM
    let cellLength = Float(output.grid.dyM) / volume.cellStepZM
    let collisionShapes = (0..<output.grid.nx).flatMap { x in
      (0..<output.grid.ny).compactMap { y -> ShapeResource? in
        guard output.topDepthMXY[output.grid.column(x, y)] != nil else { return nil }
        return ShapeResource.generateBox(size: [cellWidth, 0.25, cellLength])
          .offsetBy(translation: [
            BearingCandidateGeometry.localX(Double(x), output: output, volume: volume), 0,
            BearingCandidateGeometry.localZ(Double(y), output: output, volume: volume)
          ])
      }
    }
    entity.components.set(CollisionComponent(shapes: collisionShapes))
    entity.components.set(InputTargetComponent())
    return entity
  }

  // The original Git version used a single flat, textured RealityKit surface.
  // Build that same presentation from actual Bearing Rule columns, leaving empty cells absent.
  @MainActor
  private func makeFlatHeatmapMesh(for volume: SubsurfaceVoxelVolume, output: BearingRuleOutput) -> MeshResource? {
    let grid = output.grid
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []
    for x in 0..<grid.nx {
      for y in 0..<grid.ny where output.topDepthMXY[grid.column(x, y)] != nil {
        let x0 = BearingCandidateGeometry.localX(Double(x) - 0.5, output: output, volume: volume)
        let x1 = BearingCandidateGeometry.localX(Double(x) + 0.5, output: output, volume: volume)
        let z0 = BearingCandidateGeometry.localZ(Double(y) + 0.5, output: output, volume: volume)
        let z1 = BearingCandidateGeometry.localZ(Double(y) - 0.5, output: output, volume: volume)
        let base = UInt32(positions.count)
        positions.append(contentsOf: [SIMD3(x0,0,z0), SIMD3(x0,0,z1), SIMD3(x1,0,z1), SIMD3(x1,0,z0)])
        normals.append(contentsOf: Array(repeating: SIMD3<Float>(0,1,0), count: 4))
        // Match the corner UVs of the original flat heatmap mesh.
        let u0 = Float(x) / Float(grid.nx)
        let u1 = Float(x + 1) / Float(grid.nx)
        let v0 = Float(y) / Float(grid.ny)
        let v1 = Float(y + 1) / Float(grid.ny)
        uvs.append(contentsOf: [SIMD2(u0,v0), SIMD2(u0,v1), SIMD2(u1,v1), SIMD2(u1,v0)])
        indices.append(contentsOf: [base,base+1,base+2,base,base+2,base+3])
        // The historical surface was visible from both sides during orbit.
        let underside = UInt32(positions.count)
        positions.append(contentsOf: [SIMD3(x0,0,z0), SIMD3(x0,0,z1), SIMD3(x1,0,z1), SIMD3(x1,0,z0)])
        normals.append(contentsOf: Array(repeating: SIMD3<Float>(0,-1,0), count: 4))
        uvs.append(contentsOf: [SIMD2(u0,v0), SIMD2(u0,v1), SIMD2(u1,v1), SIMD2(u1,v0)])
        indices.append(contentsOf: [underside,underside+2,underside+1,underside,underside+3,underside+2])
      }
    }
    guard !positions.isEmpty else { return nil }
    var descriptor = MeshDescriptor(name: "BearingDepthHeatmap")
    descriptor.positions = MeshBuffers.Positions(positions)
    descriptor.normals = MeshBuffers.Normals(normals)
    descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
    descriptor.primitives = .triangles(indices)
    return try? MeshResource.generate(from: [descriptor])
  }

  @MainActor
  private func makeSurfaceBorderEntity(for volume: SubsurfaceVoxelVolume, output: BearingRuleOutput) -> Entity {
    let border = Entity()
    let material = UnlitMaterial(color: UIColor(white: 0.18, alpha: 1.0))
    let grid = output.grid
    let stepX = Float(grid.dxM) / volume.cellStepXM
    let stepZ = Float(grid.dyM) / volume.cellStepZM
    for x in 0..<grid.nx {
      for y in 0..<grid.ny where output.topDepthMXY[grid.column(x, y)] != nil {
        let centerX = BearingCandidateGeometry.localX(Double(x), output: output, volume: volume)
        let centerZ = BearingCandidateGeometry.localZ(Double(y), output: output, volume: volume)
        func active(_ ax: Int, _ ay: Int) -> Bool {
          (0..<grid.nx).contains(ax) && (0..<grid.ny).contains(ay) &&
            output.topDepthMXY[grid.column(ax, ay)] != nil
        }
        if !active(x, y - 1) || !active(x, y + 1) {
          for side in [-1, 1] where !active(x, y + side) {
            let line = ModelEntity(mesh: .generateBox(width: stepX, height: 0.10, depth: 0.09), materials: [material])
            line.position = [centerX, 0.04, centerZ - Float(side) * stepZ * 0.5]
            border.addChild(line)
          }
        }
        if !active(x - 1, y) || !active(x + 1, y) {
          for side in [-1, 1] where !active(x + side, y) {
            let line = ModelEntity(mesh: .generateBox(width: 0.09, height: 0.10, depth: stepZ), materials: [material])
            line.position = [centerX + Float(side) * stepX * 0.5, 0.04, centerZ]
            border.addChild(line)
          }
        }
      }
    }
    return border
  }

  // MARK: - 3. CPT Markers on 1m² Voxel Surface

  @MainActor
  private func makeCPTMarkersContainer(for volume: SubsurfaceVoxelVolume) -> Entity {
    let container = Entity()

    let outerDotMesh = MeshResource.generateCylinder(height: 0.08, radius: 0.42)
    let innerDotMesh = MeshResource.generateCylinder(height: 0.11, radius: 0.28)
    let darkRingMat = UnlitMaterial(color: UIColor(white: 0.15, alpha: 1.0))
    let whiteDotMat = UnlitMaterial(color: .white)

    let badgePlaneMesh = MeshResource.generatePlane(width: 4.0, depth: 1.4, cornerRadius: 0.7)

    for (idx, pos) in volume.cptSurfacePositions.prefix(measuredCPTCount).enumerated() {
      let label = String(format: "CPT-%02d", idx + 1)

      let group = Entity()
      group.name = "BearingCPT_\(idx)"
      group.position = SIMD3<Float>(pos.x, 0.03, pos.z)

      // Outer dark ring on surface
      let outerDot = ModelEntity(mesh: outerDotMesh, materials: [darkRingMat])
      outerDot.position = SIMD3<Float>(0, 0.01, 0)
      group.addChild(outerDot)

      // Inner white dot on surface
      let innerDot = ModelEntity(mesh: innerDotMesh, materials: [whiteDotMat])
      innerDot.position = SIMD3<Float>(0, 0.03, 0)
      group.addChild(innerDot)

      // Dark pill badge ("CPT-01", "CPT-02", "CPT-03") positioned slightly behind/above dot
      var badgeMat = UnlitMaterial()
      if let badgeTex = Self.getOrCreateBadgeTexture(title: label) {
        badgeMat.color = .init(tint: .white, texture: .init(badgeTex))
      } else {
        badgeMat.color = .init(tint: UIColor(white: 0.16, alpha: 1.0))
      }
      let badgeEntity = ModelEntity(mesh: badgePlaneMesh, materials: [badgeMat])
      badgeEntity.position = SIMD3<Float>(0.15, 0.35, -1.35)
      badgeEntity.orientation = simd_quatf(angle: 0.22, axis: SIMD3<Float>(1, 0, 0))
      group.addChild(badgeEntity)

      group.components.set(CollisionComponent(shapes: [
        .generateBox(size: [4.0, 1.2, 3.0])
      ]))
      group.components.set(InputTargetComponent())

      container.addChild(group)
    }

    return container
  }

  // MARK: - 4. Base Ruler Axes Along 1m² Voxel Grid Perimeter

  private func makeRulerAxesEntity(for volume: SubsurfaceVoxelVolume) -> Entity {
    let container = Entity()
    let axisColor = UIColor(white: 0.22, alpha: 1.0)
    let axisMaterial = UnlitMaterial(color: axisColor)

    let minX = -0.5 - volume.centerX
    let maxX = Float(volume.nx) - 0.5 - volume.centerX
    let minZ = -0.5 - volume.centerZ
    let maxZ = Float(volume.nz) - 0.5 - volume.centerZ

    let xLength = max(maxX - minX, 1.0)
    let zLength = max(maxZ - minZ, 1.0)
    let frontZ = maxZ + 1.0
    let rightX = maxX + 1.0

    // X Axis bar along front edge
    let xBar = ModelEntity(
      mesh: .generateBox(width: xLength, height: 0.10, depth: 0.12),
      materials: [axisMaterial]
    )
    xBar.position = SIMD3<Float>((minX + maxX) * 0.5, 0, frontZ)
    container.addChild(xBar)

    let xTickValues = Array(0...5)
    for val in xTickValues {
      let t = Float(val) / 5.0
      let tx = minX + t * xLength

      let tick = ModelEntity(
        mesh: .generateBox(width: 0.12, height: 0.10, depth: 0.6),
        materials: [axisMaterial]
      )
      tick.position = SIMD3<Float>(tx, 0, frontZ + 0.3)
      container.addChild(tick)

      let labelEntity = makeAxisTextEntity(text: String(format: "%.0f", t * volume.widthXM), size: 0.95, color: axisColor)
      labelEntity.orientation = simd_quatf(angle: -0.75, axis: SIMD3<Float>(1, 0, 0))
      labelEntity.position = SIMD3<Float>(tx - 0.38, -0.25, frontZ + 1.45)
      container.addChild(labelEntity)
    }

    let xTitleEntity = makeAxisTextEntity(text: "X (m)", size: 1.05, color: axisColor)
    xTitleEntity.orientation = simd_quatf(angle: -0.75, axis: SIMD3<Float>(1, 0, 0))
    xTitleEntity.position = SIMD3<Float>((minX + maxX) * 0.5 - 1.4, -0.55, frontZ + 3.1)
    container.addChild(xTitleEntity)

    // Y Axis bar along right edge (0 at front to 4 at back)
    let yBar = ModelEntity(
      mesh: .generateBox(width: 0.12, height: 0.10, depth: zLength),
      materials: [axisMaterial]
    )
    yBar.position = SIMD3<Float>(rightX, 0, (minZ + maxZ) * 0.5)
    container.addChild(yBar)

    let yTickValues = Array(0...4)
    for val in yTickValues {
      let t = Float(val) / 4.0
      let tz = maxZ - t * zLength

      let tick = ModelEntity(
        mesh: .generateBox(width: 0.6, height: 0.10, depth: 0.12),
        materials: [axisMaterial]
      )
      tick.position = SIMD3<Float>(rightX + 0.3, 0, tz)
      container.addChild(tick)

      let labelEntity = makeAxisTextEntity(text: String(format: "%.0f", t * volume.lengthZM), size: 0.95, color: axisColor)
      labelEntity.orientation = simd_quatf(angle: -0.75, axis: SIMD3<Float>(1, 0, 0))
      labelEntity.position = SIMD3<Float>(rightX + 0.95, -0.18, tz + 0.25)
      container.addChild(labelEntity)
    }

    let yTitleEntity = makeAxisTextEntity(text: "Y (m)", size: 1.05, color: axisColor)
    yTitleEntity.orientation = simd_quatf(angle: -0.75, axis: SIMD3<Float>(1, 0, 0))
    yTitleEntity.position = SIMD3<Float>(rightX + 2.45, -0.25, (minZ + maxZ) * 0.5 + 0.3)
    container.addChild(yTitleEntity)

    return container
  }

  private func makeAxisTextEntity(text: String, size: CGFloat, color: UIColor) -> ModelEntity {
    let mesh = MeshResource.generateText(
      text,
      extrusionDepth: 0.04,
      font: .systemFont(ofSize: size, weight: .semibold),
      containerFrame: .zero,
      alignment: .center,
      lineBreakMode: .byClipping
    )
    let mat = UnlitMaterial(color: color)
    return ModelEntity(mesh: mesh, materials: [mat])
  }

  // MARK: - Candidate depth heatmap & badge texture generation

  @MainActor
  private static func getOrCreateBadgeTexture(title: String) -> TextureResource? {
    if let cached = cachedBadgeTextures[title] {
      return cached
    }

    let size = CGSize(width: 240, height: 84)
    let renderer = UIGraphicsImageRenderer(size: size)
    let img = renderer.image { _ in
      let rect = CGRect(origin: .zero, size: size)
      let pillPath = UIBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 40)
      UIColor(white: 0.16, alpha: 1.0).setFill()
      pillPath.fill()

      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      let attrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 34, weight: .bold),
        .foregroundColor: UIColor.white,
        .paragraphStyle: paragraph
      ]
      let textSize = (title as NSString).size(withAttributes: attrs)
      let textRect = CGRect(
        x: 0,
        y: (size.height - textSize.height) * 0.5,
        width: size.width,
        height: textSize.height
      )
      (title as NSString).draw(in: textRect, withAttributes: attrs)
    }

    guard let cgImg = img.cgImage,
          let tex = try? TextureResource(image: cgImg, options: .init(semantic: .color))
    else {
      return nil
    }
    cachedBadgeTextures[title] = tex
    return tex
  }

  @MainActor
  private static func makeCandidateHeatmapTexture(output: BearingRuleOutput) -> TextureResource? {
    let width = output.grid.nx
    let height = output.grid.ny
    guard width > 0, height > 0,
          let shallow = output.summary.shallowestTopDepthM,
          let deep = output.summary.deepestBottomDepthM else { return nil }
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let column = output.grid.column(x, y)
        guard let top = output.topDepthMXY[column] else { continue }
        let ratio = Float((top - shallow) / max(deep - shallow, 1e-6))
        let bands: Float = 16
        let scaled = min(max(ratio, 0), 1) * bands
        let band = floor(scaled)
        let fraction = scaled - band
        let softenedEdge = fraction < 0.82 ? 0 : (fraction - 0.82) / 0.18
        let color = contourColormap(t: min((band + softenedEdge) / bands, 1))
        let offset = ((height - 1 - y) * width + x) * 4
        pixels[offset] = UInt8(min(max(Int(color.0 * 255), 0), 255))
        pixels[offset + 1] = UInt8(min(max(Int(color.1 * 255), 0), 255))
        pixels[offset + 2] = UInt8(min(max(Int(color.2 * 255), 0), 255))
        pixels[offset + 3] = 255
      }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
          ),
          let tex = try? TextureResource(image: cgImage, options: .init(semantic: .color))
    else {
      return nil
    }

    return tex
  }

  /// Maps `t` in `[0, 1]` from Shallowest (Red-Orange -> Yellow -> Green -> Cyan -> Deep Blue).
  private static func contourColormap(t: Float) -> (Float, Float, Float) {
    let stops: [(pos: Float, r: Float, g: Float, b: Float)] = [
      (0.00, 0.93, 0.33, 0.07), // Deep Orange-Red
      (0.16, 0.97, 0.58, 0.12), // Vibrant Orange
      (0.30, 0.92, 0.82, 0.20), // Warm Yellow
      (0.45, 0.50, 0.80, 0.36), // Lime Green
      (0.60, 0.18, 0.72, 0.58), // Teal Green
      (0.75, 0.11, 0.58, 0.72), // Cerulean Blue
      (0.88, 0.07, 0.40, 0.65), // Medium Navy Blue
      (1.00, 0.04, 0.24, 0.52)  // Deepest Navy Blue
    ]

    let clamped = min(max(t, 0.0), 1.0)
    for i in 0 ..< (stops.count - 1) {
      let s0 = stops[i]
      let s1 = stops[i + 1]
      if clamped >= s0.pos && clamped <= s1.pos {
        let localT = (clamped - s0.pos) / max(s1.pos - s0.pos, 1e-5)
        let r = s0.r + (s1.r - s0.r) * localT
        let g = s0.g + (s1.g - s0.g) * localT
        let b = s0.b + (s1.b - s0.b) * localT
        return (r, g, b)
      }
    }
    let last = stops[stops.count - 1]
    return (last.r, last.g, last.b)
  }
}
