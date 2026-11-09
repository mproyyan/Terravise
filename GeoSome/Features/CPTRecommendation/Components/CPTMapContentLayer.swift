import CoreLocation
import MapKit
import SwiftUI

struct CPTMapContentLayer: View {
  @Binding var cameraPosition: MapCameraPosition
  var coordinates: [CLLocationCoordinate2D]
  var isSatelliteStyle: Bool
  var recommendedCoordinate: CLLocationCoordinate2D?
  var cptPoints: [CPTPointEntry]

  @Environment(\.colorSchemeContrast) private var contrast

  init(
    cameraPosition: Binding<MapCameraPosition>,
    coordinates: [CLLocationCoordinate2D] = [],
    isSatelliteStyle: Bool = false,
    recommendedCoordinate: CLLocationCoordinate2D? = nil,
    cptPoints: [CPTPointEntry] = []
  ) {
    _cameraPosition = cameraPosition
    self.coordinates = coordinates
    self.isSatelliteStyle = isSatelliteStyle
    self.recommendedCoordinate = recommendedCoordinate
    self.cptPoints = cptPoints
  }

  var body: some View {
    Map(position: $cameraPosition) {
      UserAnnotation()

      if coordinates.count >= 3 {
        MapPolygon(coordinates: coordinates)
          .foregroundStyle(Color.blue.opacity(contrast == .increased ? 0.35 : 0.20))
          .stroke(Color.blue, lineWidth: contrast == .increased ? 3.5 : 2.5)
      } else if coordinates.count == 2 {
        MapPolyline(coordinates: coordinates)
          .stroke(
            Color.blue,
            style: StrokeStyle(
              lineWidth: contrast == .increased ? 3.5 : 2.5,
              lineCap: .round,
              lineJoin: .round,
              dash: [8, 6]
            )
          )
      }

      // Uploaded CPT Points Annotations (Orange Circle with Number)
      ForEach(Array(cptPoints.enumerated()), id: \.element.id) { index, point in
        Annotation("CPT Point \(index + 1)", coordinate: point.coordinate) {
          ZStack {
            Circle()
              .fill(Color.orange)
              .frame(width: 28, height: 28)
              .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)

            Text("\(index + 1)")
              .font(.caption.weight(.bold))
              .foregroundStyle(Color.white)
          }
          .accessibilityLabel("CPT Point \(index + 1)")
        }
      }

      // Recommended Point Annotation (Green Circle with X)
      if let recommendedCoordinate {
        Annotation("Recommended Point", coordinate: recommendedCoordinate) {
          ZStack {
            Circle()
              .fill(Color.green)
              .frame(width: 32, height: 32)
              .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

            Image(systemName: "xmark")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(.white)
          }
          .accessibilityLabel("Recommended CPT Point")
        }
      }
    }
    .mapStyle(
      isSatelliteStyle
        ? .hybrid(elevation: .realistic)
        : .standard(elevation: .realistic)
    )
    .mapControlVisibility(.hidden)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Map with project boundary and CPT points")
  }
}

#Preview {
  CPTMapContentLayer(
    cameraPosition: .constant(.region(BoundaryMapConfiguration.defaultRegion)),
    coordinates: [
      CLLocationCoordinate2D(latitude: -6.2405, longitude: 106.8295),
      CLLocationCoordinate2D(latitude: -6.2402, longitude: 106.8336),
      CLLocationCoordinate2D(latitude: -6.2435, longitude: 106.8338),
      CLLocationCoordinate2D(latitude: -6.2430, longitude: 106.8292)
    ],
    recommendedCoordinate: CLLocationCoordinate2D(latitude: -6.2415, longitude: 106.8315),
    cptPoints: [
      CPTPointEntry(
        coordinate: CLLocationCoordinate2D(latitude: -6.2410, longitude: 106.8300),
        file: CPTUploadedFile(name: "CPT1.csv")
      )
    ]
  )
}
