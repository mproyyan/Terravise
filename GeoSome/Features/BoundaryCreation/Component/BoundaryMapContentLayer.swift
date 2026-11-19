import MapKit
import SwiftUI

struct BoundaryMapContentLayer: View {
  @Binding var cameraPosition: MapCameraPosition
  var points: [BoundaryPoint]
  var isSatelliteStyle: Bool
  var onMapTap: ((CLLocationCoordinate2D) -> Void)?
  var onBeginMovePoint: (() -> Void)?
  var onMovePoint: ((BoundaryPoint.ID, CLLocationCoordinate2D) -> Void)?
  var onSelectPoint: ((BoundaryPoint) -> Void)?
  var onDeletePoint: ((BoundaryPoint.ID) -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = 28

  @State private var draggingPointID: BoundaryPoint.ID?
  @State private var dragStartCoordinate: CLLocationCoordinate2D?
  @State private var didRecordDragStart: Bool = false
  @State private var lastPointInteractionTime: Date = .distantPast

  init(
    cameraPosition: Binding<MapCameraPosition>,
    points: [BoundaryPoint] = [],
    isSatelliteStyle: Bool = false,
    onMapTap: ((CLLocationCoordinate2D) -> Void)? = nil,
    onBeginMovePoint: (() -> Void)? = nil,
    onMovePoint: ((BoundaryPoint.ID, CLLocationCoordinate2D) -> Void)? = nil,
    onSelectPoint: ((BoundaryPoint) -> Void)? = nil,
    onDeletePoint: ((BoundaryPoint.ID) -> Void)? = nil
  ) {
    _cameraPosition = cameraPosition
    self.points = points
    self.isSatelliteStyle = isSatelliteStyle
    self.onMapTap = onMapTap
    self.onBeginMovePoint = onBeginMovePoint
    self.onMovePoint = onMovePoint
    self.onSelectPoint = onSelectPoint
    self.onDeletePoint = onDeletePoint
  }

  private var coordinates: [CLLocationCoordinate2D] {
    points.map(\.coordinate)
  }

  private var resolvedBadgeSize: CGFloat {
    max(badgeSize, 28)
  }

  var body: some View {
    MapReader { proxy in
      Map(
        position: $cameraPosition,
        interactionModes: draggingPointID == nil ? .all : []
      ) {
        UserAnnotation()

        if coordinates.count == 2 {
          MapPolyline(coordinates: coordinates)
            .stroke(
              .blue,
              style: StrokeStyle(
                lineWidth: contrast == .increased ? 4 : 3,
                lineCap: .round,
                lineJoin: .round,
                dash: [8, 6]
              )
            )
        } else if coordinates.count >= 3 {
          MapPolygon(coordinates: coordinates)
            .foregroundStyle(.blue.opacity(contrast == .increased ? 0.34 : 0.22))
            .stroke(.blue, lineWidth: contrast == .increased ? 4 : 3)
        }

        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
          let isDraggingThisPoint = draggingPointID == point.id
          let anchorCoordinate = (isDraggingThisPoint ? dragStartCoordinate : nil) ?? point.coordinate

          Annotation("CPT Point \(index + 1)", coordinate: anchorCoordinate, anchor: .center) {
            interactivePointBadge(
              index: index,
              point: point,
              isDragging: isDraggingThisPoint,
              proxy: proxy
            )
          }
          .annotationTitles(.hidden)
        }

        if let draggingPointID,
           let draggedIndex = points.firstIndex(where: { $0.id == draggingPointID })
        {
          let draggedPoint = points[draggedIndex]
          Annotation(
            "CPT Point \(draggedIndex + 1) Preview",
            coordinate: draggedPoint.coordinate,
            anchor: .center
          ) {
            pointBadgeLabel(index: draggedIndex, isDragging: true)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
          .annotationTitles(.hidden)
        }
      }
      .mapStyle(
        isSatelliteStyle
          ? .hybrid(elevation: .realistic)
          : .standard(elevation: .realistic, pointsOfInterest: .all)
      )
      .mapControlVisibility(.hidden)
      .onTapGesture { screenPoint in
        guard
          draggingPointID == nil,
          Date.now.timeIntervalSince(lastPointInteractionTime) > 0.3,
          !isScreenPointNearExistingAnnotation(screenPoint, proxy: proxy)
        else {
          return
        }

        if let coordinate = proxy.convert(screenPoint, from: .local) {
          onMapTap?(coordinate)
        }
      }
      .accessibilityAction(named: "Add Boundary Point at Default Anchor") {
        onMapTap?(BoundaryMapConfiguration.defaultCenter)
      }
      .ignoresSafeArea()
    }
  }

  private func isScreenPointNearExistingAnnotation(
    _ screenPoint: CGPoint,
    proxy: MapProxy
  ) -> Bool {
    for point in points {
      if let existingScreenPoint = proxy.convert(point.coordinate, to: .local) {
        let distance = hypot(
          screenPoint.x - existingScreenPoint.x,
          screenPoint.y - existingScreenPoint.y
        )
        if distance < 28 {
          return true
        }
      }
    }
    return false
  }

  private func pointBadgeLabel(index: Int, isDragging: Bool) -> some View {
    let isFirstAnchor = index == 0 && differentiateWithoutColor
    return Text("\(index + 1)")
      .font(.caption.weight(.bold))
      .foregroundStyle(.white)
      .padding(4)
      .frame(minWidth: resolvedBadgeSize, minHeight: resolvedBadgeSize)
      .background(
        .blue,
        in: isFirstAnchor
          ? AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
          : AnyShape(Circle())
      )
      .overlay {
        if isFirstAnchor {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(.white, lineWidth: contrast == .increased ? 3 : 2)
        } else {
          Circle()
            .stroke(
              .white,
              style: StrokeStyle(
                lineWidth: contrast == .increased ? 3 : 2,
                dash: isDragging ? [4, 2] : []
              )
            )
        }
      }
      .scaleEffect(isDragging && !reduceMotion ? 1.2 : 1.0)
      .shadow(
        color: .black.opacity(isDragging ? 0.3 : 0.2),
        radius: isDragging ? 6 : 3,
        y: 2
      )
  }

  private func interactivePointBadge(
    index: Int,
    point: BoundaryPoint,
    isDragging: Bool,
    proxy: MapProxy
  ) -> some View {
    pointBadgeLabel(index: index, isDragging: false)
      .opacity(isDragging ? 0 : 1)
      .frame(minWidth: max(resolvedBadgeSize, 44), minHeight: max(resolvedBadgeSize, 44))
      .contentShape(Circle())
      .highPriorityGesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            lastPointInteractionTime = .now

            if draggingPointID != point.id {
              draggingPointID = point.id
              dragStartCoordinate = point.coordinate
              didRecordDragStart = false
            }

            let distance = hypot(value.translation.width, value.translation.height)
            guard
              distance > 1,
              let startCoordinate = dragStartCoordinate,
              let startScreenPoint = proxy.convert(startCoordinate, to: .local)
            else {
              return
            }

            if !didRecordDragStart {
              didRecordDragStart = true
              onBeginMovePoint?()
            }

            let targetScreenPoint = CGPoint(
              x: startScreenPoint.x + value.translation.width,
              y: startScreenPoint.y + value.translation.height
            )

            if let newCoordinate = proxy.convert(targetScreenPoint, from: .local) {
              onMovePoint?(point.id, newCoordinate)
            }
          }
          .onEnded { value in
            lastPointInteractionTime = .now

            let distance = hypot(value.translation.width, value.translation.height)
            if distance > 1,
               let startCoordinate = dragStartCoordinate,
               let startScreenPoint = proxy.convert(startCoordinate, to: .local)
            {
              if !didRecordDragStart {
                didRecordDragStart = true
                onBeginMovePoint?()
              }
              let targetScreenPoint = CGPoint(
                x: startScreenPoint.x + value.translation.width,
                y: startScreenPoint.y + value.translation.height
              )
              if let finalCoordinate = proxy.convert(targetScreenPoint, from: .local) {
                onMovePoint?(point.id, finalCoordinate)
                AccessibilityCaptionCenter.shared.announce(
                  "Moved CPT Point \(index + 1) to \(BoundaryPoint(coordinate: finalCoordinate).formattedCoordinate)."
                )
              }
            }

            draggingPointID = nil
            dragStartCoordinate = nil
            didRecordDragStart = false
          }
      )
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("CPT Point \(index + 1)")
      .accessibilityValue(point.formattedCoordinate)
      .accessibilityHint("Double-tap and hold to drag on the map, or use actions to edit or delete")
      .accessibilityAction(named: "Edit Coordinate") {
        onSelectPoint?(point)
      }
      .accessibilityAction(named: "Delete Point") {
        onDeletePoint?(point.id)
      }
  }
}

#Preview {
  @Previewable @State var position = MapCameraPosition.region(BoundaryMapConfiguration.defaultRegion)
  @Previewable @State var points = [
    BoundaryPoint(latitude: -6.2405, longitude: 106.8305),
    BoundaryPoint(latitude: -6.2425, longitude: 106.8330),
    BoundaryPoint(latitude: -6.2430, longitude: 106.8295)
  ]

  BoundaryMapContentLayer(
    cameraPosition: $position,
    points: points,
    isSatelliteStyle: false,
    onMovePoint: { id, newCoordinate in
      if let index = points.firstIndex(where: { $0.id == id }) {
        points[index].latitude = newCoordinate.latitude
        points[index].longitude = newCoordinate.longitude
      }
    }
  )
}
