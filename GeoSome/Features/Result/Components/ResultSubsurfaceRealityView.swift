import RealityKit
import simd
import SwiftUI
import UIKit

struct ResultSubsurfaceRealityView: View {
  let volume: SubsurfaceVoxelVolume
  let maxSliceX: Int
  let maxSliceZ: Int
  let selectedVoxel: SoilVoxel?
  @Binding var cameraYaw: Float
  @Binding var cameraPitch: Float
  @Binding var cameraZoom: Float
  var onSelectVoxel: (SoilVoxel?) -> Void

  @State private var dragStartYaw: Float?
  @State private var dragStartPitch: Float?
  @State private var pinchStartZoom: Float?
  @State private var lastBuiltSliceX: Int = -1
  @State private var lastBuiltSliceZ: Int = -1
  @State private var lastBuiltVoxelCount: Int = -1

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

          // 3. Single Ephemeral Highlight Marker (VoxelSelectionMarker)
          let selectionMarker = makeVoxelSelectionMarker()
          selectionMarker.name = "VoxelSelectionMarker"
          selectionMarker.isEnabled = false
          pivotEntity.addChild(selectionMarker)

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

          // Update Single Ephemeral Selection Marker (`VoxelSelectionMarker`)
          if let marker = pivotEntity.findEntity(named: "VoxelSelectionMarker") {
            if let voxel = selectedVoxel,
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
        .simultaneousGesture(analyticTapGesture(in: proxy.size))

        // Floating HUD badge when a discrete 1m² voxel is selected via analytic raycast
        if let voxel = selectedVoxel {
          selectedVoxelBadge(for: voxel)
            .padding(.top, 14)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
      }
    }
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

  /// Mathematical Screen-to-Grid Raycasting without physics engine or `CollisionComponent`.
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

        let hitVoxel = VoxelMeshSynthesizer.pickSurfaceVoxel(
          rayOrigin: localOrigin,
          rayDirection: localDir,
          volume: volume,
          maxSliceX: maxSliceX,
          maxSliceZ: maxSliceZ
        )
        onSelectVoxel(hitVoxel)
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

  /// Creates the single lightweight `VoxelSelectionMarker` entity.
  private func makeVoxelSelectionMarker() -> Entity {
    let container = Entity()

    // Glowing highlight footprint + vertical pin on the selected 1m² voxel
    let footprintMesh = MeshResource.generateBox(width: 1.06, height: 0.22, depth: 1.06, cornerRadius: 0.08)
    let footprintMaterial = UnlitMaterial(color: UIColor.systemBlue.withAlphaComponent(0.85))
    let footprintEntity = ModelEntity(mesh: footprintMesh, materials: [footprintMaterial])
    footprintEntity.position = SIMD3<Float>(0, 0.12, 0)
    container.addChild(footprintEntity)

    let beaconMesh = MeshResource.generateCylinder(height: 2.2, radius: 0.24)
    let beaconMaterial = SimpleMaterial(color: .systemYellow, roughness: 0.2, isMetallic: false)
    let beaconEntity = ModelEntity(mesh: beaconMesh, materials: [beaconMaterial])
    beaconEntity.position = SIMD3<Float>(0, 1.2, 0)
    container.addChild(beaconEntity)

    return container
  }

  /// Creates white cylindrical markers on top of the surface representing CPT soundings (matching screenshot).
  private func buildCPTBoreholeMarkers(for volume: SubsurfaceVoxelVolume) -> Entity {
    let container = Entity()
    let pinMesh = MeshResource.generateCylinder(height: 1.8, radius: 0.42)
    let pinMaterial = SimpleMaterial(color: .white, roughness: 0.25, isMetallic: false)

    for (idx, pos) in volume.cptSurfacePositions.enumerated() {
      let pin = ModelEntity(mesh: pinMesh, materials: [pinMaterial])
      pin.name = "CPTPin_\(idx)"
      pin.position = SIMD3<Float>(pos.x, 0.9, pos.z)
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

  private func selectedVoxelBadge(for voxel: SoilVoxel) -> some View {
    HStack(spacing: 12) {
      Circle()
        .fill(Color(uiColor: voxel.soilClassification.uiColor))
        .frame(width: 14, height: 14)

      VStack(alignment: .leading, spacing: 2) {
        Text(voxel.soilClassification.displayName)
          .font(.caption.weight(.bold))
          .foregroundStyle(Color.primary)

        Text(
          String(
            format: "Grid (%d, %d) • Ic %.2f • Moisture %.0f%% • Bearing %.0f kPa",
            voxel.coord.x,
            voxel.coord.z,
            voxel.robertsonIc,
            voxel.moisturePercent,
            voxel.bearingCapacityKPa
          )
        )
        .font(.caption2)
        .foregroundStyle(Color.secondary)
      }

      Button(action: {
        onSelectVoxel(nil)
      }) {
        Image(systemName: "xmark.circle.fill")
          .font(.subheadline)
          .foregroundStyle(Color.secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Clear voxel selection")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(.regularMaterial, in: Capsule())
    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
  }
}
