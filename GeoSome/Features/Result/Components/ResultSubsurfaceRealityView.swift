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
  var cameraController: SubsurfaceCameraController
  @Binding var cameraYaw: Float
  @Binding var cameraPitch: Float
  @Binding var cameraZoom: Float
  @Binding var isProfilePopoverPresented: Bool
  @Binding var profilePopoverLocation: CGPoint?
  var popoverTitle: String = "CPT Point-01"
  var popoverLatitude: String = "-6.215432"
  var popoverLongitude: String = "106.845321"
  var popoverLayers: [SBTProfileLayerItem] = CPTPointProfilePopoverView.defaultLayers
  var onSelectVoxel: (SoilVoxel?) -> Void
  var onTapTopSurface: ((CGPoint, SIMD3<Float>, SoilVoxel?) -> Void)? = nil

  @State private var lastBuiltSliceX: Int = -1
  @State private var lastBuiltSliceZ: Int = -1
  @State private var lastBuiltVoxelCount: Int = -1
  @State private var lastBuiltVolumeID: UUID?

  init(
    volume: SubsurfaceVoxelVolume,
    maxSliceX: Int,
    maxSliceZ: Int,
    selectedVoxel: SoilVoxel?,
    selectedPipePosition3D: SIMD3<Float>? = nil,
    cameraController: SubsurfaceCameraController? = nil,
    cameraYaw: Binding<Float>,
    cameraPitch: Binding<Float>,
    cameraZoom: Binding<Float>,
    isProfilePopoverPresented: Binding<Bool> = .constant(false),
    profilePopoverLocation: Binding<CGPoint?> = .constant(nil),
    popoverTitle: String = "CPT Point-01",
    popoverLatitude: String = "-6.215432",
    popoverLongitude: String = "106.845321",
    popoverLayers: [SBTProfileLayerItem] = CPTPointProfilePopoverView.defaultLayers,
    onSelectVoxel: @escaping (SoilVoxel?) -> Void,
    onTapTopSurface: ((CGPoint, SIMD3<Float>, SoilVoxel?) -> Void)? = nil
  ) {
    self.volume = volume
    self.maxSliceX = maxSliceX
    self.maxSliceZ = maxSliceZ
    self.selectedVoxel = selectedVoxel
    self.selectedPipePosition3D = selectedPipePosition3D
    self.cameraController = cameraController ?? SubsurfaceCameraController()
    self._cameraYaw = cameraYaw
    self._cameraPitch = cameraPitch
    self._cameraZoom = cameraZoom
    self._isProfilePopoverPresented = isProfilePopoverPresented
    self._profilePopoverLocation = profilePopoverLocation
    self.popoverTitle = popoverTitle
    self.popoverLatitude = popoverLatitude
    self.popoverLongitude = popoverLongitude
    self.popoverLayers = popoverLayers
    self.onSelectVoxel = onSelectVoxel
    self.onTapTopSurface = onTapTopSurface
  }

  var body: some View {
    let _ = cameraController.revision
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        RealityView { content in
          // 1. Set camera mode to .virtual for non-AR 3D geotechnical visualization on iOS
          content.camera = .virtual

          let rootAnchor = Entity()
          rootAnchor.name = "SubsurfaceRootAnchor"

          // 1b. PerspectiveCamera Entity driven by SubsurfaceCameraController in true metric space (1 unit = 1 m)
          let cameraEntity = PerspectiveCamera()
          cameraEntity.name = "SubsurfacePerspectiveCamera"
          cameraEntity.camera.fieldOfViewInDegrees = cameraController.fovDegrees
          cameraEntity.camera.near = cameraController.nearPlane
          cameraEntity.camera.far = cameraController.farPlane
          cameraEntity.transform = cameraController.cameraTransform
          rootAnchor.addChild(cameraEntity)

          // Static metric world container (position = .zero, rotation = identity, scale = 1.0 m)
          let pivotEntity = Entity()
          pivotEntity.name = "SubsurfacePivot"
          pivotEntity.position = .zero
          pivotEntity.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
          pivotEntity.scale = .one
          rootAnchor.addChild(pivotEntity)

          // 2. Single Batched Voxel Mesh Entity in True Metric Space (1 Draw Call)
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

          // 3. Single Ephemeral Highlight Marker (VoxelSelectionMarker: Visual 3D Pipe at exact metric tap)
          let selectionMarker = makeVoxelSelectionMarker()
          selectionMarker.name = "VoxelSelectionMarker"
          selectionMarker.isEnabled = false
          pivotEntity.addChild(selectionMarker)

          // 3b. Top Surface Hit Target in Metric Coordinates
          let hitPlane = ModelEntity()
          hitPlane.name = "TopSurfaceHitPlane"
          let hitBoxWidth = volume.widthXM + 2.0 * volume.cellStepXM
          let hitBoxLength = volume.lengthZM + 2.0 * volume.cellStepZM
          let hitBoxThickness = max(0.2 * volume.cellStepYM, 0.2)
          hitPlane.components.set(CollisionComponent(shapes: [
            .generateBox(size: [hitBoxWidth, hitBoxThickness, hitBoxLength])
          ]))
          hitPlane.components.set(InputTargetComponent())
          hitPlane.position = SIMD3<Float>(0, -hitBoxThickness * 0.5, 0)
          pivotEntity.addChild(hitPlane)

          // 4. CPT Sounding Borehole Pins on Surface (Y = 0) in Metric Space
          let cptContainer = buildCPTBoreholeMarkers(for: volume)
          cptContainer.name = "CPTBoreholeContainer"
          pivotEntity.addChild(cptContainer)

          // 5. Base Ruler Axes (X and Y meter ticks along bottom perimeter) in Metric Space
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

          // 1. Update PerspectiveCamera transform and dynamic near/far clipping planes
          if let cameraEntity = rootAnchor.findEntity(named: "SubsurfacePerspectiveCamera") as? PerspectiveCamera {
            cameraEntity.camera.fieldOfViewInDegrees = cameraController.fovDegrees
            cameraEntity.camera.near = cameraController.nearPlane
            cameraEntity.camera.far = cameraController.farPlane
            cameraEntity.transform = cameraController.cameraTransform
          }

          // Keep model static in true metric units (1 unit = 1 m)
          pivotEntity.position = .zero
          pivotEntity.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
          pivotEntity.scale = .one

          // 2. Update Single Ephemeral Selection Marker at exact tapped metric (x, z) position
          if let marker = pivotEntity.findEntity(named: "VoxelSelectionMarker") {
            let metricUnit = max(min(volume.cellStepXM, volume.cellStepZM), 0.5)
            let adaptiveMarkerScale = min(metricUnit, max(cameraController.distance * 0.025, 0.25))
            marker.scale = SIMD3<Float>(repeating: adaptiveMarkerScale)

            if let pipePos = selectedPipePosition3D {
              marker.isEnabled = true
              marker.position = SIMD3<Float>(pipePos.x, 0.0, pipePos.z)
            } else if let voxel = selectedVoxel,
                      voxel.coord.x <= maxSliceX,
                      voxel.coord.z <= maxSliceZ
            {
              marker.isEnabled = true
              let pos = volume.metricWorldPosition(for: voxel.coord)
              marker.position = SIMD3<Float>(pos.x, 0.0, pos.z)
            } else {
              marker.isEnabled = false
            }
          }

          // 3. Update visibility of CPT borehole pins against active metric slicing thresholds
          if let cptContainer = pivotEntity.findEntity(named: "CPTBoreholeContainer") {
            let maxWorldX = (Float(maxSliceX) - volume.centerX + 0.5) * volume.cellStepXM
            let maxWorldZ = (Float(maxSliceZ) - volume.centerZ + 0.5) * volume.cellStepZM
            for child in cptContainer.children {
              child.isEnabled = (child.position.x <= maxWorldX) && (child.position.z <= maxWorldZ)
            }
          }

          // 4. Rebuild the single batched MeshResource only when slicing thresholds or volume data change
          if lastBuiltSliceX != maxSliceX ||
            lastBuiltSliceZ != maxSliceZ ||
            lastBuiltVoxelCount != volume.voxels.count ||
            lastBuiltVolumeID != volume.id
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

            if lastBuiltVolumeID != volume.id {
              if let oldCPT = pivotEntity.findEntity(named: "CPTBoreholeContainer") {
                oldCPT.removeFromParent()
              }
              let newCPT = buildCPTBoreholeMarkers(for: volume)
              newCPT.name = "CPTBoreholeContainer"
              pivotEntity.addChild(newCPT)

              if let oldAxes = pivotEntity.findEntity(named: "BaseAxesContainer") {
                oldAxes.removeFromParent()
              }
              let newAxes = buildBaseAxesEntity(for: volume)
              newAxes.name = "BaseAxesContainer"
              pivotEntity.addChild(newAxes)

              if let hitPlane = pivotEntity.findEntity(named: "TopSurfaceHitPlane") as? ModelEntity {
                let hitBoxWidth = volume.widthXM + 2.0 * volume.cellStepXM
                let hitBoxLength = volume.lengthZM + 2.0 * volume.cellStepZM
                let hitBoxThickness = max(0.2 * volume.cellStepYM, 0.2)
                hitPlane.components.set(CollisionComponent(shapes: [
                  .generateBox(size: [hitBoxWidth, hitBoxThickness, hitBoxLength])
                ]))
                hitPlane.position = SIMD3<Float>(0, -hitBoxThickness * 0.5, 0)
              }
            }

            Task { @MainActor in
              lastBuiltSliceX = maxSliceX
              lastBuiltSliceZ = maxSliceZ
              lastBuiltVoxelCount = volume.voxels.count
              lastBuiltVolumeID = volume.id
            }
          }
        }
        .overlay {
          SubsurfaceCameraGestureOverlay(
            controller: cameraController,
            onSingleTap: { screenPoint, viewportSize in
              handleMetricTap(at: screenPoint, in: viewportSize)
            }
          )
        }

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

        // Native-looking Popover Overlay (Zero UIKit modal conflict with the left sheet)
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

  // MARK: - Metric Screen-to-Surface Raycast Picking

  /// Unprojects the 2D screen tap through the active `PerspectiveCamera` (`SubsurfaceCameraController`)
  /// into true metric world space (`1 unit = 1 meter`) and resolves the exact `(x, 0, z)` coordinate in meters.
  private func handleMetricTap(at screenPoint: CGPoint, in viewSize: CGSize) {
    guard viewSize.width > 1, viewSize.height > 1 else { return }

    let ray = cameraController.worldRay(from: screenPoint, viewportSize: viewSize)

    let hitResult = VoxelMeshSynthesizer.pickSurfaceVoxelWithFace(
      rayOrigin: ray.origin,
      rayDirection: ray.direction,
      volume: volume,
      maxSliceX: maxSliceX,
      maxSliceZ: maxSliceZ
    )

    if let hit = hitResult {
      onSelectVoxel(hit.voxel)
      onTapTopSurface?(screenPoint, hit.hitPoint, hit.voxel)
    } else if let groundHit = cameraController.intersectGroundPlane(
      screenPoint: screenPoint,
      viewportSize: viewSize
    ) {
      let halfW = volume.widthXM * 0.5 + volume.cellStepXM * 2.0
      let halfL = volume.lengthZM * 0.5 + volume.cellStepZM * 2.0
      if abs(groundHit.x) <= halfW, abs(groundHit.z) <= halfL {
        let (fx, fz) = volume.continuousGridCoordinates(forMetricX: groundHit.x, zM: groundHit.z)
        let xGrid = min(max(Int(fx.rounded()), 0), volume.nx - 1)
        let zGrid = min(max(Int(fz.rounded()), 0), volume.nz - 1)
        let voxel = volume.voxels[GridCoord(x: xGrid, y: volume.ny - 1, z: zGrid)]
        if let voxel {
          onSelectVoxel(voxel)
        }
        onTapTopSurface?(screenPoint, groundHit, voxel)
      }
    }
  }

  // MARK: - Scene Helpers & Metric Entities (1 unit = 1 meter)

  /// Creates the visual 3D CPT pipe entity standing upright on the terrain top surface.
  /// Scaled dynamically in `update` relative to `cellStep` and `cameraController.distance`.
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

  /// Creates cylindrical markers on top of the surface (`Y = 0`) in true metric coordinates (`1 unit = 1 meter`).
  private func buildCPTBoreholeMarkers(for volume: SubsurfaceVoxelVolume) -> Entity {
    let container = Entity()
    let metricUnit = max(min(volume.cellStepXM, volume.cellStepZM), 0.5)
    let pinHeight = 1.8 * metricUnit
    let pinRadius = 0.42 * metricUnit
    let pinMesh = MeshResource.generateCylinder(height: pinHeight, radius: pinRadius)
    let pinMaterial = SimpleMaterial(
      color: UIColor(red: 0.90, green: 0.57, blue: 0.25, alpha: 1.0),
      roughness: 0.28,
      isMetallic: false
    )

    let positions = volume.cptMetricSurfacePositions.isEmpty
      ? volume.cptSurfacePositions.map { SIMD3<Float>($0.x * volume.cellStepXM, 0.0, $0.z * volume.cellStepZM) }
      : volume.cptMetricSurfacePositions

    for (idx, pos) in positions.enumerated() {
      let pin = ModelEntity(mesh: pinMesh, materials: [pinMaterial])
      pin.name = "CPTPin_\(idx)"
      pin.position = SIMD3<Float>(pos.x, pinHeight * 0.5, pos.z)
      pin.components.set(CollisionComponent(shapes: [
        .generateCapsule(height: pinHeight, radius: pinRadius)
      ]))
      pin.components.set(InputTargetComponent())
      container.addChild(pin)
    }
    return container
  }

  /// Creates the 3D ruler lines and tick marks along the X and Y (Z) base edges of the volume in true metric units (`1 unit = 1 meter`).
  private func buildBaseAxesEntity(for volume: SubsurfaceVoxelVolume) -> Entity {
    let container = Entity()
    let axisColor = UIColor.darkGray
    let axisMaterial = UnlitMaterial(color: axisColor)

    let stepXM = volume.cellStepXM
    let stepYM = volume.cellStepYM
    let stepZM = volume.cellStepZM
    let u = max(min(stepXM, stepZM), 0.5)

    let minX = (-0.5 - volume.centerX) * stepXM
    let maxX = (Float(volume.nx) - 0.5 - volume.centerX) * stepXM
    let minZ = (-0.5 - volume.centerZ) * stepZM
    let maxZ = (Float(volume.nz) - 0.5 - volume.centerZ) * stepZM
    let baseY = -Float(volume.ny) * stepYM - 0.35 * u
    let frontZ = maxZ + 0.8 * u
    let rightX = maxX + 0.8 * u

    let barThickness = 0.14 * u

    // X Axis main bar along front-bottom edge
    let xLength = max(maxX - minX, 1.0)
    let xBar = ModelEntity(
      mesh: .generateBox(width: xLength, height: barThickness, depth: barThickness),
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
        mesh: .generateBox(width: barThickness, height: 0.7 * u, depth: barThickness),
        materials: [axisMaterial]
      )
      tick.position = SIMD3<Float>(tx, baseY - 0.3 * u, frontZ)
      container.addChild(tick)

      // 3D numeric label for X axis tick
      let meterVal = Int((t * volume.widthXM).rounded())
      let labelEntity = makeAxisTextEntity(text: "\(meterVal)", color: axisColor, scale: u)
      labelEntity.position = SIMD3<Float>(tx - 0.4 * u, baseY - 1.5 * u, frontZ)
      container.addChild(labelEntity)
    }

    let xTitleEntity = makeAxisTextEntity(text: "X (m)", color: axisColor, scale: u)
    xTitleEntity.position = SIMD3<Float>((minX + maxX) * 0.5 - 1.2 * u, baseY - 3.0 * u, frontZ)
    container.addChild(xTitleEntity)

    // Y (Depth/Northing) Axis main bar along right-bottom edge
    let zLength = max(maxZ - minZ, 1.0)
    let zBar = ModelEntity(
      mesh: .generateBox(width: barThickness, height: barThickness, depth: zLength),
      materials: [axisMaterial]
    )
    zBar.position = SIMD3<Float>(rightX, baseY, (minZ + maxZ) * 0.5)
    container.addChild(zBar)

    let tickCountZ = 4
    for i in 0 ... tickCountZ {
      let t = Float(i) / Float(tickCountZ)
      let tz = maxZ - t * zLength
      let tick = ModelEntity(
        mesh: .generateBox(width: 0.6 * u, height: barThickness, depth: barThickness),
        materials: [axisMaterial]
      )
      tick.position = SIMD3<Float>(rightX + 0.3 * u, baseY, tz)
      container.addChild(tick)

      let meterVal = Int((t * volume.lengthZM).rounded())
      if meterVal > 0 {
        let labelEntity = makeAxisTextEntity(text: "\(meterVal)", color: axisColor, scale: u)
        labelEntity.position = SIMD3<Float>(rightX + 0.8 * u, baseY - 0.8 * u, tz)
        container.addChild(labelEntity)
      }
    }

    let yTitleEntity = makeAxisTextEntity(text: "Y (m)", color: axisColor, scale: u)
    yTitleEntity.position = SIMD3<Float>(rightX + 2.2 * u, baseY - 1.6 * u, (minZ + maxZ) * 0.5)
    container.addChild(yTitleEntity)

    return container
  }

  private func makeAxisTextEntity(text: String, color: UIColor, scale: Float = 1.0) -> ModelEntity {
    let mesh = MeshResource.generateText(
      text,
      extrusionDepth: 0.05,
      font: .systemFont(ofSize: 0.95, weight: .semibold),
      containerFrame: .zero,
      alignment: .center,
      lineBreakMode: .byClipping
    )
    let mat = UnlitMaterial(color: color)
    let entity = ModelEntity(mesh: mesh, materials: [mat])
    entity.scale = SIMD3<Float>(repeating: scale)
    return entity
  }
}

// MARK: - Native-styled Popover Pointer Bubble Shape

struct PopoverBubbleShape: Shape {
  var arrowEdge: Edge = .trailing
  var arrowY: CGFloat
  var cornerRadius: CGFloat = 18
  var arrowWidth: CGFloat = 16
  var arrowHeight: CGFloat = 10

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let minX = arrowEdge == .leading ? rect.minX + arrowHeight : rect.minX
    let maxX = arrowEdge == .trailing ? rect.maxX - arrowHeight : rect.maxX
    let minY = rect.minY
    let maxY = rect.maxY
    let clampedArrowY = min(max(arrowY, minY + cornerRadius + arrowWidth * 0.5), maxY - cornerRadius - arrowWidth * 0.5)

    path.move(to: CGPoint(x: minX + cornerRadius, y: minY))
    path.addLine(to: CGPoint(x: maxX - cornerRadius, y: minY))
    path.addArc(
      center: CGPoint(x: maxX - cornerRadius, y: minY + cornerRadius),
      radius: cornerRadius,
      startAngle: .degrees(-90),
      endAngle: .degrees(0),
      clockwise: false
    )
    if arrowEdge == .trailing {
      path.addLine(to: CGPoint(x: maxX, y: clampedArrowY - arrowWidth * 0.5))
      path.addLine(to: CGPoint(x: rect.maxX, y: clampedArrowY))
      path.addLine(to: CGPoint(x: maxX, y: clampedArrowY + arrowWidth * 0.5))
    }
    path.addLine(to: CGPoint(x: maxX, y: maxY - cornerRadius))
    path.addArc(
      center: CGPoint(x: maxX - cornerRadius, y: maxY - cornerRadius),
      radius: cornerRadius,
      startAngle: .degrees(0),
      endAngle: .degrees(90),
      clockwise: false
    )
    path.addLine(to: CGPoint(x: minX + cornerRadius, y: maxY))
    path.addArc(
      center: CGPoint(x: minX + cornerRadius, y: maxY - cornerRadius),
      radius: cornerRadius,
      startAngle: .degrees(90),
      endAngle: .degrees(180),
      clockwise: false
    )
    if arrowEdge == .leading {
      path.addLine(to: CGPoint(x: minX, y: clampedArrowY + arrowWidth * 0.5))
      path.addLine(to: CGPoint(x: rect.minX, y: clampedArrowY))
      path.addLine(to: CGPoint(x: minX, y: clampedArrowY - arrowWidth * 0.5))
    }
    path.addLine(to: CGPoint(x: minX, y: minY + cornerRadius))
    path.addArc(
      center: CGPoint(x: minX + cornerRadius, y: minY + cornerRadius),
      radius: cornerRadius,
      startAngle: .degrees(180),
      endAngle: .degrees(270),
      clockwise: false
    )
    path.closeSubpath()
    return path
  }
}
