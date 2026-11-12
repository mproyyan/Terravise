import RealityKit
import simd
import SwiftUI
import UIKit

struct ResultSubsurfaceRealityView: View {
  let volume: SubsurfaceVoxelVolume
  let maxSliceX: Int
  let maxSliceZ: Int
  let selectedVoxel: SoilVoxel?
  var selectedPipePosition3D: SIMD3<Float>? = nil
  @Binding var cameraYaw: Float
  @Binding var cameraPitch: Float
  @Binding var cameraZoom: Float
  @Binding var isProfilePopoverPresented: Bool
  @Binding var profilePopoverLocation: CGPoint?
  var popoverTitle: String = "CPT Point-01"
  var popoverLatitude: String = "-6.215432"
  var popoverLongitude: String = "106.845321"
  var onSelectVoxel: (SoilVoxel?) -> Void
  var onTapTopSurface: ((CGPoint, SIMD3<Float>, SoilVoxel?) -> Void)? = nil

  @State private var dragStartYaw: Float?
  @State private var dragStartPitch: Float?
  @State private var pinchStartZoom: Float?
  @State private var lastBuiltSliceX: Int = -1
  @State private var lastBuiltSliceZ: Int = -1
  @State private var lastBuiltVoxelCount: Int = -1

  init(
    volume: SubsurfaceVoxelVolume,
    maxSliceX: Int,
    maxSliceZ: Int,
    selectedVoxel: SoilVoxel?,
    selectedPipePosition3D: SIMD3<Float>? = nil,
    cameraYaw: Binding<Float>,
    cameraPitch: Binding<Float>,
    cameraZoom: Binding<Float>,
    isProfilePopoverPresented: Binding<Bool> = .constant(false),
    profilePopoverLocation: Binding<CGPoint?> = .constant(nil),
    popoverTitle: String = "CPT Point-01",
    popoverLatitude: String = "-6.215432",
    popoverLongitude: String = "106.845321",
    onSelectVoxel: @escaping (SoilVoxel?) -> Void,
    onTapTopSurface: ((CGPoint, SIMD3<Float>, SoilVoxel?) -> Void)? = nil
  ) {
    self.volume = volume
    self.maxSliceX = maxSliceX
    self.maxSliceZ = maxSliceZ
    self.selectedVoxel = selectedVoxel
    self.selectedPipePosition3D = selectedPipePosition3D
    self._cameraYaw = cameraYaw
    self._cameraPitch = cameraPitch
    self._cameraZoom = cameraZoom
    self._isProfilePopoverPresented = isProfilePopoverPresented
    self._profilePopoverLocation = profilePopoverLocation
    self.popoverTitle = popoverTitle
    self.popoverLatitude = popoverLatitude
    self.popoverLongitude = popoverLongitude
    self.onSelectVoxel = onSelectVoxel
    self.onTapTopSurface = onTapTopSurface
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        RealityView { content in
          // 1. Set camera mode to .virtual for non-AR 3D geotechnical visualization on iOS
          content.camera = .virtual

          let rootAnchor = Entity()
          rootAnchor.name = "SubsurfaceRootAnchor"

          // Pivot entity rotated/scaled by user orbit & zoom gestures
          let pivotEntity = Entity()
          pivotEntity.name = "SubsurfacePivot"
          pivotEntity.position = computeSceneOffset(for: volume)
          pivotEntity.orientation = makeOrbitOrientation(yaw: cameraYaw, pitch: cameraPitch)
          let initialScale = computeNormalizedScale(for: volume) * cameraZoom
          pivotEntity.scale = SIMD3<Float>(repeating: initialScale)
          rootAnchor.addChild(pivotEntity)

          // 2. Single Batched Voxel Mesh Entity (1 Draw Call, 0 per-voxel entities, 0 CollisionComponents)
          let materials = VoxelMeshSynthesizer.makeMaterialPalette()
          let terrainEntity = ModelEntity()
          terrainEntity.name = "SubsurfaceTerrainEntity"
          if let mesh = VoxelMeshSynthesizer.synthesizeMesh(
            volume: volume,
            maxSliceX: maxSliceX,
            maxSliceZ: maxSliceZ
          ) {
            terrainEntity.model = ModelComponent(mesh: mesh, materials: materials)
          }
          pivotEntity.addChild(terrainEntity)

          // 3. Single Ephemeral Highlight Marker (VoxelSelectionMarker: Visual 3D Pipe)
          let selectionMarker = makeVoxelSelectionMarker()
          selectionMarker.name = "VoxelSelectionMarker"
          selectionMarker.isEnabled = false
          pivotEntity.addChild(selectionMarker)

          // 3b. Top Surface Hit Target for High-Precision RealityKit Targeted Gestures
          let hitPlane = ModelEntity()
          hitPlane.name = "TopSurfaceHitPlane"
          let hitBoxWidth = Float(volume.nx) + 1.0
          let hitBoxLength = Float(volume.nz) + 1.0
          hitPlane.components.set(CollisionComponent(shapes: [
            .generateBox(size: [hitBoxWidth, 0.2, hitBoxLength])
          ]))
          hitPlane.components.set(InputTargetComponent())
          hitPlane.position = SIMD3<Float>(0, -0.1, 0)
          pivotEntity.addChild(hitPlane)

          // 4. CPT Sounding Borehole Pins on Surface (Y = 0)
          let cptContainer = buildCPTBoreholeMarkers(for: volume)
          cptContainer.name = "CPTBoreholeContainer"
          pivotEntity.addChild(cptContainer)

          // 5. Base Ruler Axes (X and Y meter ticks along bottom perimeter)
          let axesContainer = buildBaseAxesEntity(for: volume)
          axesContainer.name = "BaseAxesContainer"
          pivotEntity.addChild(axesContainer)

          // 6. Directional key + fill lighting for clear 3D depth perception
          let keyLight = DirectionalLight()
          keyLight.light.color = .white
          keyLight.light.intensity = 2200
          keyLight.look(
            at: .zero,
            from: SIMD3<Float>(18, 28, 24),
            relativeTo: nil
          )
          rootAnchor.addChild(keyLight)

          let fillLight = DirectionalLight()
          fillLight.light.color = UIColor(white: 0.95, alpha: 1.0)
          fillLight.light.intensity = 1100
          fillLight.look(
            at: .zero,
            from: SIMD3<Float>(-20, 14, -18),
            relativeTo: nil
          )
          rootAnchor.addChild(fillLight)

          content.add(rootAnchor)
        } update: { content in
          guard let rootAnchor = content.entities.first(where: { $0.name == "SubsurfaceRootAnchor" }),
                let pivotEntity = rootAnchor.findEntity(named: "SubsurfacePivot")
          else {
            return
          }

          // Update orbit orientation, position, and zoom scale
          pivotEntity.position = computeSceneOffset(for: volume)
          pivotEntity.orientation = makeOrbitOrientation(yaw: cameraYaw, pitch: cameraPitch)
          let scale = computeNormalizedScale(for: volume) * cameraZoom
          pivotEntity.scale = SIMD3<Float>(repeating: scale)

          // Update Single Ephemeral Selection Marker (`VoxelSelectionMarker`: Visual 3D Pipe)
          if let marker = pivotEntity.findEntity(named: "VoxelSelectionMarker") {
            if let pipePos = selectedPipePosition3D {
              marker.isEnabled = true
              marker.position = SIMD3<Float>(pipePos.x, 0.0, pipePos.z)
            } else if let voxel = selectedVoxel,
               voxel.coord.x <= maxSliceX,
               voxel.coord.z <= maxSliceZ
            {
              marker.isEnabled = true
              let pos = volume.worldPosition(for: voxel.coord)
              marker.position = SIMD3<Float>(pos.x, 0.0, pos.z)
            } else {
              marker.isEnabled = false
            }
          }

          // Update visibility of CPT borehole pins against active slicing thresholds
          if let cptContainer = pivotEntity.findEntity(named: "CPTBoreholeContainer") {
            let maxWorldX = Float(maxSliceX) - volume.centerX + 0.5
            let maxWorldZ = Float(maxSliceZ) - volume.centerZ + 0.5
            for child in cptContainer.children {
              child.isEnabled = (child.position.x <= maxWorldX) && (child.position.z <= maxWorldZ)
            }
          }

          // Rebuild the single batched MeshResource only when slicing thresholds or volume data change
          if lastBuiltSliceX != maxSliceX ||
            lastBuiltSliceZ != maxSliceZ ||
            lastBuiltVoxelCount != volume.voxels.count
          {
            if let terrainEntity = pivotEntity.findEntity(named: "SubsurfaceTerrainEntity") as? ModelEntity,
               let updatedMesh = VoxelMeshSynthesizer.synthesizeMesh(
                 volume: volume,
                 maxSliceX: maxSliceX,
                 maxSliceZ: maxSliceZ
               )
            {
              let materials = VoxelMeshSynthesizer.makeMaterialPalette()
              terrainEntity.model = ModelComponent(mesh: updatedMesh, materials: materials)
            }
            Task { @MainActor in
              lastBuiltSliceX = maxSliceX
              lastBuiltSliceZ = maxSliceZ
              lastBuiltVoxelCount = volume.voxels.count
            }
          }
        }
        .gesture(orbitDragGesture)
        .simultaneousGesture(zoomMagnifyGesture)
        .simultaneousGesture(targetedSurfaceTapGesture)
        .simultaneousGesture(analyticTapGesture(in: proxy.size))
        .popover(
          isPresented: $isProfilePopoverPresented,
          attachmentAnchor: .point(
            UnitPoint(
              x: max(min((profilePopoverLocation?.x ?? (proxy.size.width * 0.5)) / max(proxy.size.width, 1), 1), 0),
              y: max(min((profilePopoverLocation?.y ?? (proxy.size.height * 0.4)) / max(proxy.size.height, 1), 1), 0)
            )
          ),
          arrowEdge: popoverArrowEdge(for: profilePopoverLocation, in: proxy.size)
        ) {
          CPTPointProfilePopoverView(
            pointTitle: popoverTitle,
            latitudeText: popoverLatitude,
            longitudeText: popoverLongitude
          )
          .presentationCompactAdaptation(.popover)
        }
      }
    }
  }

  private func popoverArrowEdge(for point: CGPoint?, in size: CGSize) -> Edge {
    guard let point else { return .trailing }
    return point.x >= (size.width * 0.45) ? .trailing : .leading
  }

  // MARK: - Gestures (Orbit, Zoom, and Mathematical Analytic Raycast Picking)

  private var orbitDragGesture: some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        if dragStartYaw == nil {
          dragStartYaw = cameraYaw
          dragStartPitch = cameraPitch
        }
        let baseYaw = dragStartYaw ?? cameraYaw
        let basePitch = dragStartPitch ?? cameraPitch
        let deltaYaw = Float(value.translation.width) * 0.0075
        let deltaPitch = Float(value.translation.height) * 0.0065

        cameraYaw = baseYaw + deltaYaw
        cameraPitch = min(max(basePitch + deltaPitch, -0.15), 1.25)
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
        cameraZoom = min(max(updated, 0.55), 2.25)
      }
      .onEnded { _ in
        pinchStartZoom = nil
      }
  }

  /// High-precision RealityKit raycast gesture directly matching user screen touch to 3D surface
  private var targetedSurfaceTapGesture: some Gesture {
    SpatialTapGesture()
      .targetedToAnyEntity()
      .onEnded { value in
        guard let pivot = findPivotEntity(from: value.entity) else { return }
        let hits = value.hitTest(point: value.location, in: .local)
        let exactPoint: SIMD3<Float>
        if let firstHit = hits.first {
          let ptInPivot = pivot.convert(position: firstHit.position, from: nil)
          exactPoint = SIMD3<Float>(ptInPivot.x, 0.0, ptInPivot.z)
        } else {
          let ptInPivot = pivot.convert(position: value.entity.position, from: value.entity.parent)
          exactPoint = SIMD3<Float>(ptInPivot.x, 0.0, ptInPivot.z)
        }

        let xGrid = Int((exactPoint.x + volume.centerX).rounded())
        let zGrid = Int((exactPoint.z + volume.centerZ).rounded())
        let voxel: SoilVoxel?
        if xGrid >= 0, xGrid < volume.nx, zGrid >= 0, zGrid < volume.nz {
          voxel = volume.voxels[GridCoord(x: xGrid, y: volume.ny - 1, z: zGrid)]
        } else {
          voxel = nil
        }

        if let voxel {
          onSelectVoxel(voxel)
        }
        onTapTopSurface?(value.location, exactPoint, voxel)
      }
  }

  private func findPivotEntity(from entity: Entity) -> Entity? {
    var current: Entity? = entity
    while let c = current {
      if c.name == "SubsurfacePivot" { return c }
      current = c.parent
    }
    return nil
  }

  /// Mathematical Screen-to-Grid Raycasting fallback without physics engine.
  /// Unprojects the 2D tap point through the virtual perspective camera into the terrain pivot's
  /// local space and intersects the top plane `Y = 0` (`X_grid = round(P_x + centerX), Z_grid = round(P_z + centerZ)`).
  private func analyticTapGesture(in viewSize: CGSize) -> some Gesture {
    SpatialTapGesture()
      .onEnded { event in
        guard viewSize.width > 1, viewSize.height > 1 else { return }

        // Convert screen tap location to Normalized Device Coordinates [-1, 1]
        let ndcX = Float((event.location.x / viewSize.width) * 2.0 - 1.0)
        let ndcY = Float(1.0 - (event.location.y / viewSize.height) * 2.0)

        let aspect = Float(viewSize.width / max(viewSize.height, 1.0))
        // Default RealityView .virtual camera vertical FOV ~ 60 degrees
        let tanHalfFov = tan(Float.pi / 6.0)

        let rayOriginWorld = SIMD3<Float>(0, 0, 0)
        let rayDirWorld = simd_normalize(
          SIMD3<Float>(
            ndcX * aspect * tanHalfFov,
            ndcY * tanHalfFov,
            -1.0
          )
        )

        // Transform world ray into the local space of `SubsurfacePivot`
        let pivotPos = computeSceneOffset(for: volume)
        let pivotRot = makeOrbitOrientation(yaw: cameraYaw, pitch: cameraPitch)
        let pivotScale = max(computeNormalizedScale(for: volume) * cameraZoom, 1e-4)

        let invRot = pivotRot.inverse
        let localOrigin = invRot.act((rayOriginWorld - pivotPos) / pivotScale)
        let localDir = simd_normalize(invRot.act(rayDirWorld))

        let hitResult = VoxelMeshSynthesizer.pickSurfaceVoxelWithFace(
          rayOrigin: localOrigin,
          rayDirection: localDir,
          volume: volume,
          maxSliceX: maxSliceX,
          maxSliceZ: maxSliceZ
        )

        if let hit = hitResult {
          onSelectVoxel(hit.voxel)
          if hit.isTopSurface {
            onTapTopSurface?(event.location, hit.hitPoint, hit.voxel)
          }
        } else {
          // Detect tap on top surface plane Y = 0 within bounding area
          if abs(localDir.y) > 1e-5 {
            let tTop = -localOrigin.y / localDir.y
            if tTop > 0 {
              let hp = localOrigin + tTop * localDir
              let margin: Float = 4.0
              if abs(hp.x) <= volume.centerX + margin, abs(hp.z) <= volume.centerZ + margin {
                let exactPoint = SIMD3<Float>(hp.x, 0.0, hp.z)
                let xGrid = Int((hp.x + volume.centerX).rounded())
                let zGrid = Int((hp.z + volume.centerZ).rounded())
                let voxel: SoilVoxel?
                if xGrid >= 0, xGrid < volume.nx, zGrid >= 0, zGrid < volume.nz {
                  voxel = volume.voxels[GridCoord(x: xGrid, y: volume.ny - 1, z: zGrid)]
                } else {
                  voxel = nil
                }
                onTapTopSurface?(event.location, exactPoint, voxel)
              }
            }
          }
        }
      }
  }

  // MARK: - Scene Helpers & Lightweight Entities

  private func computeNormalizedScale(for volume: SubsurfaceVoxelVolume) -> Float {
    let maxSpan = max(Float(volume.nx), Float(volume.nz), Float(volume.ny), 16.0)
    return 0.92 / maxSpan
  }

  private func computeSceneOffset(for volume: SubsurfaceVoxelVolume) -> SIMD3<Float> {
    let scale = computeNormalizedScale(for: volume) * cameraZoom
    let verticalHalfOffset = Float(volume.ny) * 0.5 * scale
    // Shift slightly right (+0.16) so the 3D volume sits centered in the canvas to the right of the left sheet
    return SIMD3<Float>(0.16, verticalHalfOffset * 0.68, -1.75)
  }

  private func makeOrbitOrientation(yaw: Float, pitch: Float) -> simd_quatf {
    let pitchQuat = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
    let yawQuat = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
    return simd_mul(pitchQuat, yawQuat)
  }

  /// Creates the visual 3D CPT pipe entity standing upright on the terrain top surface.
  private func makeVoxelSelectionMarker() -> Entity {
    let container = Entity()

    // 3D CPT Sounding Pipe (matching the orange cylinder in the screenshot)
    let pipeMesh = MeshResource.generateCylinder(height: 2.0, radius: 0.42)
    let pipeMaterial = SimpleMaterial(
      color: UIColor(red: 0.90, green: 0.57, blue: 0.25, alpha: 1.0),
      roughness: 0.25,
      isMetallic: false
    )
    let pipeEntity = ModelEntity(mesh: pipeMesh, materials: [pipeMaterial])
    pipeEntity.name = "CPTPipeCylinder"
    // Center at y = 1.0 places cylinder base at y = 0.0 (flush on surface)
    pipeEntity.position = SIMD3<Float>(0, 1.0, 0)
    container.addChild(pipeEntity)

    // Base collar ring at surface level
    let collarMesh = MeshResource.generateCylinder(height: 0.08, radius: 0.52)
    let collarMaterial = SimpleMaterial(
      color: UIColor(white: 0.25, alpha: 1.0),
      roughness: 0.4,
      isMetallic: true
    )
    let collarEntity = ModelEntity(mesh: collarMesh, materials: [collarMaterial])
    collarEntity.position = SIMD3<Float>(0, 0.04, 0)
    container.addChild(collarEntity)

    return container
  }

  /// Creates cylindrical markers on top of the surface representing CPT soundings (matching screenshot).
  private func buildCPTBoreholeMarkers(for volume: SubsurfaceVoxelVolume) -> Entity {
    let container = Entity()
    let pinMesh = MeshResource.generateCylinder(height: 1.8, radius: 0.42)
    let pinMaterial = SimpleMaterial(
      color: UIColor(red: 0.90, green: 0.57, blue: 0.25, alpha: 1.0),
      roughness: 0.28,
      isMetallic: false
    )

    for (idx, pos) in volume.cptSurfacePositions.enumerated() {
      let pin = ModelEntity(mesh: pinMesh, materials: [pinMaterial])
      pin.name = "CPTPin_\(idx)"
      pin.position = SIMD3<Float>(pos.x, 0.9, pos.z)
      pin.components.set(CollisionComponent(shapes: [
        .generateCapsule(height: 1.8, radius: 0.42)
      ]))
      pin.components.set(InputTargetComponent())
      container.addChild(pin)
    }
    return container
  }

  /// Creates the 3D ruler lines and tick marks along the X and Y (Z) base edges of the volume.
  private func buildBaseAxesEntity(for volume: SubsurfaceVoxelVolume) -> Entity {
    let container = Entity()
    let axisColor = UIColor.darkGray
    let axisMaterial = UnlitMaterial(color: axisColor)

    let minX = -0.5 - volume.centerX
    let maxX = Float(volume.nx) - 0.5 - volume.centerX
    let baseY = -Float(volume.ny) - 0.35
    let frontZ = Float(volume.nz) - 0.5 - volume.centerZ + 0.8
    let rightX = maxX + 0.8
    let minZ = -0.5 - volume.centerZ
    let maxZ = Float(volume.nz) - 0.5 - volume.centerZ

    // X Axis main bar along front-bottom edge
    let xLength = max(maxX - minX, 1.0)
    let xBar = ModelEntity(
      mesh: .generateBox(width: xLength, height: 0.14, depth: 0.14),
      materials: [axisMaterial]
    )
    xBar.position = SIMD3<Float>((minX + maxX) * 0.5, baseY, frontZ)
    container.addChild(xBar)

    // X Axis tick marks
    let tickCountX = 5
    for i in 0 ... tickCountX {
      let t = Float(i) / Float(tickCountX)
      let tx = minX + t * xLength
      let tick = ModelEntity(
        mesh: .generateBox(width: 0.14, height: 0.7, depth: 0.14),
        materials: [axisMaterial]
      )
      tick.position = SIMD3<Float>(tx, baseY - 0.3, frontZ)
      container.addChild(tick)

      // 3D numeric label for X axis tick
      let meterVal = Int((t * volume.widthXM).rounded())
      let labelEntity = makeAxisTextEntity(text: "\(meterVal)", color: axisColor)
      labelEntity.position = SIMD3<Float>(tx - 0.4, baseY - 1.5, frontZ)
      container.addChild(labelEntity)
    }

    let xTitleEntity = makeAxisTextEntity(text: "X (m)", color: axisColor)
    xTitleEntity.position = SIMD3<Float>((minX + maxX) * 0.5 - 1.2, baseY - 3.0, frontZ)
    container.addChild(xTitleEntity)

    // Y (Depth/Northing) Axis main bar along right-bottom edge
    let zLength = max(maxZ - minZ, 1.0)
    let zBar = ModelEntity(
      mesh: .generateBox(width: 0.14, height: 0.14, depth: zLength),
      materials: [axisMaterial]
    )
    zBar.position = SIMD3<Float>(rightX, baseY, (minZ + maxZ) * 0.5)
    container.addChild(zBar)

    let tickCountZ = 4
    for i in 0 ... tickCountZ {
      let t = Float(i) / Float(tickCountZ)
      let tz = maxZ - t * zLength
      let tick = ModelEntity(
        mesh: .generateBox(width: 0.6, height: 0.14, depth: 0.14),
        materials: [axisMaterial]
      )
      tick.position = SIMD3<Float>(rightX + 0.3, baseY, tz)
      container.addChild(tick)

      let meterVal = Int((t * volume.lengthZM).rounded())
      if meterVal > 0 {
        let labelEntity = makeAxisTextEntity(text: "\(meterVal)", color: axisColor)
        labelEntity.position = SIMD3<Float>(rightX + 0.8, baseY - 0.8, tz)
        container.addChild(labelEntity)
      }
    }

    let yTitleEntity = makeAxisTextEntity(text: "Y (m)", color: axisColor)
    yTitleEntity.position = SIMD3<Float>(rightX + 2.2, baseY - 1.6, (minZ + maxZ) * 0.5)
    container.addChild(yTitleEntity)

    return container
  }

  private func makeAxisTextEntity(text: String, color: UIColor) -> ModelEntity {
    let mesh = MeshResource.generateText(
      text,
      extrusionDepth: 0.05,
      font: .systemFont(ofSize: 0.95, weight: .semibold),
      containerFrame: .zero,
      alignment: .center,
      lineBreakMode: .byClipping
    )
    let mat = UnlitMaterial(color: color)
    return ModelEntity(mesh: mesh, materials: [mat])
  }
}
