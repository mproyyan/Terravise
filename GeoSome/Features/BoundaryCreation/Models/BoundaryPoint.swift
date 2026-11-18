import CoreLocation
import Foundation
import MapKit

struct BoundaryPoint: Identifiable, Hashable, Codable, Sendable {
  let id: UUID
  var latitude: Double
  var longitude: Double

  init(
    id: UUID = UUID(),
    latitude: Double,
    longitude: Double
  ) {
    self.id = id
    self.latitude = latitude
    self.longitude = longitude
  }

  init(
    id: UUID = UUID(),
    coordinate: CLLocationCoordinate2D
  ) {
    self.id = id
    latitude = coordinate.latitude
    longitude = coordinate.longitude
  }

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  private static let coordinateFormat = FloatingPointFormatStyle<Double>(
    locale: Locale(identifier: "en_US_POSIX")
  )
  .grouping(.never)
  .precision(.fractionLength(0 ... 6))

  var formattedLatitude: String {
    latitude.formatted(Self.coordinateFormat)
  }

  var formattedLongitude: String {
    longitude.formatted(Self.coordinateFormat)
  }

  var utmCoordinate: UTMCoordinate {
    UTMCoordinateConverter.coordinateToUTM(coordinate)
  }

  var formattedCoordinate: String {
    UTMCoordinateConverter.formatAsUTM(coordinate)
  }
}

enum BoundaryMapConfiguration {
  static let defaultCenter = CLLocationCoordinate2D(
    latitude: -6.2415,
    longitude: 106.8315
  )

  static let defaultSpan = MKCoordinateSpan(
    latitudeDelta: 0.012,
    longitudeDelta: 0.012
  )

  static var defaultRegion: MKCoordinateRegion {
    MKCoordinateRegion(
      center: defaultCenter,
      span: defaultSpan
    )
  }
}
