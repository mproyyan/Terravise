import CoreLocation
import MapKit
import QuartzCore
import simd
import SwiftUI
import UIKit

// MARK: - SubsurfaceCoordinateConverter (Double-Precision Local Meters <-> Lat/Lon)

/// Pure `Double`-precision coordinate converter between the 3D model's local metric space (`1 unit = 1 m`,
/// centered at the polygon bounding box midpoint with `+X` = East, `-Z` = North, `+Z` = South)
/// and WGS84 geographic coordinates (`CLLocationCoordinate2D`).
struct SubsurfaceCoordinateConverter: Sendable, Equatable {
  let minLatitude: Double
  let maxLatitude: Double
  let minLongitude: Double
  let maxLongitude: Double
  let widthXM: Double
  let lengthZM: Double
  let cellStepXM: Double
  let cellStepZM: Double
  let nx: Int
  let nz: Int

  init(volume: SubsurfaceVoxelVolume) {
    self.minLatitude = volume.minLatitude
    self.maxLatitude = volume.maxLatitude
    self.minLongitude = volume.minLongitude
    self.maxLongitude = volume.maxLongitude
    self.widthXM = Double(max(volume.widthXM, 1e-3))
    self.lengthZM = Double(max(volume.lengthZM, 1e-3))
    self.cellStepXM = Double(max(volume.cellStepXM, 1e-3))
    self.cellStepZM = Double(max(volume.cellStepZM, 1e-3))
    self.nx = max(volume.nx, 2)
    self.nz = max(volume.nz, 2)
  }

  /// Geographic midpoint of the site bounding box, corresponding to local metric origin `(0, 0, 0)`.
  var centerCoordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(
      latitude: (minLatitude + maxLatitude) * 0.5,
      longitude: (minLongitude + maxLongitude) * 0.5
    )
  }

  /// Maximum horizontal span of the site in meters (`max(widthXM, lengthZM)`).
  var siteSpanM: Double {
    max(widthXM, lengthZM, 12.0)
  }

  /// Minimum allowed MapCamera distance (meters) on the minimap when zoomed in close.
  var minMapCameraDistanceM: Double {
    let minCell = max(min(cellStepXM, cellStepZM), 0.5)
    return max(minCell * 3.0, 6.0)
  }

  /// Maximum allowed MapCamera distance (meters) on the minimap so zoom-out never goes too far ("ga bablas").
  var maxMapCameraDistanceM: Double {
    max(siteSpanM * 2.35, 36.0)
  }

  /// Forward conversion (Local Meters -> Geographic Lat/Lon) in `Double` precision:
  /// - `+xM` is East (`u = xM / widthXM + 0.5`)
  /// - `+zM` is South, `-zM` is North (`v = zM / lengthZM + 0.5`)
  func coordinate(forMetricX xM: Double, zM: Double) -> CLLocationCoordinate2D {
    let u = (xM / widthXM) + 0.5
    let v = (zM / lengthZM) + 0.5
    let lon = minLongitude + u * (maxLongitude - minLongitude)
    let lat = maxLatitude - v * (maxLatitude - minLatitude)
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }

  /// Exact algebraic inverse (Geographic Lat/Lon -> Local Meters `(xM, zM)`) in `Double` precision.
  func metricPoint(for coordinate: CLLocationCoordinate2D) -> SIMD2<Double> {
    let lonSpan = max(maxLongitude - minLongitude, 1e-12)
    let latSpan = max(maxLatitude - minLatitude, 1e-12)
    let u = (coordinate.longitude - minLongitude) / lonSpan
    let v = (maxLatitude - coordinate.latitude) / latSpan
    let xM = (u - 0.5) * widthXM
    let zM = (v - 0.5) * lengthZM
    return SIMD2<Double>(xM, zM)
  }

  /// Converts a 3D camera state `(target, distance, yaw)` into a flat (`pitch = 0`) `MapCamera`
  /// with strict zoom-in and zoom-out distance clamping.
  /// Note: 3D `pitch` (tilt) is intentionally ignored so tilting in 3D does not alter the minimap.
  func mapCamera(
    target: SIMD3<Float>,
    distance: Float,
    yaw: Float
  ) -> MapCamera {
    let centerCoord = coordinate(forMetricX: Double(target.x), zM: Double(target.z))
    // Scale 3D camera distance slightly so default 3D overview frames the whole polygon on the minimap,
    // while strictly clamping between [minMapCameraDistanceM, maxMapCameraDistanceM].
    let scaledDist = Double(distance) * 1.35
    let clampedDist = min(max(scaledDist, minMapCameraDistanceM), maxMapCameraDistanceM)
    let headingDeg = Self.compassHeadingDegrees(fromYawRadians: yaw)

    return MapCamera(
      centerCoordinate: centerCoord,
      distance: clampedDist,
      heading: headingDeg,
      pitch: 0.0
    )
  }

  /// Converts 3D `yaw` (radians around `+Y`, where `0` looks North along `-Z`) into MapKit clockwise compass heading `[0, 360)`.
  static func compassHeadingDegrees(fromYawRadians yaw: Float) -> Double {
    let rawDeg = (-Double(yaw) * 180.0 / .pi).truncatingRemainder(dividingBy: 360.0)
    return rawDeg < 0 ? (rawDeg + 360.0) : rawDeg
  }
}

// MARK: - Throttled Camera State Snapshot (Ignores 3D Pitch / Tilt)

private struct MinimapCameraStateSnapshot: Equatable {
  var targetX: Float
  var targetZ: Float
  var distance: Float
  var yaw: Float
}

// MARK: - SubsurfaceMinimapView

/// Direct zoom, pan, and rotate MapKit minimap synchronized two-way with `SubsurfaceCameraController`.
///
/// - **Zoom & Rotate Only (Tilt-Invariant)**: Syncs directly with `cameraController.target`, `distance`, and `yaw`
///   via a flat top-down `MapCamera` (`pitch: 0`). Tilting (`pitch`) in 3D does not change the minimap.
/// - **Strict Zoom-Out Cap**: Clamps map camera distance and 3D zoom-out from the minimap to `converter.maxMapCameraDistanceM`
///   so the minimap never zooms out past the site neighborhood.
/// - **Two-Way Direct Map Gestures**: 1-finger drag pans the target, 2-finger pinch zooms in/out, 2-finger twist rotates
///   the heading, and double-tap (or the reset button) fits the whole site.
struct SubsurfaceMinimapView: View {
  let volume: SubsurfaceVoxelVolume
  let boundaryCoordinates: [CLLocationCoordinate2D]
  let cptPoints: [CPTPointEntry]
  var cameraController: SubsurfaceCameraController
  var virtualCPTPosition3D: SIMD3<Float>?
  @Binding var isInteracting: Bool
  var onTapCreateVirtualCPT: (() -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var mapCameraPosition: MapCameraPosition
  @State private var syncedSnapshot: MinimapCameraStateSnapshot
  @State private var lastSyncTime: CFTimeInterval = 0
  @State private var trailingSyncTask: Task<Void, Never>?
  @State private var isSatelliteStyle: Bool = false

  private let converter: SubsurfaceCoordinateConverter
  private let minimapHeight: CGFloat = 188.0

  init(
    volume: SubsurfaceVoxelVolume,
    boundaryCoordinates: [CLLocationCoordinate2D],
    cptPoints: [CPTPointEntry] = [],
    cameraController: SubsurfaceCameraController,
    virtualCPTPosition3D: SIMD3<Float>? = nil,
    isInteracting: Binding<Bool> = .constant(false),
    onTapCreateVirtualCPT: (() -> Void)? = nil
  ) {
    self.volume = volume
    self.boundaryCoordinates = boundaryCoordinates
    self.cptPoints = cptPoints
    self.cameraController = cameraController
    self.virtualCPTPosition3D = virtualCPTPosition3D
    self._isInteracting = isInteracting
    self.onTapCreateVirtualCPT = onTapCreateVirtualCPT

    let conv = SubsurfaceCoordinateConverter(volume: volume)
    self.converter = conv

    let initialSnap = MinimapCameraStateSnapshot(
      targetX: cameraController.target.x,
      targetZ: cameraController.target.z,
      distance: cameraController.distance,
      yaw: cameraController.yaw
    )
    self._syncedSnapshot = State(initialValue: initialSnap)
    self._mapCameraPosition = State(
      initialValue: .camera(
        conv.mapCamera(
          target: cameraController.target,
          distance: cameraController.distance,
          yaw: cameraController.yaw
        )
      )
    )
  }

  /// Resolved CPT borehole coordinates to display on the minimap.
  private var resolvedCPTCoordinates: [CLLocationCoordinate2D] {
    if !cptPoints.isEmpty {
      return cptPoints.map(\.coordinate)
    }
    return volume.cptMetricSurfacePositions.map { pos in
      converter.coordinate(forMetricX: Double(pos.x), zM: Double(pos.z))
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Header Row
      HStack(spacing: 8) {
        Text("Site Minimap")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Color.primary)
          .accessibilityAddTraits(.isHeader)

        Spacer()

        // Compass / Snap-North Button
        Button {
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            cameraController.setYawFromMinimap(0.0)
            syncMapCameraImmediately()
          }
          AccessibilityCaptionCenter.shared.announce("Camera heading aligned to North.")
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "location.north.fill")
              .font(.caption.weight(.bold))
              .rotationEffect(.degrees(-headingDegreesDouble))
            Text(formattedHeadingText)
              .font(.system(size: 11, weight: .semibold, design: .monospaced))
          }
          .foregroundStyle(Color.primary)
          .padding(.horizontal, 8)
          .frame(height: 26)
          .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(Color(.tertiarySystemFill))
          )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compass Heading \(formattedHeadingText)")
        .accessibilityHint("Double-tap to align heading to North")

        // Map Style Toggle Button (Standard <-> Satellite)
        Button {
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            isSatelliteStyle.toggle()
          }
          AccessibilityCaptionCenter.shared.announce(
            "Minimap style changed to \(isSatelliteStyle ? "Satellite" : "Standard")."
          )
        } label: {
          Image(systemName: isSatelliteStyle ? "globe.americas.fill" : "map")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSatelliteStyle ? Color.accentColor : Color.primary)
            .frame(width: 26, height: 26)
            .background(
              RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSatelliteStyle ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map Style: \(isSatelliteStyle ? "Satellite" : "Standard")")
        .accessibilityHint("Double-tap to switch between Standard and Satellite map styles")
      }

      // Interactive Zoom & Rotate Minimap Container
      ZStack {
        Map(position: $mapCameraPosition, interactionModes: []) {
          // 1. Drawn Site Boundary Polygon (reusing BoundaryMapContentLayer styling)
          if boundaryCoordinates.count == 2 {
            MapPolyline(coordinates: boundaryCoordinates)
              .stroke(
                isSatelliteStyle ? Color.cyan : Color.blue,
                style: StrokeStyle(
                  lineWidth: contrast == .increased ? 3.5 : 2.5,
                  lineCap: .round,
                  lineJoin: .round,
                  dash: [6, 4]
                )
              )
          } else if boundaryCoordinates.count >= 3 {
            MapPolygon(coordinates: boundaryCoordinates)
              .foregroundStyle(
                (isSatelliteStyle ? Color.cyan : Color.blue)
                  .opacity(contrast == .increased ? 0.35 : (isSatelliteStyle ? 0.28 : 0.22))
              )
              .stroke(
                isSatelliteStyle ? Color.cyan : Color.blue,
                lineWidth: contrast == .increased ? 3.0 : 2.2
              )
          }

          // 2. Actual CPT Borehole Locations (Orange/Amber markers matching 3D Actual CPT pipes)
          ForEach(Array(resolvedCPTCoordinates.enumerated()), id: \.offset) { index, coord in
            Annotation("CPT \(index + 1)", coordinate: coord, anchor: .center) {
              ZStack {
                Circle()
                  .fill(Color(red: 0.92, green: 0.55, blue: 0.20))
                  .frame(width: 11, height: 11)
                Circle()
                  .fill(Color(white: 0.18))
                  .frame(width: 4, height: 4)
              }
              .overlay(
                Circle()
                  .stroke(Color.white, lineWidth: 1.8)
              )
              .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
            }
            .annotationTitles(.hidden)
          }

          // 3. Active Virtual CPT Marker on Minimap (Cyan/Blue diamond-ring pin matching 3D Virtual CPT pipe)
          if let vPos = virtualCPTPosition3D {
            let vCoord = converter.coordinate(forMetricX: Double(vPos.x), zM: Double(vPos.z))
            Annotation("Virtual CPT", coordinate: vCoord, anchor: .center) {
              ZStack {
                Circle()
                  .fill(Color(red: 0.08, green: 0.60, blue: 0.96))
                  .frame(width: 12, height: 12)
                Circle()
                  .fill(Color.white)
                  .frame(width: 4.5, height: 4.5)
              }
              .overlay(
                Circle()
                  .stroke(Color.white, lineWidth: 2.0)
              )
              .shadow(color: .black.opacity(0.32), radius: 3, y: 1)
            }
            .annotationTitles(.hidden)
          }
        }
        .mapStyle(
          isSatelliteStyle
            ? .imagery(elevation: .flat)
            : .standard(elevation: .flat, pointsOfInterest: .excludingAll)
        )
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)

        // Distinct Center Target Crosshair Reticle (Titik Tengah Minimap)
        minimapCenterReticle
          .allowsHitTesting(false)

        // Direct Multi-Touch Gesture Overlay (1-finger pan, 2-finger pinch zoom with cap, 2-finger rotate, single-tap Virtual CPT, double-tap fit)
        MinimapDirectGestureOverlay(
          cameraController: cameraController,
          converter: converter,
          volume: volume,
          isInteracting: $isInteracting,
          onCameraChanged: {
            syncMapCameraImmediately()
          },
          onSingleTap: {
            onTapCreateVirtualCPT?()
          }
        )
      }
      .frame(height: minimapHeight)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(
            Color.primary.opacity(contrast == .increased ? 0.45 : 0.14),
            lineWidth: contrast == .increased ? 2.0 : 1.0
          )
      )
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Site Minimap")
      .accessibilityValue(accessibilitySummaryText)
      .accessibilityHint("Tap to create a Virtual CPT at the center point, drag to pan, pinch to zoom, rotate with two fingers, or double-tap to fit the whole site.")
      .accessibilityAdjustableAction { direction in
        let step: Float = .pi / 12.0
        switch direction {
        case .increment:
          cameraController.setYawFromMinimap(cameraController.yaw + step)
          syncMapCameraImmediately()
        case .decrement:
          cameraController.setYawFromMinimap(cameraController.yaw - step)
          syncMapCameraImmediately()
        @unknown default:
          break
        }
      }

      // Compact Legend Row: Actual CPT vs Virtual CPT vs Center Reticle
      HStack(spacing: 12) {
        HStack(spacing: 5) {
          ZStack {
            Circle()
              .fill(Color(red: 0.92, green: 0.55, blue: 0.20))
              .frame(width: 8, height: 8)
            Circle()
              .fill(Color(white: 0.18))
              .frame(width: 3, height: 3)
          }
          Text("Actual CPT")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.secondary)
        }

        HStack(spacing: 5) {
          ZStack {
            Circle()
              .fill(Color(red: 0.08, green: 0.60, blue: 0.96))
              .frame(width: 8, height: 8)
            Circle()
              .fill(Color.white)
              .frame(width: 3, height: 3)
          }
          Text("Virtual CPT")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.secondary)
        }

        Spacer(minLength: 4)

        Text("Tap map to create Virtual CPT")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(Color.blue)
      }
    }
    .onChange(of: volume.id) { _, _ in
      syncMapCameraImmediately()
    }
    .onChange(of: cameraController.revision) { _, _ in
      handle3DCameraUpdate()
    }
    .onDisappear {
      trailingSyncTask?.cancel()
      isInteracting = false
    }
  }

  // MARK: - 3D <-> Minimap Camera Synchronization (Tilt-Invariant, ~30 Hz Throttled)

  private func handle3DCameraUpdate() {
    let candidate = MinimapCameraStateSnapshot(
      targetX: cameraController.target.x,
      targetZ: cameraController.target.z,
      distance: cameraController.distance,
      yaw: cameraController.yaw
    )

    // Ignore updates when only 3D pitch (tilt) changed!
    guard hasMeaningfulChange(from: syncedSnapshot, to: candidate) else { return }

    let now = CACurrentMediaTime()
    let minInterval: CFTimeInterval = 1.0 / 30.0

    if now - lastSyncTime >= minInterval {
      lastSyncTime = now
      trailingSyncTask?.cancel()
      applySnapshotToMapCamera(candidate)
    } else {
      trailingSyncTask?.cancel()
      let remaining = minInterval - (now - lastSyncTime)
      trailingSyncTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(Int((remaining * 1000.0).rounded(.up))))
        guard !Task.isCancelled else { return }
        let latest = MinimapCameraStateSnapshot(
          targetX: cameraController.target.x,
          targetZ: cameraController.target.z,
          distance: cameraController.distance,
          yaw: cameraController.yaw
        )
        lastSyncTime = CACurrentMediaTime()
        applySnapshotToMapCamera(latest)
      }
    }
  }

  private func syncMapCameraImmediately() {
    trailingSyncTask?.cancel()
    lastSyncTime = CACurrentMediaTime()
    let latest = MinimapCameraStateSnapshot(
      targetX: cameraController.target.x,
      targetZ: cameraController.target.z,
      distance: cameraController.distance,
      yaw: cameraController.yaw
    )
    applySnapshotToMapCamera(latest)
  }

  private func applySnapshotToMapCamera(_ snapshot: MinimapCameraStateSnapshot) {
    syncedSnapshot = snapshot
    mapCameraPosition = .camera(
      converter.mapCamera(
        target: SIMD3<Float>(snapshot.targetX, 0.0, snapshot.targetZ),
        distance: snapshot.distance,
        yaw: snapshot.yaw
      )
    )
  }

  private func hasMeaningfulChange(
    from old: MinimapCameraStateSnapshot,
    to new: MinimapCameraStateSnapshot
  ) -> Bool {
    abs(old.targetX - new.targetX) > 1e-3 ||
      abs(old.targetZ - new.targetZ) > 1e-3 ||
      abs(old.distance - new.distance) > 1e-2 ||
      abs(old.yaw - new.yaw) > 1e-3
  }

  // MARK: - Compass & Accessibility Formatting

  private var headingDegreesDouble: Double {
    SubsurfaceCoordinateConverter.compassHeadingDegrees(fromYawRadians: syncedSnapshot.yaw)
  }

  private var compassHeadingDegrees: Int {
    Int(headingDegreesDouble.rounded()) % 360
  }

  private var cardinalDirectionString: String {
    let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    let index = Int(((Double(compassHeadingDegrees) + 22.5) / 45.0).rounded(.down)) % 8
    return directions[index]
  }

  private var formattedHeadingText: String {
    String(format: "%03d° %@", compassHeadingDegrees, cardinalDirectionString)
  }

  private var accessibilitySummaryText: String {
    let tx = Int(syncedSnapshot.targetX.rounded())
    let tz = Int((-syncedSnapshot.targetZ).rounded())
    let ewText = tx >= 0 ? "\(tx) meters East" : "\(-tx) meters West"
    let nsText = tz >= 0 ? "\(tz) meters North" : "\(-tz) meters South"
    return "Target \(ewText), \(nsText) of site center. Heading \(compassHeadingDegrees) degrees \(cardinalDirectionString)."
  }

  private var isCenterInsideActiveBoundary: Bool {
    volume.isMetricPointInsideActiveArea(
      xM: syncedSnapshot.targetX,
      zM: syncedSnapshot.targetZ
    )
  }

  /// Target crosshair reticle at the center of the minimap, visually distinct from the round Actual CPT pins.
  /// Turns dimmed gray when the minimap center lies outside the drawn boundary polygon.
  private var minimapCenterReticle: some View {
    let activeColor = isCenterInsideActiveBoundary
      ? Color(red: 0.08, green: 0.60, blue: 0.96)
      : Color.secondary

    return ZStack {
      // Outer Ring
      Circle()
        .stroke(Color.white, lineWidth: 3.0)
        .frame(width: 18, height: 18)
      Circle()
        .stroke(Color(white: 0.15), lineWidth: 1.5)
        .frame(width: 18, height: 18)

      // 4 Crosshair Ticks (North, South, East, West)
      Rectangle()
        .fill(Color(white: 0.15))
        .frame(width: 1.6, height: 6)
        .offset(y: -11)
      Rectangle()
        .fill(Color(white: 0.15))
        .frame(width: 1.6, height: 6)
        .offset(y: 11)
      Rectangle()
        .fill(Color(white: 0.15))
        .frame(width: 6, height: 1.6)
        .offset(x: -11)
      Rectangle()
        .fill(Color(white: 0.15))
        .frame(width: 6, height: 1.6)
        .offset(x: 11)

      // Center precision dot
      Circle()
        .fill(activeColor)
        .frame(width: 4.5, height: 4.5)
        .overlay(
          Circle()
            .stroke(Color.white, lineWidth: 1.0)
        )
    }
    .opacity(isCenterInsideActiveBoundary ? 1.0 : 0.55)
    .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
  }
}

// MARK: - UIKit Multi-Touch Overlay for Direct Minimap Pan, Pinch-Zoom (Capped), Rotate, & Single-Tap Virtual CPT

private struct MinimapDirectGestureOverlay: UIViewRepresentable {
  let cameraController: SubsurfaceCameraController
  let converter: SubsurfaceCoordinateConverter
  let volume: SubsurfaceVoxelVolume
  @Binding var isInteracting: Bool
  var onCameraChanged: () -> Void
  var onSingleTap: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      cameraController: cameraController,
      converter: converter,
      volume: volume,
      isInteracting: $isInteracting,
      onCameraChanged: onCameraChanged,
      onSingleTap: onSingleTap
    )
  }

  func makeUIView(context: Context) -> TouchInterceptingView {
    let view = TouchInterceptingView(frame: .zero)
    view.backgroundColor = .clear
    view.isMultipleTouchEnabled = true
    view.onTouchStateChange = { touching in
      context.coordinator.setInteracting(touching)
    }
    context.coordinator.attach(to: view)
    return view
  }

  func updateUIView(_ uiView: TouchInterceptingView, context: Context) {
    context.coordinator.cameraController = cameraController
    context.coordinator.converter = converter
    context.coordinator.volume = volume
    context.coordinator.isInteracting = $isInteracting
    context.coordinator.onCameraChanged = onCameraChanged
    context.coordinator.onSingleTap = onSingleTap
  }

  /// Custom `UIView` that immediately notifies the parent `ScrollView` on `touchesBegan`
  /// so vertical drags and 2-finger gestures on the minimap never scroll the enclosing card.
  final class TouchInterceptingView: UIView {
    var onTouchStateChange: ((Bool) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesBegan(touches, with: event)
      onTouchStateChange?(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesEnded(touches, with: event)
      if (event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.isEmpty) ?? true {
        onTouchStateChange?(false)
      }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesCancelled(touches, with: event)
      onTouchStateChange?(false)
    }
  }

  @MainActor
  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var cameraController: SubsurfaceCameraController
    var converter: SubsurfaceCoordinateConverter
    var volume: SubsurfaceVoxelVolume
    var isInteracting: Binding<Bool>
    var onCameraChanged: () -> Void
    var onSingleTap: () -> Void

    private weak var hostView: UIView?
    private var prevPanTranslation: CGPoint = .zero
    private var pinchStartDistance: Float = 45.0
    private var prevRotationRadians: CGFloat = 0

    private var panRecognizer: UIPanGestureRecognizer!
    private var pinchRecognizer: UIPinchGestureRecognizer!
    private var rotationRecognizer: UIRotationGestureRecognizer!
    private var singleTapRecognizer: UITapGestureRecognizer!
    private var doubleTapRecognizer: UITapGestureRecognizer!

    init(
      cameraController: SubsurfaceCameraController,
      converter: SubsurfaceCoordinateConverter,
      volume: SubsurfaceVoxelVolume,
      isInteracting: Binding<Bool>,
      onCameraChanged: @escaping () -> Void,
      onSingleTap: @escaping () -> Void
    ) {
      self.cameraController = cameraController
      self.converter = converter
      self.volume = volume
      self.isInteracting = isInteracting
      self.onCameraChanged = onCameraChanged
      self.onSingleTap = onSingleTap
      super.init()
    }

    func setInteracting(_ active: Bool) {
      if isInteracting.wrappedValue != active {
        isInteracting.wrappedValue = active
      }
    }

    func attach(to view: UIView) {
      hostView = view

      let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
      pan.minimumNumberOfTouches = 1
      pan.maximumNumberOfTouches = 2
      pan.cancelsTouchesInView = false
      pan.delegate = self
      view.addGestureRecognizer(pan)
      panRecognizer = pan

      let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
      pinch.cancelsTouchesInView = false
      pinch.delegate = self
      view.addGestureRecognizer(pinch)
      pinchRecognizer = pinch

      let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
      rotation.cancelsTouchesInView = false
      rotation.delegate = self
      view.addGestureRecognizer(rotation)
      rotationRecognizer = rotation

      let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
      doubleTap.numberOfTapsRequired = 2
      doubleTap.numberOfTouchesRequired = 1
      doubleTap.cancelsTouchesInView = false
      doubleTap.delegate = self
      view.addGestureRecognizer(doubleTap)
      doubleTapRecognizer = doubleTap

      let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
      singleTap.numberOfTapsRequired = 1
      singleTap.numberOfTouchesRequired = 1
      singleTap.cancelsTouchesInView = false
      singleTap.require(toFail: pan)
      singleTap.require(toFail: doubleTap)
      singleTap.delegate = self
      view.addGestureRecognizer(singleTap)
      singleTapRecognizer = singleTap
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      let continuousSet: Set<ObjectIdentifier> = [
        ObjectIdentifier(panRecognizer),
        ObjectIdentifier(pinchRecognizer),
        ObjectIdentifier(rotationRecognizer)
      ]
      // Allow simultaneous pan, pinch-zoom, and two-finger rotate while keeping single/double tap disambiguated
      return continuousSet.contains(ObjectIdentifier(gestureRecognizer)) &&
        continuousSet.contains(ObjectIdentifier(otherGestureRecognizer))
    }

    ///Maximum allowed 3D camera distance when zooming out from the minimap so the map never zooms out too far.
    private var maxAllowed3DDistanceFromMinimap: Float {
      let fromCap = Float(converter.maxMapCameraDistanceM / 1.35)
      return max(min(cameraController.maxDistance, fromCap), cameraController.minDistance * 2.0)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
      guard let view = hostView else { return }
      let width = max(Float(view.bounds.width), 1.0)

      switch recognizer.state {
      case .began:
        setInteracting(true)
        cameraController.stopInertia()
        prevPanTranslation = .zero

      case .changed:
        let current = recognizer.translation(in: view)
        let dxPt = Float(current.x - prevPanTranslation.x)
        let dyPt = Float(current.y - prevPanTranslation.y)
        prevPanTranslation = current

        let mapCamDist = Float(
          min(
            max(Double(cameraController.distance) * 1.35, converter.minMapCameraDistanceM),
            converter.maxMapCameraDistanceM
          )
        )
        let metersPerPt = (mapCamDist * 0.65) / width

        // On the rotated minimap, +X_screen is cameraController.rightVector and -Y_screen is cameraController.groundForwardVector
        let deltaWorld = cameraController.rightVector * (-dxPt * metersPerPt) +
          cameraController.groundForwardVector * (dyPt * metersPerPt)

        cameraController.setTargetFromMinimap(cameraController.target + deltaWorld)
        onCameraChanged()

      case .ended, .cancelled, .failed:
        setInteracting(false)

      default:
        break
      }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
      switch recognizer.state {
      case .began:
        setInteracting(true)
        cameraController.stopInertia()
        pinchStartDistance = min(cameraController.distance, maxAllowed3DDistanceFromMinimap)

      case .changed:
        let scale = max(Float(recognizer.scale), 1e-3)
        let rawDist = pinchStartDistance / scale
        let clampedDist = min(
          max(rawDist, cameraController.minDistance),
          maxAllowed3DDistanceFromMinimap
        )
        cameraController.setDistanceFromMinimap(clampedDist)
        onCameraChanged()

      case .ended, .cancelled, .failed:
        setInteracting(false)

      default:
        break
      }
    }

    @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
      switch recognizer.state {
      case .began:
        setInteracting(true)
        cameraController.stopInertia()
        prevRotationRadians = 0

      case .changed:
        let delta = Float(recognizer.rotation - prevRotationRadians)
        prevRotationRadians = recognizer.rotation
        cameraController.setYawFromMinimap(cameraController.yaw + delta)
        onCameraChanged()

      case .ended, .cancelled, .failed:
        setInteracting(false)

      default:
        break
      }
    }

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .ended, let view = hostView else { return }
      cameraController.stopInertia()

      // 1. Ensure the minimap center point (`cameraController.target`) lies strictly inside the active site polygon
      let centerTarget = cameraController.target
      guard volume.isMetricPointInsideActiveArea(xM: centerTarget.x, zM: centerTarget.z) else {
        return
      }

      // 2. Also reject taps where the user's finger tapped outside the site polygon on the minimap
      let tapPt = recognizer.location(in: view)
      let width = max(Float(view.bounds.width), 1.0)
      let height = max(Float(view.bounds.height), 1.0)
      let dxPt = Float(tapPt.x) - (width * 0.5)
      let dyPt = Float(tapPt.y) - (height * 0.5)
      let mapCamDist = Float(
        min(
          max(Double(cameraController.distance) * 1.35, converter.minMapCameraDistanceM),
          converter.maxMapCameraDistanceM
        )
      )
      let metersPerPt = (mapCamDist * 0.65) / width
      let tappedMetric = centerTarget +
        cameraController.rightVector * (dxPt * metersPerPt) +
        cameraController.groundForwardVector * (-dyPt * metersPerPt)

      guard volume.isMetricPointInsideActiveArea(xM: tappedMetric.x, zM: tappedMetric.z) else {
        return
      }

      onSingleTap()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .ended else { return }
      cameraController.reset(for: volume)
      onCameraChanged()
      AccessibilityCaptionCenter.shared.announce("Camera fit to whole site.")
    }
  }
}
