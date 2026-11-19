import CoreLocation
import MapKit
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
  var isMapOverlayVisible: Bool = false
  var cameraController: SubsurfaceCameraController = SubsurfaceCameraController()
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

  @State private var lastBuiltVolumeID: UUID?
  @State private var lastBuiltBearingRevision: Int = -1
  @State private var lastAppliedMapOverlayVisible: Bool = false

  private struct CachedMapSnapshotEntry {
    let texture: TextureResource
    let minX: Float
    let maxX: Float
    let minZ: Float
    let maxZ: Float
  }

  // Cached textures so they are synthesized only once
  @MainActor private static var cachedBadgeTextures: [String: TextureResource] = [:]
  @MainActor private static var cachedComparisonBadgeTextures: [String: TextureResource] = [:]
  @MainActor private static var cachedMapSnapshots: [String: CachedMapSnapshotEntry] = [:]

  var body: some View {
    let _ = cameraController.revision
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        if isMapOverlayVisible {
          Color(red: 0.96, green: 0.95, blue: 0.92)
            .ignoresSafeArea()
        }

        RealityView { content in
          content.camera = .virtual

          let rootAnchor = Entity()
          rootAnchor.name = "BearingSurfaceRootAnchor"

          let cameraEntity = PerspectiveCamera()
          cameraEntity.name = "BearingPerspectiveCamera"
          cameraEntity.camera.fieldOfViewInDegrees = cameraController.fovDegrees
          cameraEntity.camera.near = cameraController.nearPlane
          cameraEntity.camera.far = cameraController.farPlane
          cameraEntity.transform = cameraController.cameraTransform
          rootAnchor.addChild(cameraEntity)

          let pivotEntity = Entity()
          pivotEntity.name = "BearingSurfacePivot"
          pivotEntity.position = .zero
          pivotEntity.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
          pivotEntity.scale = .one
          rootAnchor.addChild(pivotEntity)

          populatePivotScene(pivotEntity: pivotEntity, volume: volume)

          content.add(rootAnchor)
        } update: { content in
          guard let rootAnchor = content.entities.first(where: { $0.name == "BearingSurfaceRootAnchor" }),
                let pivotEntity = rootAnchor.findEntity(named: "BearingSurfacePivot")
          else {
            return
          }

          if let cameraEntity = rootAnchor.findEntity(named: "BearingPerspectiveCamera") as? PerspectiveCamera {
            cameraEntity.camera.fieldOfViewInDegrees = cameraController.fovDegrees
            cameraEntity.camera.near = cameraController.nearPlane
            cameraEntity.camera.far = cameraController.farPlane
            cameraEntity.transform = cameraController.cameraTransform
          }

          pivotEntity.position = .zero
          pivotEntity.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
          pivotEntity.scale = .one

          if lastBuiltVolumeID != volume.id || lastBuiltBearingRevision != bearingRevision {
            populatePivotScene(pivotEntity: pivotEntity, volume: volume)
            Task { @MainActor in
              lastBuiltVolumeID = volume.id
              lastBuiltBearingRevision = bearingRevision
              lastAppliedMapOverlayVisible = isMapOverlayVisible
            }
          } else if lastAppliedMapOverlayVisible != isMapOverlayVisible {
            updateMapOverlayAppearance(on: pivotEntity)
            Task { @MainActor in
              lastAppliedMapOverlayVisible = isMapOverlayVisible
            }
          }

          updateComparisonMarkers(on: pivotEntity)
          updateInspectionMarker(on: pivotEntity)
          updateAdaptiveMarkerScales(on: pivotEntity)
        }
        .overlay {
          SubsurfaceCameraGestureOverlay(
            controller: cameraController,
            onSingleTap: { screenPoint, viewportSize in
              handleSurfaceTap(at: screenPoint, in: viewportSize)
            },
            shouldInterceptOneFingerPan: { screenPoint, viewportSize in
              shouldInterceptMarkerDrag(at: screenPoint, in: viewportSize)
            },
            onInterceptedOneFingerPan: { screenPoint, viewportSize in
              handleInspectionMarkerDrag(at: screenPoint, in: viewportSize)
            }
          )
        }
        .onAppear {
          cameraController.updateViewportSize(proxy.size)
        }
        .onChange(of: proxy.size) { _, newSize in
          cameraController.updateViewportSize(newSize)
        }

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

    // 0. Full-Background 3D Map Plane inside the same 3D world (`BearingSurfacePivot`, Y = -0.10)
    // so it shares the exact PerspectiveCamera & 3D coordinates with zero drift during pan/zoom/rotate/tilt.
    let mapOverlayEntity = makeMapOverlayEntity(for: volume, output: bearingOutput)
    mapOverlayEntity.name = "BearingMapOverlayPlane"
    mapOverlayEntity.isEnabled = isMapOverlayVisible
    pivotEntity.addChild(mapOverlayEntity)

    // 1 & 2. Smooth Clipped Polygon Contour Heatmap Surface & Border
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
  }

  @MainActor
  private func updateMapOverlayAppearance(on pivotEntity: Entity) {
    if let mapPlane = pivotEntity.findEntity(named: "BearingMapOverlayPlane") {
      mapPlane.isEnabled = isMapOverlayVisible
    }
    if let surfaceEntity = pivotEntity.findEntity(named: "BearingSurfacePlane") as? ModelEntity,
       var model = surfaceEntity.model,
       var mat = model.materials.first as? UnlitMaterial
    {
      mat.faceCulling = .none
      mat.blending = isMapOverlayVisible
        ? .transparent(opacity: .init(floatLiteral: 0.72))
        : .opaque
      model.materials = [mat]
      surfaceEntity.model = model
    }
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

  // MARK: - Camera-Driven Surface Picking, Marker Drag & Adaptive Scaling

  @MainActor
  private func updateAdaptiveMarkerScales(on pivotEntity: Entity) {
    let refDist = max(cameraController.defaultDistance, 16.0)
    let adaptiveScale = min(1.15, max(cameraController.distance / refDist, 0.35))
    let scaleVec = SIMD3<Float>(repeating: adaptiveScale)

    if let cptContainer = pivotEntity.findEntity(named: "BearingCPTMarkers") {
      for child in cptContainer.children {
        child.scale = scaleVec
      }
    }
    if let cmpContainer = pivotEntity.findEntity(named: "BearingComparisonMarkers") {
      for child in cmpContainer.children {
        child.scale = scaleVec
      }
    }
    if let marker = pivotEntity.findEntity(named: "BearingInspectionMarker") {
      marker.scale = scaleVec
    }
  }

  private func shouldInterceptMarkerDrag(at screenPoint: CGPoint, in viewportSize: CGSize) -> Bool {
    guard let output = bearingOutput,
          let selectedCell,
          (0..<output.grid.nx).contains(selectedCell.x),
          (0..<output.grid.ny).contains(selectedCell.y),
          output.topDepthMXY[output.grid.column(selectedCell.x, selectedCell.y)] != nil
    else {
      return false
    }

    let markerPos = SIMD3<Float>(
      BearingCandidateGeometry.localX(Double(selectedCell.x), output: output, volume: volume),
      0.55,
      BearingCandidateGeometry.localZ(Double(selectedCell.y), output: output, volume: volume)
    )
    if let markerScreen = cameraController.projectToScreen(markerPos, viewportSize: viewportSize) {
      let dx = screenPoint.x - markerScreen.x
      let dy = screenPoint.y - markerScreen.y
      if (dx * dx + dy * dy) <= (32.0 * 32.0) {
        return true
      }
    }
    return false
  }

  private func handleInspectionMarkerDrag(at screenPoint: CGPoint, in viewportSize: CGSize) {
    guard let output = bearingOutput,
          let groundHit = cameraController.intersectGroundPlane(
            screenPoint: screenPoint,
            viewportSize: viewportSize
          ),
          let cell = nearestCandidateCell(localX: groundHit.x, localZ: groundHit.z, output: output)
    else {
      return
    }
    bearingPopoverLocation = screenPoint
    if selectedCell?.x != cell.x || selectedCell?.y != cell.y {
      onTapBearingSurface?(screenPoint, nil, cell.x, cell.y)
    }
  }

  private func handleSurfaceTap(at screenPoint: CGPoint, in viewportSize: CGSize) {
    guard viewportSize.width > 1, viewportSize.height > 1 else { return }
    guard let output = bearingOutput else {
      if isBearingPopoverPresented {
        withAnimation(.easeInOut(duration: 0.2)) {
          isBearingPopoverPresented = false
        }
      }
      return
    }

    guard let groundHit = cameraController.intersectGroundPlane(
      screenPoint: screenPoint,
      viewportSize: viewportSize
    ) else {
      return
    }

    let refDist = max(cameraController.defaultDistance, 16.0)
    let adaptiveScale = min(1.15, max(cameraController.distance / refDist, 0.35))

    // 1. Check if tap landed on a measured CPT marker on the surface
    let cptHitRadiusSq = pow(1.6 * adaptiveScale, 2)
    for (idx, pos) in cptLocalPositions(for: volume, output: output).prefix(measuredCPTCount).enumerated() {
      let dx = groundHit.x - pos.x
      let dz = groundHit.z - pos.z
      if (dx * dx + dz * dz) <= cptHitRadiusSq,
         let cell = BearingCandidateGeometry.gridXY(localX: pos.x, localZ: pos.z, output: output, volume: volume),
         output.intervalCountXY[output.grid.column(cell.x, cell.y)] > 0
      {
        let _ = idx
        onSelectBearingVoxel?(nil)
        onTapBearingSurface?(screenPoint, nil, cell.x, cell.y)
        return
      }
    }

    // 2. Check if tap landed inside the smooth site boundary polygon
    let xMin = BearingCandidateGeometry.localX(0, output: output, volume: volume)
    let xMax = BearingCandidateGeometry.localX(Double(max(output.grid.nx - 1, 1)), output: output, volume: volume)
    let zMin = BearingCandidateGeometry.localZ(Double(max(output.grid.ny - 1, 1)), output: output, volume: volume)
    let zMax = BearingCandidateGeometry.localZ(0, output: output, volume: volume)

    var rawPolygon: [SIMD2<Float>] = []
    if volume.boundaryPolygonUV.count >= 3 {
      rawPolygon = volume.boundaryPolygonUV.map { uv in
        SIMD2<Float>(
          xMin + uv.x * (xMax - xMin),
          zMin + uv.y * (zMax - zMin)
        )
      }
    } else {
      rawPolygon = [
        SIMD2<Float>(xMin, zMin),
        SIMD2<Float>(xMax, zMin),
        SIMD2<Float>(xMax, zMax),
        SIMD2<Float>(xMin, zMax)
      ]
    }
    rawPolygon = Self.cleanPolygonVertices(rawPolygon)

    let hit2D = SIMD2<Float>(groundHit.x, groundHit.z)
    let isInsideBoundary = rawPolygon.count >= 3 ? Self.isPointInPolygon2D(hit2D, polygon: rawPolygon) : true

    if isInsideBoundary {
      if let cell = BearingCandidateGeometry.gridXY(localX: groundHit.x, localZ: groundHit.z, output: output, volume: volume),
         output.intervalCountXY[output.grid.column(cell.x, cell.y)] > 0
      {
        onSelectBearingVoxel?(nil)
        onTapBearingSurface?(screenPoint, nil, cell.x, cell.y)
        return
      } else if let nearest = nearestCandidateCell(localX: groundHit.x, localZ: groundHit.z, output: output) {
        let stepX = Float(output.grid.dxM) / max(volume.cellStepXM, 1e-4)
        let stepZ = Float(output.grid.dyM) / max(volume.cellStepZM, 1e-4)
        let maxSnapDistSq = pow(max(stepX, stepZ) * 1.65, 2)
        let dx = groundHit.x - BearingCandidateGeometry.localX(Double(nearest.x), output: output, volume: volume)
        let dz = groundHit.z - BearingCandidateGeometry.localZ(Double(nearest.y), output: output, volume: volume)
        if (dx * dx + dz * dz) <= maxSnapDistSq {
          onSelectBearingVoxel?(nil)
          onTapBearingSurface?(screenPoint, nil, nearest.x, nearest.y)
          return
        }
      }
    }

    if isBearingPopoverPresented {
      withAnimation(.easeInOut(duration: 0.2)) {
        isBearingPopoverPresented = false
      }
    }
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

  private func cptLocalPositions(
    for volume: SubsurfaceVoxelVolume,
    output: BearingRuleOutput?
  ) -> [SIMD3<Float>] {
    let xMin: Float
    let xMax: Float
    let zMin: Float
    let zMax: Float
    if let output, output.grid.nx > 0, output.grid.ny > 0 {
      xMin = BearingCandidateGeometry.localX(0, output: output, volume: volume)
      xMax = BearingCandidateGeometry.localX(Double(max(output.grid.nx - 1, 1)), output: output, volume: volume)
      zMin = BearingCandidateGeometry.localZ(Double(max(output.grid.ny - 1, 1)), output: output, volume: volume)
      zMax = BearingCandidateGeometry.localZ(0, output: output, volume: volume)
    } else {
      let step = Float(BearingCandidateGeometry.uniformStepM(volume: volume))
      xMin = -0.5 * volume.widthXM / step
      xMax = 0.5 * volume.widthXM / step
      zMin = -0.5 * volume.lengthZM / step
      zMax = 0.5 * volume.lengthZM / step
    }

    if !volume.cptNormalizedUVs.isEmpty {
      return volume.cptNormalizedUVs.map { uv in
        SIMD3<Float>(
          xMin + uv.x * (xMax - xMin),
          0.0,
          zMin + uv.y * (zMax - zMin)
        )
      }
    }
    return volume.cptSurfacePositions
  }

  // MARK: - 0. Full-Background 3D Map Plane Beneath Heatmap Surface

  @MainActor
  private func makeMapOverlayEntity(for volume: SubsurfaceVoxelVolume, output: BearingRuleOutput?) -> ModelEntity {
    let xMin: Float
    let xMax: Float
    let zMin: Float
    let zMax: Float
    if let output, output.grid.nx > 0, output.grid.ny > 0 {
      xMin = BearingCandidateGeometry.localX(0, output: output, volume: volume)
      xMax = BearingCandidateGeometry.localX(Double(max(output.grid.nx - 1, 1)), output: output, volume: volume)
      zMin = BearingCandidateGeometry.localZ(Double(max(output.grid.ny - 1, 1)), output: output, volume: volume)
      zMax = BearingCandidateGeometry.localZ(0, output: output, volume: volume)
    } else {
      let step = Float(BearingCandidateGeometry.uniformStepM(volume: volume))
      xMin = -0.5 * volume.widthXM / step
      xMax = 0.5 * volume.widthXM / step
      zMin = -0.5 * volume.lengthZM / step
      zMax = 0.5 * volume.lengthZM / step
    }

    // Expand the 3D map ground plane far beyond the site bounds (`paddingFactor = 2.4` around maxSpan)
    // so the map fills 100% of the screen background at all allowed pan/zoom/tilt angles without clipped edges.
    let paddingFactor: Float = 2.4
    let spanX = max(xMax - xMin, 4.0)
    let spanZ = max(zMax - zMin, 4.0)
    let maxSpan = max(spanX, spanZ)
    let pad = maxSpan * paddingFactor
    let defaultMapMinX = xMin - pad
    let defaultMapMaxX = xMax + pad
    let defaultMapMinZ = zMin - pad
    let defaultMapMaxZ = zMax + pad

    let cacheKey = String(
      format: "fullmap_%.6f_%.6f_%.6f_%.6f_%.2f_%.2f",
      volume.minLatitude, volume.maxLatitude,
      volume.minLongitude, volume.maxLongitude,
      spanX, spanZ
    )

    let entity = ModelEntity()
    entity.position = .zero

    if let cached = Self.cachedMapSnapshots[cacheKey],
       let mesh = Self.makeMapQuadMesh(minX: cached.minX, maxX: cached.maxX, minZ: cached.minZ, maxZ: cached.maxZ)
    {
      var mat = UnlitMaterial()
      mat.color = .init(tint: .white, texture: .init(cached.texture))
      mat.faceCulling = .none
      entity.model = ModelComponent(mesh: mesh, materials: [mat])
      return entity
    }

    if let fallbackMesh = Self.makeMapQuadMesh(
      minX: defaultMapMinX,
      maxX: defaultMapMaxX,
      minZ: defaultMapMinZ,
      maxZ: defaultMapMaxZ
    ) {
      var mat = UnlitMaterial()
      if let fallbackTex = Self.makeFallbackMapTexture(
        volume: volume,
        xMin: xMin,
        xMax: xMax,
        zMin: zMin,
        zMax: zMax,
        mapMinX: defaultMapMinX,
        mapMaxX: defaultMapMaxX,
        mapMinZ: defaultMapMinZ,
        mapMaxZ: defaultMapMaxZ
      ) {
        mat.color = .init(tint: .white, texture: .init(fallbackTex))
      } else {
        mat.color = .init(tint: UIColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1.0))
      }
      mat.faceCulling = .none
      entity.model = ModelComponent(mesh: fallbackMesh, materials: [mat])
    }

    Self.requestRealMapSnapshot(
      volume: volume,
      xMin: xMin,
      xMax: xMax,
      zMin: zMin,
      zMax: zMax,
      paddingFactor: paddingFactor,
      cacheKey: cacheKey
    ) { [weak entity] entry in
      guard let entity,
            let calibratedMesh = Self.makeMapQuadMesh(
              minX: entry.minX,
              maxX: entry.maxX,
              minZ: entry.minZ,
              maxZ: entry.maxZ
            )
      else {
        return
      }
      var mat = UnlitMaterial()
      mat.color = .init(tint: .white, texture: .init(entry.texture))
      mat.faceCulling = .none
      entity.model = ModelComponent(mesh: calibratedMesh, materials: [mat])
    }

    return entity
  }

  @MainActor
  private static func makeMapQuadMesh(
    minX: Float,
    maxX: Float,
    minZ: Float,
    maxZ: Float,
    yLevel: Float = -0.10
  ) -> MeshResource? {
    let positions: [SIMD3<Float>] = [
      SIMD3<Float>(minX, yLevel, minZ),
      SIMD3<Float>(minX, yLevel, maxZ),
      SIMD3<Float>(maxX, yLevel, maxZ),
      SIMD3<Float>(maxX, yLevel, minZ)
    ]
    let normals = Array(repeating: SIMD3<Float>(0, 1, 0), count: 4)
    let uvs: [SIMD2<Float>] = [
      SIMD2<Float>(0.0, 1.0),
      SIMD2<Float>(0.0, 0.0),
      SIMD2<Float>(1.0, 0.0),
      SIMD2<Float>(1.0, 1.0)
    ]
    let indices: [UInt32] = [0, 1, 2, 0, 2, 3]

    var descriptor = MeshDescriptor(name: "BearingMapOverlayQuad")
    descriptor.positions = MeshBuffers.Positions(positions)
    descriptor.normals = MeshBuffers.Normals(normals)
    descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
    descriptor.primitives = .triangles(indices)
    return try? MeshResource.generate(from: [descriptor])
  }

  @MainActor
  private static func makeFallbackMapTexture(
    volume: SubsurfaceVoxelVolume,
    xMin: Float,
    xMax: Float,
    zMin: Float,
    zMax: Float,
    mapMinX: Float,
    mapMaxX: Float,
    mapMinZ: Float,
    mapMaxZ: Float
  ) -> TextureResource? {
    let size = CGSize(width: 960, height: 960)
    let renderer = UIGraphicsImageRenderer(size: size)
    let totalW = max(mapMaxX - mapMinX, 1e-4)
    let totalZ = max(mapMaxZ - mapMinZ, 1e-4)

    let img = renderer.image { ctx in
      let cg = ctx.cgContext
      let rect = CGRect(origin: .zero, size: size)

      UIColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1.0).setFill()
      cg.fill(rect)

      let gridCount = 24
      for i in 0 ... gridCount {
        let pos = CGFloat(i) / CGFloat(gridCount) * size.width
        let isMajor = (i % 4 == 0)
        cg.setStrokeColor(
          isMajor
            ? UIColor(red: 0.87, green: 0.85, blue: 0.80, alpha: 0.85).cgColor
            : UIColor(red: 0.91, green: 0.89, blue: 0.85, alpha: 0.65).cgColor
        )
        cg.setLineWidth(isMajor ? 2.0 : 1.0)
        cg.move(to: CGPoint(x: pos, y: 0))
        cg.addLine(to: CGPoint(x: pos, y: size.height))
        cg.move(to: CGPoint(x: 0, y: pos))
        cg.addLine(to: CGPoint(x: size.width, y: pos))
        cg.strokePath()
      }

      if volume.boundaryPolygonUV.count >= 3 {
        let path = UIBezierPath()
        for (idx, uv) in volume.boundaryPolygonUV.enumerated() {
          let wx = xMin + uv.x * (xMax - xMin)
          let wz = zMin + uv.y * (zMax - zMin)
          let px = CGFloat((wx - mapMinX) / totalW) * size.width
          let py = CGFloat((wz - mapMinZ) / totalZ) * size.height
          if idx == 0 {
            path.move(to: CGPoint(x: px, y: py))
          } else {
            path.addLine(to: CGPoint(x: px, y: py))
          }
        }
        path.close()
        UIColor.systemBlue.withAlphaComponent(0.08).setFill()
        path.fill()
        UIColor.systemBlue.withAlphaComponent(0.65).setStroke()
        path.lineWidth = 2.5
        let dash: [CGFloat] = [8, 5]
        path.setLineDash(dash, count: dash.count, phase: 0)
        path.stroke()
      }
    }

    guard let cgImage = img.cgImage else { return nil }
    return try? TextureResource(image: cgImage, options: .init(semantic: .color))
  }

  @MainActor
  private static func requestRealMapSnapshot(
    volume: SubsurfaceVoxelVolume,
    xMin: Float,
    xMax: Float,
    zMin: Float,
    zMax: Float,
    paddingFactor: Float,
    cacheKey: String,
    completion: @escaping @MainActor (CachedMapSnapshotEntry) -> Void
  ) {
    let centerLat = (volume.minLatitude + volume.maxLatitude) * 0.5
    let centerLon = (volume.minLongitude + volume.maxLongitude) * 0.5
    let latSpan = max(volume.maxLatitude - volume.minLatitude, 0.0004)
    let lonSpan = max(volume.maxLongitude - volume.minLongitude, 0.0004)
    let maxDegSpan = max(latSpan, lonSpan)
    let regionSpan = maxDegSpan * Double(1.0 + 2.0 * paddingFactor)

    let options = MKMapSnapshotter.Options()
    options.region = MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
      span: MKCoordinateSpan(
        latitudeDelta: regionSpan,
        longitudeDelta: regionSpan
      )
    )
    options.mapType = .standard
    options.showsBuildings = true
    options.size = CGSize(width: 1440, height: 1440)
    options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

    let snapshotter = MKMapSnapshotter(options: options)
    snapshotter.start { snapshot, _ in
      guard let snapshot else { return }

      let imgSize = snapshot.image.size
      let nwCoord = CLLocationCoordinate2D(latitude: volume.maxLatitude, longitude: volume.minLongitude)
      let seCoord = CLLocationCoordinate2D(latitude: volume.minLatitude, longitude: volume.maxLongitude)
      let pNW = snapshot.point(for: nwCoord)
      let pSE = snapshot.point(for: seCoord)

      let uNW = Float(pNW.x / max(imgSize.width, 1.0))
      let uSE = Float(pSE.x / max(imgSize.width, 1.0))
      let vNW = Float(pNW.y / max(imgSize.height, 1.0))
      let vSE = Float(pSE.y / max(imgSize.height, 1.0))

      let du = max(uSE - uNW, 1e-4)
      let dv = max(vSE - vNW, 1e-4)
      let siteSpanX = xMax - xMin
      let siteSpanZ = zMax - zMin

      // Calibrate exact 3D quad bounds so (xMin, zMin) lands on pixel pNW and (xMax, zMax) lands on pixel pSE
      let calMinX = xMin - (uNW / du) * siteSpanX
      let calMaxX = xMin + ((1.0 - uNW) / du) * siteSpanX
      let calMinZ = zMin - (vNW / dv) * siteSpanZ
      let calMaxZ = zMin + ((1.0 - vNW) / dv) * siteSpanZ

      let boundaryUVs = volume.boundaryPolygonUV
      let compositedImage = UIGraphicsImageRenderer(size: imgSize).image { _ in
        snapshot.image.draw(at: .zero)

        if boundaryUVs.count >= 3 {
          let polyPath = UIBezierPath()
          for (idx, uv) in boundaryUVs.enumerated() {
            let lon = volume.minLongitude + Double(uv.x) * (volume.maxLongitude - volume.minLongitude)
            let lat = volume.maxLatitude - Double(uv.y) * (volume.maxLatitude - volume.minLatitude)
            let pt = snapshot.point(for: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            if idx == 0 {
              polyPath.move(to: pt)
            } else {
              polyPath.addLine(to: pt)
            }
          }
          polyPath.close()
          UIColor.systemBlue.withAlphaComponent(0.65).setStroke()
          polyPath.lineWidth = 2.5
          let dash: [CGFloat] = [8, 5]
          polyPath.setLineDash(dash, count: dash.count, phase: 0)
          polyPath.stroke()
        }
      }

      guard let cgImg = compositedImage.cgImage else { return }
      Task { @MainActor in
        guard let tex = try? TextureResource(image: cgImg, options: .init(semantic: .color)) else {
          return
        }
        let entry = CachedMapSnapshotEntry(
          texture: tex,
          minX: calMinX,
          maxX: calMaxX,
          minZ: calMinZ,
          maxZ: calMaxZ
        )
        Self.cachedMapSnapshots[cacheKey] = entry
        completion(entry)
      }
    }
  }

  // MARK: - 1. Smooth Clipped Polygon 3D Surface Mesh & Border with Contour Heatmap

  private struct SmoothBearingGeometry {
    let surfaceMesh: MeshResource
    let borderMesh: MeshResource?
  }

  @MainActor
  private func makeBearingSurfaceEntity(for volume: SubsurfaceVoxelVolume, output: BearingRuleOutput) -> ModelEntity? {
    guard let mesh = makeFlatHeatmapMesh(for: volume, output: output) else { return nil }

    var material = UnlitMaterial()
    if let tex = Self.makeCandidateHeatmapTexture(output: output) {
      material.color = .init(tint: .white, texture: .init(tex))
    } else {
      material.color = .init(tint: UIColor(red: 0.14, green: 0.62, blue: 0.68, alpha: 1.0))
    }
    material.faceCulling = .none
    material.blending = isMapOverlayVisible
      ? .transparent(opacity: .init(floatLiteral: 0.72))
      : .opaque

    let entity = ModelEntity(mesh: mesh, materials: [material])
    entity.position = .zero
    let cellWidth = Float(output.grid.dxM) / volume.cellStepXM
    let cellLength = Float(output.grid.dyM) / volume.cellStepZM
    let collisionShapes = (0..<output.grid.nx).flatMap { x in
      (0..<output.grid.ny).compactMap { y -> ShapeResource? in
        guard output.topDepthMXY[output.grid.column(x, y)] != nil else { return nil }
        return ShapeResource.generateBox(size: [cellWidth * 1.15, 0.25, cellLength * 1.15])
          .offsetBy(translation: [
            BearingCandidateGeometry.localX(Double(x), output: output, volume: volume), 0,
            BearingCandidateGeometry.localZ(Double(y), output: output, volume: volume)
          ])
      }
    }
    entity.components.set(CollisionComponent(shapes: collisionShapes))
    entity.components.set(InputTargetComponent())
    Task { @MainActor in
      if let staticMeshShape = try? await ShapeResource.generateStaticMesh(from: mesh) {
        entity.components.set(CollisionComponent(shapes: [staticMeshShape]))
      }
    }
    return entity
  }

  @MainActor
  private func makeFlatHeatmapMesh(for volume: SubsurfaceVoxelVolume, output: BearingRuleOutput) -> MeshResource? {
    synthesizeSmoothBearingGeometry(for: volume, output: output)?.surfaceMesh
  }

  @MainActor
  private func makeSurfaceBorderEntity(for volume: SubsurfaceVoxelVolume, output: BearingRuleOutput) -> Entity {
    let material = UnlitMaterial(color: UIColor(white: 0.18, alpha: 1.0))
    if let borderMesh = synthesizeSmoothBearingGeometry(for: volume, output: output)?.borderMesh {
      return ModelEntity(mesh: borderMesh, materials: [material])
    }
    return Entity()
  }

  /// Synthesizes the Bearing Layer 3D surface and perimeter border with smooth polygon edges
  /// matching the 3D Layer (`volume.boundaryPolygonUV`), while smoothly contouring any internal
  /// boundary when criteria sliders filter out a subset of columns.
  @MainActor
  private func synthesizeSmoothBearingGeometry(
    for volume: SubsurfaceVoxelVolume,
    output: BearingRuleOutput
  ) -> SmoothBearingGeometry? {
    let grid = output.grid
    guard grid.nx > 0, grid.ny > 0, output.summary.candidateColumns > 0 else { return nil }

    let xMin = BearingCandidateGeometry.localX(0, output: output, volume: volume)
    let xMax = BearingCandidateGeometry.localX(Double(max(grid.nx - 1, 1)), output: output, volume: volume)
    let zMin = BearingCandidateGeometry.localZ(Double(max(grid.ny - 1, 1)), output: output, volume: volume)
    let zMax = BearingCandidateGeometry.localZ(0, output: output, volume: volume)

    let stepX = max(Float(grid.dxM) / max(volume.cellStepXM, 1e-4), 0.25)
    let stepZ = max(Float(grid.dyM) / max(volume.cellStepZM, 1e-4), 0.25)

    // 1. Build clean CCW 2D site boundary polygon matching the 3D Layer (`volume.boundaryPolygonUV`)
    var rawPolygon: [SIMD2<Float>] = []
    if volume.boundaryPolygonUV.count >= 3 {
      rawPolygon = volume.boundaryPolygonUV.map { uv in
        SIMD2<Float>(
          xMin + uv.x * (xMax - xMin),
          zMin + uv.y * (zMax - zMin)
        )
      }
    } else {
      rawPolygon = [
        SIMD2<Float>(xMin, zMin),
        SIMD2<Float>(xMax, zMin),
        SIMD2<Float>(xMax, zMax),
        SIMD2<Float>(xMin, zMax)
      ]
    }

    rawPolygon = Self.cleanPolygonVertices(rawPolygon)
    guard rawPolygon.count >= 3 else { return nil }
    if Self.polygonSignedArea(rawPolygon) < 0 {
      rawPolygon.reverse()
    }

    @inline(__always)
    func uvAt(_ p: SIMD2<Float>) -> SIMD2<Float> {
      let u = min(max((p.x - xMin) / max(xMax - xMin, 1e-5), 0.0), 1.0)
      let v = min(max((p.y - zMin) / max(zMax - zMin, 1e-5), 0.0), 1.0)
      return SIMD2<Float>(u, 1.0 - v)
    }

    // 2. Determine whether the entire site boundary polygon is active or if criteria sliders filtered out interior columns
    let isFullSiteActive = output.summary.candidateColumns >= output.summary.validColumns

    var activeTriangles: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = []
    var borderSegments: [(SIMD2<Float>, SIMD2<Float>)] = []

    if isFullSiteActive {
      // Full site is active: triangulate the exact smooth boundary polygon directly (identical to 3D Layer)
      let maxEdgeLen = max(stepX, stepZ) * 1.25
      let subdividedPoly = Self.subdividePolygon(rawPolygon, maxEdgeLen: maxEdgeLen)
      activeTriangles = Self.triangulateConvexOrConcavePolygon(subdividedPoly)
      for i in 0 ..< rawPolygon.count {
        let p0 = rawPolygon[i]
        let p1 = rawPolygon[(i + 1) % rawPolygon.count]
        if simd_distance(p0, p1) > 1e-4 {
          borderSegments.append((p0, p1))
        }
      }
    } else {
      // Partial site active: classify interior vs exterior grid cells and build a smooth indicator field
      var cellState = [Float](repeating: -1.0, count: grid.nx * grid.ny)
      var interiorPoints: [(x: Int, y: Int, state: Float)] = []
      var hasFilteredInterior = false

      for x in 0 ..< grid.nx {
        for y in 0 ..< grid.ny {
          let col = grid.column(x, y)
          if output.topDepthMXY[col] != nil {
            cellState[col] = 1.0
            interiorPoints.append((x, y, 1.0))
          } else {
            let p = SIMD2<Float>(
              BearingCandidateGeometry.localX(Double(x), output: output, volume: volume),
              BearingCandidateGeometry.localZ(Double(y), output: output, volume: volume)
            )
            if Self.isPointInPolygon2D(p, polygon: rawPolygon) {
              cellState[col] = 0.0
              interiorPoints.append((x, y, 0.0))
              hasFilteredInterior = true
            }
          }
        }
      }

      if !hasFilteredInterior {
        let maxEdgeLen = max(stepX, stepZ) * 1.25
        let subdividedPoly = Self.subdividePolygon(rawPolygon, maxEdgeLen: maxEdgeLen)
        activeTriangles = Self.triangulateConvexOrConcavePolygon(subdividedPoly)
        for i in 0 ..< rawPolygon.count {
          let p0 = rawPolygon[i]
          let p1 = rawPolygon[(i + 1) % rawPolygon.count]
          if simd_distance(p0, p1) > 1e-4 {
            borderSegments.append((p0, p1))
          }
        }
      } else {
        // Extrapolate exterior cells from nearest interior cell so the outer polygon boundary never stair-steps
        for x in 0 ..< grid.nx {
          for y in 0 ..< grid.ny {
            let col = grid.column(x, y)
            if cellState[col] < 0 {
              var bestDist = Int.max
              var bestVal: Float = 1.0
              for pt in interiorPoints {
                let d = (x - pt.x) * (x - pt.x) + (y - pt.y) * (y - pt.y)
                if d < bestDist {
                  bestDist = d
                  bestVal = pt.state
                }
              }
              cellState[col] = bestVal
            }
          }
        }

        // 1 pass of 3x3 Gaussian-like spatial smoothing so internal criteria cut-offs curve smoothly
        var smoothIndicator = cellState
        for x in 0 ..< grid.nx {
          for y in 0 ..< grid.ny {
            let col = grid.column(x, y)
            var sum: Float = 0
            var weightSum: Float = 0
            for dx in -1 ... 1 {
              for dy in -1 ... 1 {
                let nx = min(max(x + dx, 0), grid.nx - 1)
                let ny = min(max(y + dy, 0), grid.ny - 1)
                let w: Float = (dx == 0 && dy == 0) ? 4.0 : ((dx == 0 || dy == 0) ? 2.0 : 1.0)
                sum += w * cellState[grid.column(nx, ny)]
                weightSum += w
              }
            }
            let avg = sum / max(weightSum, 1.0)
            // Keep active cells above threshold so thin candidate regions are preserved
            smoothIndicator[col] = cellState[col] >= 0.5 ? max(avg, 0.58) : min(avg, 0.42)
          }
        }

        @inline(__always)
        func sampleIndicator(_ p: SIMD2<Float>) -> Float {
          let u = min(max((p.x - xMin) / max(xMax - xMin, 1e-5), 0.0), 1.0)
          let v = min(max((p.y - zMin) / max(zMax - zMin, 1e-5), 0.0), 1.0)
          let gx = u * Float(max(grid.nx - 1, 1))
          let gy = (1.0 - v) * Float(max(grid.ny - 1, 1))

          let x0 = min(max(Int(floor(gx)), 0), grid.nx - 1)
          let x1 = min(x0 + 1, grid.nx - 1)
          let tx = gx - Float(x0)

          let y0 = min(max(Int(floor(gy)), 0), grid.ny - 1)
          let y1 = min(y0 + 1, grid.ny - 1)
          let ty = gy - Float(y0)

          let v00 = smoothIndicator[grid.column(x0, y0)]
          let v10 = smoothIndicator[grid.column(x1, y0)]
          let v01 = smoothIndicator[grid.column(x0, y1)]
          let v11 = smoothIndicator[grid.column(x1, y1)]

          let v0 = v00 * (1.0 - tx) + v10 * tx
          let v1 = v01 * (1.0 - tx) + v11 * tx
          return v0 * (1.0 - ty) + v1 * ty
        }

        // Subdivide the boundary-conforming triangulation to fine resolution and clip against `sampleIndicator >= 0.5`
        let targetEdgeLen = max(min(stepX, stepZ) * 0.72, 0.45)
        let fineMesh = Self.buildRefinedBoundaryTriangulation(
          polygon: rawPolygon,
          maxEdgeLength: targetEdgeLen
        )

        let isoThreshold: Float = 0.5
        for tri in fineMesh {
          let p0 = tri.a, p1 = tri.b, p2 = tri.c
          let v0 = sampleIndicator(p0)
          let v1 = sampleIndicator(p1)
          let v2 = sampleIndicator(p2)

          let clipped = Self.clipTriangleToIsoThreshold(
            p0: p0, p1: p1, p2: p2,
            v0: v0, v1: v1, v2: v2,
            e01Outer: tri.e01Outer,
            e12Outer: tri.e12Outer,
            e20Outer: tri.e20Outer,
            threshold: isoThreshold
          )
          activeTriangles.append(contentsOf: clipped.triangles)
          borderSegments.append(contentsOf: clipped.boundarySegments)
        }
      }
    }

    guard !activeTriangles.isEmpty else { return nil }

    // 3. Emit Top Cap (Y = 0), Bottom Cap (Y = -0.08), and Side Walls for the smooth surface mesh
    let yTopSurface: Float = 0.0
    let yBotSurface: Float = -0.08

    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    positions.reserveCapacity(activeTriangles.count * 6 + borderSegments.count * 4)
    normals.reserveCapacity(activeTriangles.count * 6 + borderSegments.count * 4)
    uvs.reserveCapacity(activeTriangles.count * 6 + borderSegments.count * 4)
    indices.reserveCapacity(activeTriangles.count * 6 + borderSegments.count * 6)

    for tri in activeTriangles {
      let a = tri.0
      let b = tri.1
      let c = tri.2
      let uvA = uvAt(a)
      let uvB = uvAt(b)
      let uvC = uvAt(c)

      // Top face (+Y normal, CCW winding: a, c, b). Double-sided via `faceCulling = .none`
      // so transparent blending over the Map Overlay plane passes through a single surface layer.
      let baseTop = UInt32(positions.count)
      positions.append(SIMD3<Float>(a.x, yTopSurface, a.y))
      positions.append(SIMD3<Float>(c.x, yTopSurface, c.y))
      positions.append(SIMD3<Float>(b.x, yTopSurface, b.y))
      normals.append(contentsOf: [
        SIMD3<Float>(0, 1, 0),
        SIMD3<Float>(0, 1, 0),
        SIMD3<Float>(0, 1, 0)
      ])
      uvs.append(contentsOf: [uvA, uvC, uvB])
      indices.append(contentsOf: [baseTop, baseTop + 1, baseTop + 2])
    }

    // Side wall extrusion along smooth perimeter segments
    for seg in borderSegments {
      let p0 = seg.0
      let p1 = seg.1
      let d = p1 - p0
      let len = simd_length(d)
      guard len > 1e-4 else { continue }
      let n = SIMD3<Float>(d.y / len, 0, -d.x / len)
      let uv0 = uvAt(p0)
      let uv1 = uvAt(p1)

      let base = UInt32(positions.count)
      positions.append(contentsOf: [
        SIMD3<Float>(p0.x, yBotSurface, p0.y),
        SIMD3<Float>(p0.x, yTopSurface, p0.y),
        SIMD3<Float>(p1.x, yTopSurface, p1.y),
        SIMD3<Float>(p1.x, yBotSurface, p1.y)
      ])
      normals.append(contentsOf: [n, n, n, n])
      uvs.append(contentsOf: [uv0, uv0, uv1, uv1])
      indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
    }

    var surfaceDescriptor = MeshDescriptor(name: "BearingDepthHeatmap")
    surfaceDescriptor.positions = MeshBuffers.Positions(positions)
    surfaceDescriptor.normals = MeshBuffers.Normals(normals)
    surfaceDescriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
    surfaceDescriptor.primitives = .triangles(indices)
    guard let surfaceMesh = try? MeshResource.generate(from: [surfaceDescriptor]) else {
      return nil
    }

    // 4. Synthesize smooth 3D perimeter border mesh (1 draw call)
    let borderMesh = Self.synthesizeSmoothBorderMesh(segments: borderSegments)
    return SmoothBearingGeometry(surfaceMesh: surfaceMesh, borderMesh: borderMesh)
  }

  /// Synthesizes a single batched 3D border ribbon with smooth rounded joint caps along `segments`.
  @MainActor
  private static func synthesizeSmoothBorderMesh(
    segments: [(SIMD2<Float>, SIMD2<Float>)]
  ) -> MeshResource? {
    guard !segments.isEmpty else { return nil }

    let halfThick: Float = 0.08
    let yTop: Float = 0.04
    let yBot: Float = -0.10

    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    positions.reserveCapacity(segments.count * 24)
    normals.reserveCapacity(segments.count * 24)
    indices.reserveCapacity(segments.count * 36)

    @inline(__always)
    func emitQuad(
      _ v0: SIMD3<Float>,
      _ v1: SIMD3<Float>,
      _ v2: SIMD3<Float>,
      _ v3: SIMD3<Float>,
      normal: SIMD3<Float>
    ) {
      let base = UInt32(positions.count)
      positions.append(contentsOf: [v0, v1, v2, v3])
      normals.append(contentsOf: [normal, normal, normal, normal])
      indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
    }

    var jointCenters: [SIMD2<Float>] = []
    jointCenters.reserveCapacity(segments.count + 2)

    func addJointIfUnique(_ pt: SIMD2<Float>) {
      for existing in jointCenters {
        if simd_distance_squared(existing, pt) < 1e-5 {
          return
        }
      }
      jointCenters.append(pt)
    }

    for seg in segments {
      let p0 = seg.0
      let p1 = seg.1
      let dirVec = p1 - p0
      let len = simd_length(dirVec)
      guard len > 1e-4 else { continue }

      addJointIfUnique(p0)
      addJointIfUnique(p1)

      let dir = dirVec / len
      let perp = SIMD2<Float>(dir.y, -dir.x) * halfThick

      let aOut = p0 + perp
      let aIn = p0 - perp
      let bOut = p1 + perp
      let bIn = p1 - perp

      let nOut = SIMD3<Float>(dir.y, 0, -dir.x)
      let nIn = SIMD3<Float>(-dir.y, 0, dir.x)

      // Top face (+Y)
      emitQuad(
        SIMD3<Float>(aIn.x, yTop, aIn.y),
        SIMD3<Float>(aOut.x, yTop, aOut.y),
        SIMD3<Float>(bOut.x, yTop, bOut.y),
        SIMD3<Float>(bIn.x, yTop, bIn.y),
        normal: SIMD3<Float>(0, 1, 0)
      )
      // Bottom face (-Y)
      emitQuad(
        SIMD3<Float>(aOut.x, yBot, aOut.y),
        SIMD3<Float>(aIn.x, yBot, aIn.y),
        SIMD3<Float>(bIn.x, yBot, bIn.y),
        SIMD3<Float>(bOut.x, yBot, bOut.y),
        normal: SIMD3<Float>(0, -1, 0)
      )
      // Outer side wall
      emitQuad(
        SIMD3<Float>(aOut.x, yBot, aOut.y),
        SIMD3<Float>(bOut.x, yBot, bOut.y),
        SIMD3<Float>(bOut.x, yTop, bOut.y),
        SIMD3<Float>(aOut.x, yTop, aOut.y),
        normal: nOut
      )
      // Inner side wall
      emitQuad(
        SIMD3<Float>(bIn.x, yBot, bIn.y),
        SIMD3<Float>(aIn.x, yBot, aIn.y),
        SIMD3<Float>(aIn.x, yTop, aIn.y),
        SIMD3<Float>(bIn.x, yTop, bIn.y),
        normal: nIn
      )
    }

    // Emit smooth vertical cylinder caps at every corner/joint vertex so angled edges meet seamlessly
    let capSides = 10
    for c in jointCenters {
      let topCenterIdx = UInt32(positions.count)
      positions.append(SIMD3<Float>(c.x, yTop, c.y))
      normals.append(SIMD3<Float>(0, 1, 0))

      let botCenterIdx = UInt32(positions.count)
      positions.append(SIMD3<Float>(c.x, yBot, c.y))
      normals.append(SIMD3<Float>(0, -1, 0))

      for s in 0 ..< capSides {
        let a0 = (Float(s) / Float(capSides)) * (.pi * 2.0)
        let a1 = (Float(s + 1) / Float(capSides)) * (.pi * 2.0)
        let d0 = SIMD2<Float>(cos(a0), sin(a0))
        let d1 = SIMD2<Float>(cos(a1), sin(a1))
        let p0 = c + d0 * halfThick
        let p1 = c + d1 * halfThick

        // Top fan triangle (+Y)
        let tBase = UInt32(positions.count)
        positions.append(SIMD3<Float>(p0.x, yTop, p0.y))
        positions.append(SIMD3<Float>(p1.x, yTop, p1.y))
        normals.append(SIMD3<Float>(0, 1, 0))
        normals.append(SIMD3<Float>(0, 1, 0))
        indices.append(contentsOf: [topCenterIdx, tBase + 1, tBase])

        // Bottom fan triangle (-Y)
        let bBase = UInt32(positions.count)
        positions.append(SIMD3<Float>(p0.x, yBot, p0.y))
        positions.append(SIMD3<Float>(p1.x, yBot, p1.y))
        normals.append(SIMD3<Float>(0, -1, 0))
        normals.append(SIMD3<Float>(0, -1, 0))
        indices.append(contentsOf: [botCenterIdx, bBase, bBase + 1])

        // Side quad
        let nMid = simd_normalize(SIMD3<Float>(d0.x + d1.x, 0, d0.y + d1.y))
        emitQuad(
          SIMD3<Float>(p0.x, yBot, p0.y),
          SIMD3<Float>(p0.x, yTop, p0.y),
          SIMD3<Float>(p1.x, yTop, p1.y),
          SIMD3<Float>(p1.x, yBot, p1.y),
          normal: nMid
        )
      }
    }

    guard !positions.isEmpty else { return nil }
    var descriptor = MeshDescriptor(name: "BearingSmoothBorderManifold")
    descriptor.positions = MeshBuffers.Positions(positions)
    descriptor.normals = MeshBuffers.Normals(normals)
    descriptor.primitives = .triangles(indices)
    return try? MeshResource.generate(from: [descriptor])
  }

  // MARK: - 2D Polygon Triangulation & Iso-Contour Clipping Helpers

  private struct RefinedTriangle {
    let a: SIMD2<Float>
    let b: SIMD2<Float>
    let c: SIMD2<Float>
    let e01Outer: Bool
    let e12Outer: Bool
    let e20Outer: Bool
  }

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

  private static func subdividePolygon(_ polygon: [SIMD2<Float>], maxEdgeLen: Float) -> [SIMD2<Float>] {
    guard polygon.count >= 3, maxEdgeLen > 1e-3 else { return polygon }
    var subdivided: [SIMD2<Float>] = []
    subdivided.reserveCapacity(polygon.count * 4)

    for i in 0 ..< polygon.count {
      let p0 = polygon[i]
      let p1 = polygon[(i + 1) % polygon.count]
      let edgeVec = p1 - p0
      let edgeLen = simd_length(edgeVec)
      subdivided.append(p0)
      if edgeLen > maxEdgeLen {
        let subs = Int(ceil(edgeLen / maxEdgeLen))
        for s in 1 ..< subs {
          let t = Float(s) / Float(subs)
          subdivided.append(p0 + t * edgeVec)
        }
      }
    }
    return cleanPolygonVertices(subdivided)
  }

  private static func isPointInPolygon2D(_ p: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
    guard polygon.count >= 3 else { return false }
    var inside = false
    var j = polygon.count - 1
    for i in 0 ..< polygon.count {
      let pi = polygon[i]
      let pj = polygon[j]
      let denom = (pj.y - pi.y) == 0 ? 1e-7 : (pj.y - pi.y)
      let intersect = ((pi.y > p.y) != (pj.y > p.y)) &&
        (p.x < (pj.x - pi.x) * (p.y - pi.y) / denom + pi.x)
      if intersect {
        inside.toggle()
      }
      j = i
    }
    return inside
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

  private static func buildRefinedBoundaryTriangulation(
    polygon: [SIMD2<Float>],
    maxEdgeLength: Float
  ) -> [RefinedTriangle] {
    let baseTris = triangulateConvexOrConcavePolygon(polygon)
    guard !baseTris.isEmpty else { return [] }

    func isOuterEdge(_ p0: SIMD2<Float>, _ p1: SIMD2<Float>) -> Bool {
      for i in 0 ..< polygon.count {
        let a = polygon[i]
        let b = polygon[(i + 1) % polygon.count]
        if simd_distance(p0, a) < 1e-3 && simd_distance(p1, b) < 1e-3 {
          return true
        }
      }
      return false
    }

    var queue: [RefinedTriangle] = baseTris.map { t in
      RefinedTriangle(
        a: t.0,
        b: t.1,
        c: t.2,
        e01Outer: isOuterEdge(t.0, t.1),
        e12Outer: isOuterEdge(t.1, t.2),
        e20Outer: isOuterEdge(t.2, t.0)
      )
    }

    var result: [RefinedTriangle] = []
    result.reserveCapacity(baseTris.count * 16)
    let maxAllowed = max(maxEdgeLength, 0.35)
    let maxTriangleLimit = 4096

    while let tri = queue.popLast() {
      let l01 = simd_distance(tri.a, tri.b)
      let l12 = simd_distance(tri.b, tri.c)
      let l20 = simd_distance(tri.c, tri.a)
      let maxL = max(l01, max(l12, l20))

      if maxL <= maxAllowed || (queue.count + result.count) >= maxTriangleLimit {
        result.append(tri)
        continue
      }

      if l01 >= l12 && l01 >= l20 {
        let mid = (tri.a + tri.b) * 0.5
        queue.append(RefinedTriangle(a: tri.a, b: mid, c: tri.c, e01Outer: tri.e01Outer, e12Outer: false, e20Outer: tri.e20Outer))
        queue.append(RefinedTriangle(a: mid, b: tri.b, c: tri.c, e01Outer: tri.e01Outer, e12Outer: tri.e12Outer, e20Outer: false))
      } else if l12 >= l01 && l12 >= l20 {
        let mid = (tri.b + tri.c) * 0.5
        queue.append(RefinedTriangle(a: tri.a, b: tri.b, c: mid, e01Outer: tri.e01Outer, e12Outer: tri.e12Outer, e20Outer: false))
        queue.append(RefinedTriangle(a: tri.a, b: mid, c: tri.c, e01Outer: false, e12Outer: tri.e12Outer, e20Outer: tri.e20Outer))
      } else {
        let mid = (tri.c + tri.a) * 0.5
        queue.append(RefinedTriangle(a: tri.a, b: tri.b, c: mid, e01Outer: tri.e01Outer, e12Outer: false, e20Outer: tri.e20Outer))
        queue.append(RefinedTriangle(a: mid, b: tri.b, c: tri.c, e01Outer: false, e12Outer: tri.e12Outer, e20Outer: tri.e20Outer))
      }
    }

    return result
  }

  private static func clipTriangleToIsoThreshold(
    p0: SIMD2<Float>,
    p1: SIMD2<Float>,
    p2: SIMD2<Float>,
    v0: Float,
    v1: Float,
    v2: Float,
    e01Outer: Bool,
    e12Outer: Bool,
    e20Outer: Bool,
    threshold: Float
  ) -> (
    triangles: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)],
    boundarySegments: [(SIMD2<Float>, SIMD2<Float>)]
  ) {
    let in0 = v0 >= threshold
    let in1 = v1 >= threshold
    let in2 = v2 >= threshold

    if !in0 && !in1 && !in2 {
      return ([], [])
    }

    if in0 && in1 && in2 {
      var segs: [(SIMD2<Float>, SIMD2<Float>)] = []
      if e01Outer { segs.append((p0, p1)) }
      if e12Outer { segs.append((p1, p2)) }
      if e20Outer { segs.append((p2, p0)) }
      return ([(p0, p1, p2)], segs)
    }

    @inline(__always)
    func interp(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ va: Float, _ vb: Float) -> SIMD2<Float> {
      let denom = vb - va
      let t = abs(denom) > 1e-6 ? min(max((threshold - va) / denom, 0.0), 1.0) : 0.5
      return a + t * (b - a)
    }

    let pts = [p0, p1, p2]
    let vals = [v0, v1, v2]
    let ins = [in0, in1, in2]
    let outers = [e01Outer, e12Outer, e20Outer]

    var poly: [SIMD2<Float>] = []
    var segs: [(SIMD2<Float>, SIMD2<Float>)] = []
    var cutEnter: SIMD2<Float>?
    var cutExit: SIMD2<Float>?

    for i in 0 ..< 3 {
      let j = (i + 1) % 3
      let a = pts[i], b = pts[j]
      let va = vals[i], vb = vals[j]
      let inA = ins[i], inB = ins[j]
      let isOuter = outers[i]

      if inA && inB {
        poly.append(b)
        if isOuter { segs.append((a, b)) }
      } else if inA && !inB {
        let cut = interp(a, b, va, vb)
        poly.append(cut)
        cutExit = cut
        if isOuter { segs.append((a, cut)) }
      } else if !inA && inB {
        let cut = interp(a, b, va, vb)
        poly.append(cut)
        poly.append(b)
        cutEnter = cut
        if isOuter { segs.append((cut, b)) }
      }
    }

    if let exitPt = cutExit, let enterPt = cutEnter, simd_distance(exitPt, enterPt) > 1e-5 {
      segs.append((exitPt, enterPt))
    }

    if poly.count == 3 {
      return ([(poly[0], poly[1], poly[2])], segs)
    } else if poly.count == 4 {
      return ([(poly[0], poly[1], poly[2]), (poly[0], poly[2], poly[3])], segs)
    }
    return ([], [])
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

    for (idx, pos) in cptLocalPositions(for: volume, output: bearingOutput).prefix(measuredCPTCount).enumerated() {
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
    let grid = output.grid
    let nx = grid.nx
    let ny = grid.ny
    guard nx > 0, ny > 0,
          let shallow = output.summary.shallowestTopDepthM,
          let deep = output.summary.deepestBottomDepthM else { return nil }

    let shallowF = Float(shallow)
    let deepF = Float(deep)
    let depthSpan = max(deepF - shallowF, 1e-6)

    // 1. Collect active candidate column depths and extrapolate empty/exterior cells from nearest active neighbors
    var activeCells: [(x: Int, y: Int, depth: Float)] = []
    activeCells.reserveCapacity(nx * ny)
    for x in 0 ..< nx {
      for y in 0 ..< ny {
        if let top = output.topDepthMXY[grid.column(x, y)] {
          activeCells.append((x, y, Float(top)))
        }
      }
    }
    guard !activeCells.isEmpty else { return nil }

    var filledDepth = [Float](repeating: shallowF, count: nx * ny)
    for x in 0 ..< nx {
      for y in 0 ..< ny {
        let col = grid.column(x, y)
        if let top = output.topDepthMXY[col] {
          filledDepth[col] = Float(top)
        } else {
          // Inverse-distance weighted extrapolation from nearest active candidate cells
          var bestD1 = Int.max, bestD2 = Int.max, bestD3 = Int.max
          var val1 = shallowF, val2 = shallowF, val3 = shallowF
          for cell in activeCells {
            let d = (x - cell.x) * (x - cell.x) + (y - cell.y) * (y - cell.y)
            if d < bestD1 {
              bestD3 = bestD2; val3 = val2
              bestD2 = bestD1; val2 = val1
              bestD1 = d; val1 = cell.depth
            } else if d < bestD2 {
              bestD3 = bestD2; val3 = val2
              bestD2 = d; val2 = cell.depth
            } else if d < bestD3 {
              bestD3 = d; val3 = cell.depth
            }
          }
          if bestD2 == Int.max {
            filledDepth[col] = val1
          } else {
            let w1 = 1.0 / Float(max(bestD1, 1))
            let w2 = 1.0 / Float(max(bestD2, 1))
            let w3 = bestD3 < Int.max ? (1.0 / Float(max(bestD3, 1))) : 0.0
            filledDepth[col] = (w1 * val1 + w2 * val2 + w3 * val3) / (w1 + w2 + w3)
          }
        }
      }
    }

    // 2. Subtle 3x3 spatial smoothing across the discrete dzM steps for natural geological contour transitions
    var smoothedDepth = filledDepth
    for x in 0 ..< nx {
      for y in 0 ..< ny {
        var sum: Float = 0
        var wTotal: Float = 0
        for dx in -1 ... 1 {
          for dy in -1 ... 1 {
            let qx = min(max(x + dx, 0), nx - 1)
            let qy = min(max(y + dy, 0), ny - 1)
            let w: Float = (dx == 0 && dy == 0) ? 4.0 : ((dx == 0 || dy == 0) ? 2.0 : 1.0)
            sum += w * filledDepth[grid.column(qx, qy)]
            wTotal += w
          }
        }
        smoothedDepth[grid.column(x, y)] = sum / max(wTotal, 1.0)
      }
    }

    // 3. Render high-resolution bilinearly interpolated contour heatmap texture
    let texWidth = 480
    let texHeight = 480
    var pixels = [UInt8](repeating: 255, count: texWidth * texHeight * 4)
    let maxGX = Float(max(nx - 1, 1))
    let maxGY = Float(max(ny - 1, 1))
    let bands: Float = 16.0

    for py in 0 ..< texHeight {
      let v = Float(py) / Float(texHeight - 1) // 0 = North (top row), 1 = South (bottom row)
      let gy = (1.0 - v) * maxGY
      let y0 = min(max(Int(floor(gy)), 0), ny - 1)
      let y1 = min(y0 + 1, ny - 1)
      let ty = gy - Float(y0)

      for px in 0 ..< texWidth {
        let u = Float(px) / Float(texWidth - 1) // 0 = West (left col), 1 = East (right col)
        let gx = u * maxGX
        let x0 = min(max(Int(floor(gx)), 0), nx - 1)
        let x1 = min(x0 + 1, nx - 1)
        let tx = gx - Float(x0)

        let d00 = smoothedDepth[grid.column(x0, y0)]
        let d10 = smoothedDepth[grid.column(x1, y0)]
        let d01 = smoothedDepth[grid.column(x0, y1)]
        let d11 = smoothedDepth[grid.column(x1, y1)]

        let d0 = d00 * (1.0 - tx) + d10 * tx
        let d1 = d01 * (1.0 - tx) + d11 * tx
        let top = d0 * (1.0 - ty) + d1 * ty

        let ratio = (top - shallowF) / depthSpan
        let scaled = min(max(ratio, 0.0), 1.0) * bands
        let band = floor(scaled)
        let fraction = scaled - band
        let softenedEdge = fraction < 0.82 ? 0.0 : (fraction - 0.82) / 0.18
        var color = contourColormap(t: min((band + softenedEdge) / bands, 1.0))
        if fraction > 0.86 {
          color.0 *= 0.95
          color.1 *= 0.95
          color.2 *= 0.95
        }

        let offset = (py * texWidth + px) * 4
        pixels[offset] = UInt8(min(max(Int(color.0 * 255), 0), 255))
        pixels[offset + 1] = UInt8(min(max(Int(color.1 * 255), 0), 255))
        pixels[offset + 2] = UInt8(min(max(Int(color.2 * 255), 0), 255))
        pixels[offset + 3] = 255
      }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let cgImage = CGImage(
            width: texWidth,
            height: texHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: texWidth * 4,
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
