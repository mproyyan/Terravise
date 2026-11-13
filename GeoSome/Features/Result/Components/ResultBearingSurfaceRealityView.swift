import RealityKit
import simd
import SwiftUI
import UIKit

struct ResultBearingSurfaceRealityView: View {
  let volume: SubsurfaceVoxelVolume
  @Binding var cameraYaw: Float
  @Binding var cameraPitch: Float
  @Binding var cameraZoom: Float
  @Binding var isProfilePopoverPresented: Bool
  @Binding var profilePopoverLocation: CGPoint?
  var popoverTitle: String = "CPT Point-01"
  var popoverLatitude: String = "-6.215432"
  var popoverLongitude: String = "106.845321"
  var popoverLayers: [SBTProfileLayerItem] = CPTPointProfilePopoverView.defaultLayers
  var onTapCPTPoint: ((CGPoint, Int) -> Void)? = nil
  var onSelectBearingVoxel: ((BearingLayerVoxel?) -> Void)? = nil

  @State private var dragStartYaw: Float?
  @State private var dragStartPitch: Float?
  @State private var pinchStartZoom: Float?
  @State private var lastBuiltVolumeID: UUID?

  // Cached textures so they are synthesized only once
  @MainActor private static var cachedHeatmapTexture: TextureResource?
  @MainActor private static var cachedBadgeTextures: [String: TextureResource] = [:]

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        RealityView { content in
          content.camera = .virtual

          let rootAnchor = Entity()
          rootAnchor.name = "BearingSurfaceRootAnchor"

          let pivotEntity = Entity()
          pivotEntity.name = "BearingSurfacePivot"
          pivotEntity.position = computeSceneOffset()
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

          pivotEntity.position = computeSceneOffset()
          pivotEntity.orientation = makeOrbitOrientation(yaw: cameraYaw, pitch: cameraPitch)
          let scale = computeNormalizedScale(for: volume) * cameraZoom
          pivotEntity.scale = SIMD3<Float>(repeating: scale)

          if lastBuiltVolumeID != volume.id {
            populatePivotScene(pivotEntity: pivotEntity, volume: volume)
            Task { @MainActor in
              lastBuiltVolumeID = volume.id
            }
          }
        }
        .gesture(orbitDragGesture)
        .simultaneousGesture(zoomMagnifyGesture)
        .simultaneousGesture(targetedTapGesture)

        // Background tap-to-dismiss layer when popover is visible
        if isProfilePopoverPresented {
          Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture {
              withAnimation(.easeInOut(duration: 0.2)) {
                isProfilePopoverPresented = false
              }
            }
        }

        // Native-looking Popover Overlay
        if isProfilePopoverPresented, let tapLoc = profilePopoverLocation {
          let popoverWidth: CGFloat = min(348, proxy.size.width - 32)
          let popoverHeight: CGFloat = 370
          let arrowEdge: Edge = tapLoc.x >= (proxy.size.width * 0.45) ? .trailing : .leading

          let originX: CGFloat = arrowEdge == .trailing
            ? max(tapLoc.x - popoverWidth - 6, 16)
            : min(tapLoc.x + 6, proxy.size.width - popoverWidth - 16)

          let rawOriginY = tapLoc.y - (popoverHeight * 0.35)
          let clampedOriginY = min(max(rawOriginY, 70), max(proxy.size.height - popoverHeight - 90, 70))
          let localArrowY = min(max(tapLoc.y - clampedOriginY, 32), popoverHeight - 32)

          CPTPointProfilePopoverView(
            pointTitle: popoverTitle,
            latitudeText: popoverLatitude,
            longitudeText: popoverLongitude,
            layers: popoverLayers,
            onClose: {
              withAnimation(.easeInOut(duration: 0.2)) {
                isProfilePopoverPresented = false
              }
            }
          )
          .padding(18)
          .frame(width: popoverWidth)
          .background {
            PopoverBubbleShape(
              arrowEdge: arrowEdge,
              arrowY: localArrowY,
              cornerRadius: 18,
              arrowWidth: 16,
              arrowHeight: 10
            )
            .fill(Color(.systemBackground).opacity(0.96))
            .overlay {
              PopoverBubbleShape(
                arrowEdge: arrowEdge,
                arrowY: localArrowY,
                cornerRadius: 18,
                arrowWidth: 16,
                arrowHeight: 10
              )
              .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 6)
          }
          .position(x: originX + popoverWidth * 0.5, y: clampedOriginY + popoverHeight * 0.5)
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

    // 1. Flat 3D 1m²-Voxel Surface Mesh with Contour Depth Heatmap Texture (1 Draw Call)
    let surfaceEntity = makeBearingSurfaceEntity(for: volume)
    surfaceEntity.name = "BearingSurfacePlane"
    pivotEntity.addChild(surfaceEntity)

    // 2. Crisp Dark Border Frame along the outer 1m² Voxel Boundary Perimeter (1 Draw Call)
    let borderEntity = makeSurfaceBorderEntity(for: volume)
    borderEntity.name = "BearingSurfaceBorder"
    pivotEntity.addChild(borderEntity)

    // 3. CPT Markers on 1m² Voxel Surface (CPT-01, CPT-02, CPT-03...)
    let cptMarkersEntity = makeCPTMarkersContainer(for: volume)
    cptMarkersEntity.name = "BearingCPTMarkers"
    pivotEntity.addChild(cptMarkersEntity)

    // 4. Perimeter Ruler Axes: X (m) along front edge, Y (m) along right edge
    let axesEntity = makeRulerAxesEntity(for: volume)
    axesEntity.name = "BearingRulerAxes"
    pivotEntity.addChild(axesEntity)
  }

  // MARK: - Gestures

  private var orbitDragGesture: some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        if dragStartYaw == nil {
          dragStartYaw = cameraYaw
          dragStartPitch = cameraPitch
        }
        let baseYaw = dragStartYaw ?? cameraYaw
        let basePitch = dragStartPitch ?? cameraPitch
        let deltaYaw = Float(value.translation.width) * 0.0065
        let deltaPitch = Float(value.translation.height) * 0.0055

        cameraYaw = min(max(baseYaw + deltaYaw, -0.85), 0.85)
        cameraPitch = min(max(basePitch + deltaPitch, 0.25), 1.35)
      }
      .onEnded { _ in
        dragStartYaw = nil
        dragStartPitch = nil
      }
  }

  private var zoomMagnifyGesture: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        if pinchStartZoom == nil {
          pinchStartZoom = cameraZoom
        }
        let baseZoom = pinchStartZoom ?? cameraZoom
        let updated = baseZoom * Float(value.magnification)
        cameraZoom = min(max(updated, 0.65), 2.1)
      }
      .onEnded { _ in
        pinchStartZoom = nil
      }
  }

  private var targetedTapGesture: some Gesture {
    SpatialTapGesture()
      .targetedToAnyEntity()
      .onEnded { value in
        let name = value.entity.name
        if name.hasPrefix("BearingCPT_"),
           let idxStr = name.split(separator: "_").last,
           let idx = Int(idxStr)
        {
          if idx < volume.cptSurfacePositions.count {
            let pos = volume.cptSurfacePositions[idx]
            let xGrid = Int((pos.x + volume.centerX).rounded())
            let zGrid = Int((pos.z + volume.centerZ).rounded())
            onSelectBearingVoxel?(volume.bearingVoxels[ColumnCoord(x: xGrid, z: zGrid)])
          }
          onTapCPTPoint?(value.location, idx)
        } else {
          // Resolve exact 1m² BearingLayerVoxel at tap point in O(1) time
          let hits = value.hitTest(point: value.location, in: .local)
          if let firstHit = hits.first,
             let pivot = findPivotEntity(from: value.entity)
          {
            let localPt = pivot.convert(position: firstHit.position, from: nil)
            let xGrid = Int((localPt.x + volume.centerX).rounded())
            let zGrid = Int((localPt.z + volume.centerZ).rounded())
            let tappedBearingVoxel = volume.bearingVoxels[ColumnCoord(x: xGrid, z: zGrid)]
            onSelectBearingVoxel?(tappedBearingVoxel)

            var bestIdx = 0
            var bestDist = Float.greatestFiniteMagnitude
            for (i, pos) in volume.cptSurfacePositions.enumerated() {
              let d = (localPt.x - pos.x) * (localPt.x - pos.x) + (localPt.z - pos.z) * (localPt.z - pos.z)
              if d < bestDist {
                bestDist = d
                bestIdx = i
              }
            }
            onTapCPTPoint?(value.location, bestIdx)
          } else {
            onTapCPTPoint?(value.location, 0)
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

  private func makeOrbitOrientation(yaw: Float, pitch: Float) -> simd_quatf {
    let pitchQuat = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
    let yawQuat = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
    return simd_mul(pitchQuat, yawQuat)
  }

  // MARK: - 1. Flat 3D 1m² Voxel Surface Mesh with Contour Heatmap

  @MainActor
  private func makeBearingSurfaceEntity(for volume: SubsurfaceVoxelVolume) -> ModelEntity {
    let width = Float(volume.nx)
    let depth = Float(volume.nz)

    let mesh = VoxelMeshSynthesizer.synthesizeBearingVoxelSurfaceMesh(volume: volume)
      ?? MeshResource.generatePlane(width: width, depth: depth)

    var material = UnlitMaterial()
    if let tex = Self.getOrCreateHeatmapTexture() {
      material.color = .init(tint: .white, texture: .init(tex))
    } else {
      material.color = .init(tint: UIColor(red: 0.14, green: 0.62, blue: 0.68, alpha: 1.0))
    }

    let entity = ModelEntity(mesh: mesh, materials: [material])
    entity.position = .zero
    entity.components.set(CollisionComponent(shapes: [
      .generateBox(size: [width, 0.25, depth])
    ]))
    entity.components.set(InputTargetComponent())
    return entity
  }

  // MARK: - 2. Surface Border Frame Around Active 1m² Voxel Boundary

  @MainActor
  private func makeSurfaceBorderEntity(for volume: SubsurfaceVoxelVolume) -> Entity {
    let borderMat = UnlitMaterial(color: UIColor(white: 0.18, alpha: 1.0))
    if let borderMesh = VoxelMeshSynthesizer.synthesizeBearingVoxelBorderMesh(volume: volume) {
      return ModelEntity(mesh: borderMesh, materials: [borderMat])
    }
    return Entity()
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

    for (idx, pos) in volume.cptSurfacePositions.enumerated() {
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

    let xTickValues = [0, 2, 4, 6, 8, 10]
    for val in xTickValues {
      let t = Float(val) / 10.0
      let tx = minX + t * xLength

      let tick = ModelEntity(
        mesh: .generateBox(width: 0.12, height: 0.10, depth: 0.6),
        materials: [axisMaterial]
      )
      tick.position = SIMD3<Float>(tx, 0, frontZ + 0.3)
      container.addChild(tick)

      let labelEntity = makeAxisTextEntity(text: "\(val)", size: 0.95, color: axisColor)
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

    let yTickValues = [0, 1, 2, 3, 4]
    for val in yTickValues {
      let t = Float(val) / 4.0
      let tz = maxZ - t * zLength

      let tick = ModelEntity(
        mesh: .generateBox(width: 0.6, height: 0.10, depth: 0.12),
        materials: [axisMaterial]
      )
      tick.position = SIMD3<Float>(rightX + 0.3, 0, tz)
      container.addChild(tick)

      let labelEntity = makeAxisTextEntity(text: "\(val)", size: 0.95, color: axisColor)
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

  // MARK: - High-Speed Procedural Contour Heatmap & Badge Texture Generation

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
  private static func getOrCreateHeatmapTexture() -> TextureResource? {
    if let cached = cachedHeatmapTexture {
      return cached
    }

    let width = 560
    let height = 294
    var pixels = [UInt8](repeating: 255, count: width * height * 4)

    for py in 0 ..< height {
      let v = Float(py) / Float(height - 1) // 0 = back (top in image), 1 = front (bottom in image)
      for px in 0 ..< width {
        let u = Float(px) / Float(width - 1) // 0 = left, 1 = right

        let dVal = VoxelMeshSynthesizer.evaluateBearingDepthRatio(u: u, v: v)

        // Quantize into 16 contour bands with subtle smoothing for authentic topographic isoline look
        let numBands: Float = 16.0
        let scaled = dVal * numBands
        let bandIdx = floor(scaled)
        let frac = scaled - bandIdx
        let smoothFrac = frac < 0.82 ? 0.0 : (frac - 0.82) / 0.18
        let quantizedVal = min(max((bandIdx + smoothFrac) / numBands, 0.0), 1.0)

        var r = contourColormap(t: quantizedVal)
        if frac > 0.86 {
          r.0 *= 0.94
          r.1 *= 0.94
          r.2 *= 0.94
        }

        let offset = (py * width + px) * 4
        pixels[offset + 0] = UInt8(min(max(Int(r.0 * 255.0), 0), 255))
        pixels[offset + 1] = UInt8(min(max(Int(r.1 * 255.0), 0), 255))
        pixels[offset + 2] = UInt8(min(max(Int(r.2 * 255.0), 0), 255))
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

    cachedHeatmapTexture = tex
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
