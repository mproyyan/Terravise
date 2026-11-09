import MapKit
import SwiftUI

struct CPTMapContentLayer: View {
  @Binding var cameraPosition: MapCameraPosition
  var coordinates: [CLLocationCoordinate2D]
  var isSatelliteStyle: Bool

  @Environment(\.colorSchemeContrast) private var contrast

  init(
    cameraPosition: Binding<MapCameraPosition>,
    coordinates: [CLLocationCoordinate2D] = [],
    isSatelliteStyle: Bool = false
  ) {
    _cameraPosition = cameraPosition
    self.coordinates = coordinates
    self.isSatelliteStyle = isSatelliteStyle
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
    }
    .mapStyle(
      isSatelliteStyle
        ? .hybrid(elevation: .realistic)
        : .standard(elevation: .realistic)
    )
    .mapControlVisibility(.hidden)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Map with project boundary")
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
    ]
  )
}
