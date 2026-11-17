import Observation
import QuartzCore
import RealityKit
import simd
import SwiftUI
import UIKit

/// Apple Maps-style 3D camera rig controller operating in true metric world space (`1 unit = 1 meter`).
///
/// Instead of scaling or rotating the terrain entity around a normalized pivot, the terrain stays
/// fixed in metric world coordinates (`Y = 0` at the ground surface) while a `PerspectiveCamera`
/// moves according to `(target, distance, yaw, pitch)`.
@MainActor
@Observable
final class SubsurfaceCameraController {
  // MARK: - Default Angles & Constants

  static let defaultYaw: Float = 0.54
  static let defaultPitch: Float = 0.56
  static let defaultFovDegrees: Float = 60.0

  static let absoluteMinPitch: Float = 0.08 // ~4.6° above horizontal ground plane
  static let absoluteMaxPitch: Float = 1.48 // ~84.8° near top-down nadir

  // MARK: - Core Camera State (Metric Space: 1 unit = 1 meter)

  /// Look-at target point on the ground plane (`Y = 0`) in meters.
  var target: SIMD3<Float> = .zero

  /// Distance in meters from `target` to the camera eye position.
  var distance: Float = 45.0

  /// Horizontal azimuth angle in radians around the world `+Y` axis (`0` looks toward `-Z` / North).
  var yaw: Float = SubsurfaceCameraController.defaultYaw

  /// Elevation angle in radians above the horizontal `Y = 0` ground plane (`pi/2` = top-down nadir).
  var pitch: Float = SubsurfaceCameraController.defaultPitch

  /// Vertical field of view of the perspective camera in degrees.
  var fovDegrees: Float = SubsurfaceCameraController.defaultFovDegrees

  // MARK: - Dynamic Metric Limits (Derived from Site Volume & Voxel Size)

  private(set) var minDistance: Float = 2.0
  private(set) var maxDistance: Float = 500.0
  private(set) var minPitch: Float = SubsurfaceCameraController.absoluteMinPitch
  private(set) var maxPitch: Float = SubsurfaceCameraController.absoluteMaxPitch
  private(set) var maxTargetExtentX: Float = 50.0
  private(set) var maxTargetExtentZ: Float = 50.0
  private(set) var siteMaxSpanM: Float = 32.0
  private(set) var defaultDistance: Float = 45.0

  /// Revision counter incremented on any camera change to ensure `RealityView.update` runs.
  private(set) var revision: UInt64 = 0

  // MARK: - Gesture & Inertia State

  private var pinchAnchorGroundPoint: SIMD3<Float>?
  private var pinchStartDistance: Float = 45.0
  private var isInteracting: Bool = false

  /// Linear ground-plane pan velocity in meters/second.
  private var panVelocityMps: SIMD3<Float> = .zero
  /// Logarithmic zoom velocity (`d(ln distance)/dt`) in 1/second.
  private var zoomLogVelocity: Float = 0.0
  /// Angular yaw velocity in radians/second.
  private var yawVelocityRadPerSec: Float = 0.0
  /// Angular pitch velocity in radians/second.
  private var pitchVelocityRadPerSec: Float = 0.0

  /// Exponential damping rate (1/s) for smooth Apple Maps-like deceleration.
  private let dampingRate: Float = 6.5

  init() {}

  // MARK: - Volume Configuration & Reset

  /// Updates distance limits, pan bounds, and clipping parameters from a `SubsurfaceVoxelVolume`.
  func configure(for volume: SubsurfaceVoxelVolume, resetState: Bool = false) {
    let minCellM = max(min(volume.cellStepXM, volume.cellStepZM), 0.25)
    let maxSpanM = max(volume.widthXM, volume.lengthZM, volume.depthYM, 12.0)

    siteMaxSpanM = maxSpanM
    minDistance = max(minCellM * 1.5, 1.5)
    maxDistance = max(maxSpanM * 4.0, 80.0)
    maxTargetExtentX = max(volume.widthXM * 0.75, 10.0)
    maxTargetExtentZ = max(volume.lengthZM * 0.75, 10.0)

    let computedDefaultDist = min(max(maxSpanM * 1.45, minDistance * 2.0), maxDistance)
    defaultDistance = computedDefaultDist

    if resetState {
      stopInertia()
      target = .zero
      distance = computedDefaultDist
      yaw = Self.defaultYaw
      pitch = Self.defaultPitch
    } else {
      target = clampTarget(target)
      distance = min(max(distance, minDistance), maxDistance)
      pitch = min(max(pitch, minPitch), maxPitch)
    }
    revision &+= 1
  }

  /// Resets the camera rig to the default overview framing for the given volume.
  func reset(for volume: SubsurfaceVoxelVolume) {
    configure(for: volume, resetState: true)
  }

  // MARK: - Derived Camera Transform & Clipping Planes

  /// Dynamic near clip plane in meters, scaled with camera distance to prevent close-up clipping and z-fighting.
  var nearPlane: Float {
    max(0.05, min(distance * 0.02, 2.0))
  }

  /// Dynamic far clip plane in meters, ensuring the full site and axes remain inside the view frustum.
  var farPlane: Float {
    max(distance + siteMaxSpanM * 4.5, 500.0)
  }

  /// Camera eye position in metric world space (`E = T + d * (cos(pitch)*sin(yaw), sin(pitch), cos(pitch)*cos(yaw))`).
  var eyePosition: SIMD3<Float> {
    target + sphericalOffset(distance: distance, yaw: yaw, pitch: pitch)
  }

  /// Camera right unit vector (`+X_cam`) in world space, lying purely in the horizontal `Y = 0` plane.
  var rightVector: SIMD3<Float> {
    SIMD3<Float>(cos(yaw), 0.0, -sin(yaw))
  }

  /// Horizontal forward unit vector on the `Y = 0` ground plane aligned with the camera's look azimuth.
  var groundForwardVector: SIMD3<Float> {
    SIMD3<Float>(-sin(yaw), 0.0, -cos(yaw))
  }

  /// Camera 3D forward look unit vector (`-Z_cam`) pointing from `eyePosition` toward `target`.
  var forwardVector: SIMD3<Float> {
    let cp = cos(pitch)
    let sp = sin(pitch)
    let sy = sin(yaw)
    let cy = cos(yaw)
    return simd_normalize(SIMD3<Float>(-cp * sy, -sp, -cp * cy))
  }

  /// Camera 3D up unit vector (`+Y_cam`).
  var upVector: SIMD3<Float> {
    let cp = cos(pitch)
    let sp = sin(pitch)
    let sy = sin(yaw)
    let cy = cos(yaw)
    return simd_normalize(SIMD3<Float>(-sp * sy, cp, -sp * cy))
  }

  /// Camera orientation quaternion `q_cam = q_Y(yaw) * q_X(-pitch)` without gimbal lock or nadir flip.
  var cameraOrientation: simd_quatf {
    let yawQuat = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
    let pitchQuat = simd_quatf(angle: -pitch, axis: SIMD3<Float>(1, 0, 0))
    return simd_mul(yawQuat, pitchQuat)
  }

  /// Complete RealityKit `Transform` for the `PerspectiveCamera` entity.
  var cameraTransform: Transform {
    Transform(
      scale: .one,
      rotation: cameraOrientation,
      translation: eyePosition
    )
  }

  // MARK: - Analytic Ray Unprojection & Ground Plane Intersection

  /// Unprojects a 2D screen point (in points) into a 3D metric world ray `(origin, direction)`.
  func worldRay(
    from screenPoint: CGPoint,
    viewportSize: CGSize
  ) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
    let width = Float(max(viewportSize.width, 1.0))
    let height = Float(max(viewportSize.height, 1.0))

    let ndcX = (2.0 * Float(screenPoint.x) / width) - 1.0
    let ndcY = 1.0 - (2.0 * Float(screenPoint.y) / height)

    let aspect = width / height
    let tanHalfFov = tan((fovDegrees * .pi / 180.0) * 0.5)

    let dirCam = simd_normalize(
      SIMD3<Float>(
        ndcX * aspect * tanHalfFov,
        ndcY * tanHalfFov,
        -1.0
      )
    )

    let dirWorld = simd_normalize(cameraOrientation.act(dirCam))
    return (origin: eyePosition, direction: dirWorld)
  }

  /// Analytically intersects the camera ray through `screenPoint` with the horizontal ground plane `Y = 0`.
  func intersectGroundPlane(
    screenPoint: CGPoint,
    viewportSize: CGSize
  ) -> SIMD3<Float>? {
    let ray = worldRay(from: screenPoint, viewportSize: viewportSize)
    // Require ray to point downward toward Y = 0 (or clamp grazing ray)
    guard ray.direction.y < -1e-4 else { return nil }
    let t = -ray.origin.y / ray.direction.y
    guard t > 0, t.isFinite else { return nil }
    let hitX = ray.origin.x + t * ray.direction.x
    let hitZ = ray.origin.z + t * ray.direction.z
    return SIMD3<Float>(hitX, 0.0, hitZ)
  }

  // MARK: - Gesture Handlers (Pan, Pinch-to-Point, Rotate, Tilt)

  func beginInteraction() {
    isInteracting = true
    stopInertia()
  }

  func endInteraction() {
    isInteracting = false
    pinchAnchorGroundPoint = nil
  }

  /// 1-finger drag: pans `target` across the `Y = 0` ground plane with speed proportional to `distance`.
  func applyGroundPan(
    translationDelta: CGPoint,
    velocityInPoints: CGPoint,
    viewportSize: CGSize
  ) {
    let height = Float(max(viewportSize.height, 1.0))
    let tanHalfFov = tan((fovDegrees * .pi / 180.0) * 0.5)
    let metersPerPoint = (2.0 * distance * tanHalfFov) / height
    let pitchForeshortening = 1.0 / max(sin(pitch), 0.25)

    let dxM = -Float(translationDelta.x) * metersPerPoint
    let dzM = Float(translationDelta.y) * metersPerPoint * pitchForeshortening

    let deltaWorld = rightVector * dxM + groundForwardVector * dzM
    target = clampTarget(target + deltaWorld)

    let vxM = -Float(velocityInPoints.x) * metersPerPoint
    let vzM = Float(velocityInPoints.y) * metersPerPoint * pitchForeshortening
    panVelocityMps = rightVector * vxM + groundForwardVector * vzM
    revision &+= 1
  }

  /// Captures the exact ground point (`Y = 0`) under the user's pinch centroid at the start of a pinch gesture.
  func beginPinch(at pinchLocation: CGPoint, viewportSize: CGSize) {
    beginInteraction()
    pinchStartDistance = distance
    pinchAnchorGroundPoint = intersectGroundPlane(
      screenPoint: pinchLocation,
      viewportSize: viewportSize
    ) ?? target
  }

  /// Updates zoom distance and shifts `target` so `pinchAnchorGroundPoint` remains fixed under `pinchLocation`.
  func updatePinch(
    scale: CGFloat,
    pinchLocation: CGPoint,
    velocity: CGFloat,
    viewportSize: CGSize
  ) {
    let safeScale = max(Float(scale), 1e-3)
    let newDistance = min(max(pinchStartDistance / safeScale, minDistance), maxDistance)
    distance = newDistance

    if let anchor = pinchAnchorGroundPoint {
      // Compute ray direction for current pinch centroid (independent of target and distance)
      let ray = worldRay(from: pinchLocation, viewportSize: viewportSize)
      if ray.direction.y < -1e-3 {
        let eyeOffset = sphericalOffset(distance: newDistance, yaw: yaw, pitch: pitch)
        let lambda = -eyeOffset.y / ray.direction.y
        // Solve: anchor = T_new + eyeOffset + lambda * ray.direction
        let solvedTarget = SIMD3<Float>(
          anchor.x - (eyeOffset.x + lambda * ray.direction.x),
          0.0,
          anchor.z - (eyeOffset.z + lambda * ray.direction.z)
        )
        target = clampTarget(solvedTarget)
      }
    }

    // Store logarithmic zoom velocity for smooth post-pinch inertia
    zoomLogVelocity = Float(-velocity) / safeScale
    revision &+= 1
  }

  func endPinch() {
    pinchAnchorGroundPoint = nil
    endInteraction()
  }

  /// Two-finger rotation gesture: rotates camera azimuth (`yaw`) around the ground anchor or `target`.
  func applyTwoFingerRotation(
    angleDeltaRadians: Float,
    angularVelocity: Float,
    centroid: CGPoint,
    viewportSize: CGSize
  ) {
    let pivotPoint = pinchAnchorGroundPoint
      ?? intersectGroundPlane(screenPoint: centroid, viewportSize: viewportSize)
      ?? target

    // Rotate `target` around `pivotPoint` on Y = 0 if the two-finger centroid is off-center
    let offsetFromPivot = target - pivotPoint
    let c = cos(angleDeltaRadians)
    let s = sin(angleDeltaRadians)
    let rotatedX = offsetFromPivot.x * c + offsetFromPivot.z * s
    let rotatedZ = -offsetFromPivot.x * s + offsetFromPivot.z * c
    target = clampTarget(pivotPoint + SIMD3<Float>(rotatedX, 0.0, rotatedZ))

    yaw += angleDeltaRadians
    yawVelocityRadPerSec = angularVelocity
    revision &+= 1
  }

  /// Two-finger vertical drag gesture: tilts camera elevation (`pitch`) within `[minPitch, maxPitch]`.
  func applyTwoFingerPitch(verticalDeltaPoints: CGFloat, verticalVelocityPoints: CGFloat) {
    let sensitivity: Float = 0.0055
    let deltaPitch = Float(verticalDeltaPoints) * sensitivity
    pitch = min(max(pitch + deltaPitch, minPitch), maxPitch)
    pitchVelocityRadPerSec = Float(verticalVelocityPoints) * sensitivity
    revision &+= 1
  }

  // MARK: - Inertia / Damping Tick

  /// Whether any velocity component is currently above its perceptual stopping threshold.
  var hasActiveInertia: Bool {
    guard !isInteracting else { return false }
    let panSpeed = simd_length(panVelocityMps)
    let panThreshold = max(distance * 0.015, 0.02)
    return panSpeed > panThreshold ||
      abs(zoomLogVelocity) > 0.04 ||
      abs(yawVelocityRadPerSec) > 0.02 ||
      abs(pitchVelocityRadPerSec) > 0.02
  }

  /// Stops all ongoing inertial motion immediately.
  func stopInertia() {
    panVelocityMps = .zero
    zoomLogVelocity = 0.0
    yawVelocityRadPerSec = 0.0
    pitchVelocityRadPerSec = 0.0
  }

  /// Steps inertial damping forward by `dt` seconds. Returns `true` if inertia is still active.
  @discardableResult
  func stepInertia(dt: Float) -> Bool {
    guard hasActiveInertia else {
      stopInertia()
      return false
    }

    let clampedDt = min(max(dt, 1.0 / 240.0), 0.05)
    let decay = exp(-dampingRate * clampedDt)

    // 1. Pan inertia
    if simd_length(panVelocityMps) > 1e-4 {
      target = clampTarget(target + panVelocityMps * clampedDt)
      panVelocityMps *= decay
    }

    // 2. Zoom inertia
    if abs(zoomLogVelocity) > 1e-4 {
      let factor = exp(zoomLogVelocity * clampedDt)
      distance = min(max(distance * factor, minDistance), maxDistance)
      zoomLogVelocity *= decay
    }

    // 3. Yaw inertia
    if abs(yawVelocityRadPerSec) > 1e-4 {
      yaw += yawVelocityRadPerSec * clampedDt
      yawVelocityRadPerSec *= decay
    }

    // 4. Pitch inertia
    if abs(pitchVelocityRadPerSec) > 1e-4 {
      pitch = min(max(pitch + pitchVelocityRadPerSec * clampedDt, minPitch), maxPitch)
      pitchVelocityRadPerSec *= decay
    }

    revision &+= 1

    if !hasActiveInertia {
      stopInertia()
      return false
    }
    return true
  }

  // MARK: - Internal Helpers

  private func sphericalOffset(distance d: Float, yaw y: Float, pitch p: Float) -> SIMD3<Float> {
    let cp = cos(p)
    let sp = sin(p)
    let sy = sin(y)
    let cy = cos(y)
    return SIMD3<Float>(d * cp * sy, d * sp, d * cp * cy)
  }

  private func clampTarget(_ candidate: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(
      min(max(candidate.x, -maxTargetExtentX), maxTargetExtentX),
      0.0,
      min(max(candidate.z, -maxTargetExtentZ), maxTargetExtentZ)
    )
  }
}

// MARK: - UIKit Multi-Touch Gesture & Inertia Overlay

/// Transparent UIKit gesture overlay providing conflict-free Apple Maps-like multi-touch interaction:
/// - 1-finger drag: ground-plane pan
/// - 2-finger pinch: zoom toward the ground anchor point under the fingers
/// - 2-finger rotate: orbit yaw
/// - 2-finger vertical drag: orbit pitch
/// - 1-finger tap: disambiguated surface/voxel inspection tap
struct SubsurfaceCameraGestureOverlay: UIViewRepresentable {
  let controller: SubsurfaceCameraController
  var onSingleTap: (CGPoint, CGSize) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(controller: controller, onSingleTap: onSingleTap)
  }

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.backgroundColor = .clear
    view.isMultipleTouchEnabled = true
    context.coordinator.attach(to: view)
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.controller = controller
    context.coordinator.onSingleTap = onSingleTap
  }

  @MainActor
  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var controller: SubsurfaceCameraController
    var onSingleTap: (CGPoint, CGSize) -> Void

    private weak var hostView: UIView?
    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval?
    private var lastTwoFingerEndTime: CFTimeInterval = 0

    private var oneFingerPanPrevTranslation: CGPoint = .zero
    private var twoFingerPanPrevTranslation: CGPoint = .zero
    private var prevRotationRadians: CGFloat = 0

    private var oneFingerPanRecognizer: UIPanGestureRecognizer!
    private var twoFingerPanRecognizer: UIPanGestureRecognizer!
    private var pinchRecognizer: UIPinchGestureRecognizer!
    private var rotationRecognizer: UIRotationGestureRecognizer!
    private var singleTapRecognizer: UITapGestureRecognizer!

    init(
      controller: SubsurfaceCameraController,
      onSingleTap: @escaping (CGPoint, CGSize) -> Void
    ) {
      self.controller = controller
      self.onSingleTap = onSingleTap
      super.init()
    }

    func attach(to view: UIView) {
      hostView = view

      // 1. One-finger ground pan
      let onePan = UIPanGestureRecognizer(target: self, action: #selector(handleOneFingerPan(_:)))
      onePan.minimumNumberOfTouches = 1
      onePan.maximumNumberOfTouches = 1
      onePan.cancelsTouchesInView = false
      onePan.delegate = self
      view.addGestureRecognizer(onePan)
      oneFingerPanRecognizer = onePan

      // 2. Two-finger vertical drag (pitch tilt)
      let twoPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
      twoPan.minimumNumberOfTouches = 2
      twoPan.maximumNumberOfTouches = 2
      twoPan.cancelsTouchesInView = false
      twoPan.delegate = self
      view.addGestureRecognizer(twoPan)
      twoFingerPanRecognizer = twoPan

      // 3. Two-finger pinch-to-zoom toward anchor
      let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
      pinch.cancelsTouchesInView = false
      pinch.delegate = self
      view.addGestureRecognizer(pinch)
      pinchRecognizer = pinch

      // 4. Two-finger rotation (yaw)
      let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
      rotation.cancelsTouchesInView = false
      rotation.delegate = self
      view.addGestureRecognizer(rotation)
      rotationRecognizer = rotation

      // 5. Single-tap (disambiguated against 1-finger pan)
      let tap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
      tap.numberOfTapsRequired = 1
      tap.numberOfTouchesRequired = 1
      tap.cancelsTouchesInView = false
      tap.require(toFail: onePan)
      tap.delegate = self
      view.addGestureRecognizer(tap)
      singleTapRecognizer = tap
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      let twoFingerSet: Set<ObjectIdentifier> = [
        ObjectIdentifier(twoFingerPanRecognizer),
        ObjectIdentifier(pinchRecognizer),
        ObjectIdentifier(rotationRecognizer)
      ]
      // Allow pinch, 2-finger rotate, and 2-finger tilt to run simultaneously
      return twoFingerSet.contains(ObjectIdentifier(gestureRecognizer)) &&
        twoFingerSet.contains(ObjectIdentifier(otherGestureRecognizer))
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      if gestureRecognizer === oneFingerPanRecognizer {
        // Prevent transient 1-finger pan jump immediately after releasing a 2-finger gesture
        if CACurrentMediaTime() - lastTwoFingerEndTime < 0.12 {
          return false
        }
      }
      return true
    }

    // MARK: - Gesture Actions

    @objc private func handleOneFingerPan(_ recognizer: UIPanGestureRecognizer) {
      guard let view = hostView else { return }
      let size = view.bounds.size

      switch recognizer.state {
      case .began:
        stopDisplayLink()
        controller.beginInteraction()
        oneFingerPanPrevTranslation = .zero

      case .changed:
        let current = recognizer.translation(in: view)
        let delta = CGPoint(
          x: current.x - oneFingerPanPrevTranslation.x,
          y: current.y - oneFingerPanPrevTranslation.y
        )
        oneFingerPanPrevTranslation = current
        let velocity = recognizer.velocity(in: view)
        controller.applyGroundPan(
          translationDelta: delta,
          velocityInPoints: velocity,
          viewportSize: size
        )

      case .ended, .cancelled, .failed:
        controller.endInteraction()
        startDisplayLinkIfNeeded()

      default:
        break
      }
    }

    @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
      guard let view = hostView else { return }

      switch recognizer.state {
      case .began:
        stopDisplayLink()
        controller.beginInteraction()
        twoFingerPanPrevTranslation = .zero

      case .changed:
        guard recognizer.numberOfTouches >= 2 else { return }
        let current = recognizer.translation(in: view)
        let deltaY = current.y - twoFingerPanPrevTranslation.y
        twoFingerPanPrevTranslation = current
        let velocityY = recognizer.velocity(in: view).y
        controller.applyTwoFingerPitch(
          verticalDeltaPoints: deltaY,
          verticalVelocityPoints: velocityY
        )

      case .ended, .cancelled, .failed:
        lastTwoFingerEndTime = CACurrentMediaTime()
        if !isAnyTwoFingerGestureActive {
          controller.endInteraction()
          startDisplayLinkIfNeeded()
        }

      default:
        break
      }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
      guard let view = hostView else { return }
      let size = view.bounds.size
      let location = recognizer.location(in: view)

      switch recognizer.state {
      case .began:
        stopDisplayLink()
        controller.beginPinch(at: location, viewportSize: size)

      case .changed:
        guard recognizer.numberOfTouches >= 2 else { return }
        controller.updatePinch(
          scale: recognizer.scale,
          pinchLocation: location,
          velocity: recognizer.velocity,
          viewportSize: size
        )

      case .ended, .cancelled, .failed:
        lastTwoFingerEndTime = CACurrentMediaTime()
        controller.endPinch()
        if !isAnyTwoFingerGestureActive {
          startDisplayLinkIfNeeded()
        }

      default:
        break
      }
    }

    @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
      guard let view = hostView else { return }
      let size = view.bounds.size
      let centroid = recognizer.location(in: view)

      switch recognizer.state {
      case .began:
        stopDisplayLink()
        controller.beginInteraction()
        prevRotationRadians = 0

      case .changed:
        guard recognizer.numberOfTouches >= 2 else { return }
        let delta = Float(recognizer.rotation - prevRotationRadians)
        prevRotationRadians = recognizer.rotation
        controller.applyTwoFingerRotation(
          angleDeltaRadians: delta,
          angularVelocity: Float(recognizer.velocity),
          centroid: centroid,
          viewportSize: size
        )

      case .ended, .cancelled, .failed:
        lastTwoFingerEndTime = CACurrentMediaTime()
        if !isAnyTwoFingerGestureActive {
          controller.endInteraction()
          startDisplayLinkIfNeeded()
        }

      default:
        break
      }
    }

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .ended, let view = hostView else { return }
      stopDisplayLink()
      controller.stopInertia()
      let point = recognizer.location(in: view)
      onSingleTap(point, view.bounds.size)
    }

    private var isAnyTwoFingerGestureActive: Bool {
      let activeStates: [UIGestureRecognizer.State] = [.began, .changed]
      return activeStates.contains(twoFingerPanRecognizer.state) ||
        activeStates.contains(pinchRecognizer.state) ||
        activeStates.contains(rotationRecognizer.state)
    }

    // MARK: - CADisplayLink Inertia Driver

    private func startDisplayLinkIfNeeded() {
      guard controller.hasActiveInertia, displayLink == nil else { return }
      lastFrameTimestamp = nil
      let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
      link.add(to: .main, forMode: .common)
      displayLink = link
    }

    private func stopDisplayLink() {
      displayLink?.invalidate()
      displayLink = nil
      lastFrameTimestamp = nil
    }

    @objc private func handleDisplayLink(_ link: CADisplayLink) {
      let now = link.timestamp
      let dt: Float
      if let prev = lastFrameTimestamp {
        dt = Float(now - prev)
      } else {
        dt = 1.0 / 60.0
      }
      lastFrameTimestamp = now

      if !controller.stepInertia(dt: dt) {
        stopDisplayLink()
      }
    }

    deinit {
      displayLink?.invalidate()
    }
  }
}
