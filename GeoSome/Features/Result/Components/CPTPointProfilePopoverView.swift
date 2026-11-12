import SwiftUI

struct SBTProfileLayerItem: Identifiable, Sendable {
  let id = UUID()
  let topDepthM: Double
  let bottomDepthM: Double
  let name: String
  let color: Color
  let textColor: Color
  let barHeight: CGFloat
}

struct CPTPointProfilePopoverView: View {
  var pointTitle: String
  var latitudeText: String
  var longitudeText: String
  var layers: [SBTProfileLayerItem]

  @Environment(\.colorSchemeContrast) private var contrast

  static let defaultLayers: [SBTProfileLayerItem] = [
    SBTProfileLayerItem(
      topDepthM: 0.0,
      bottomDepthM: 2.0,
      name: "Sands: clean sands to silty sands",
      color: Color(red: 0.73, green: 0.60, blue: 0.35),
      textColor: Color.black.opacity(0.9),
      barHeight: 36
    ),
    SBTProfileLayerItem(
      topDepthM: 2.0,
      bottomDepthM: 4.2,
      name: "Silt mixtures: clayey silt & silty clay",
      color: Color(red: 0.33, green: 0.53, blue: 0.49),
      textColor: Color.white,
      barHeight: 36
    ),
    SBTProfileLayerItem(
      topDepthM: 4.2,
      bottomDepthM: 8.5,
      name: "Clay - organic soil",
      color: Color(red: 0.64, green: 0.36, blue: 0.21),
      textColor: Color.white,
      barHeight: 46
    ),
    SBTProfileLayerItem(
      topDepthM: 8.5,
      bottomDepthM: 16.2,
      name: "Sand mixtures: silty sand to sandy silt",
      color: Color(red: 0.50, green: 0.74, blue: 0.58),
      textColor: Color.black.opacity(0.9),
      barHeight: 54
    ),
    SBTProfileLayerItem(
      topDepthM: 16.2,
      bottomDepthM: 25.0,
      name: "Dense sand to gravelly sand",
      color: Color(red: 0.90, green: 0.57, blue: 0.27),
      textColor: Color.black.opacity(0.9),
      barHeight: 58
    )
  ]

  init(
    pointTitle: String = "CPT Point-01",
    latitudeText: String = "-6.215432",
    longitudeText: String = "106.845321",
    layers: [SBTProfileLayerItem] = defaultLayers
  ) {
    self.pointTitle = pointTitle
    self.latitudeText = latitudeText
    self.longitudeText = longitudeText
    self.layers = layers
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      // Point Title
      Text(pointTitle)
        .font(.title3.weight(.bold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)

      // Latitude & Longitude Info Cards
      HStack(spacing: 12) {
        coordinateCard(title: "Latitude", value: latitudeText)
        coordinateCard(title: "Longitude", value: longitudeText)
      }

      // Section Header: CPT-derived SBT profile
      VStack(alignment: .leading, spacing: 2) {
        Text("CPT-derived SBT profile")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Color.primary)
          .accessibilityAddTraits(.isHeader)

        Text("Depth below local ground level")
          .font(.caption)
          .foregroundStyle(Color.secondary)
      }
      .padding(.top, 2)

      // Stratigraphy Profile with Depth Ruler
      stratigraphyProfileCard
    }
    .padding(18)
    .frame(width: 340)
  }

  // MARK: - Subviews

  private func coordinateCard(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(Color.secondary)

      Text(value)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Color.primary)
        .monospacedDigit()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(.tertiarySystemFill).opacity(0.55))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.06),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title): \(value)")
  }

  private var stratigraphyProfileCard: some View {
    let rulerHeight: CGFloat = layers.reduce(0) { $0 + $1.barHeight } + CGFloat(max(layers.count - 1, 0)) * 6.0

    return HStack(alignment: .top, spacing: 8) {
      // Left: Depth Ruler and Axis line
      depthRulerView(totalHeight: rulerHeight)

      // Right: Layer Colored Bars
      VStack(spacing: 6) {
        ForEach(layers) { layer in
          HStack {
            Text(layer.name)
              .font(.footnote.weight(.semibold))
              .foregroundStyle(layer.textColor)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
              .padding(.leading, 12)

            Spacer(minLength: 4)
          }
          .frame(maxWidth: .infinity)
          .frame(height: layer.barHeight)
          .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(layer.color)
          )
          .accessibilityElement(children: .combine)
          .accessibilityLabel(
            String(
              format: "%@, depth %.1f meters to %.1f meters",
              layer.name,
              layer.topDepthM,
              layer.bottomDepthM
            )
          )
        }
      }
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.tertiarySystemFill).opacity(0.40))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
  }

  private func depthRulerView(totalHeight: CGFloat) -> some View {
    // Calculate cumulative offsets for each depth tick
    var tickPositions: [(label: String, y: CGFloat)] = []
    var currentY: CGFloat = 0.0

    if let first = layers.first {
      tickPositions.append((label: formatDepth(first.topDepthM), y: 0.0))
    }

    for (index, layer) in layers.enumerated() {
      if index > 0 {
        currentY += 6.0
      }
      currentY += layer.barHeight
      tickPositions.append((label: formatDepth(layer.bottomDepthM), y: currentY))
    }

    return ZStack(alignment: .topTrailing) {
      // Continuous Vertical Axis Line
      Path { path in
        path.move(to: CGPoint(x: 42, y: 0))
        path.addLine(to: CGPoint(x: 42, y: totalHeight))
      }
      .stroke(Color(.systemGray3), lineWidth: 1.5)

      // Horizontal Ticks and Depth Labels
      ForEach(Array(tickPositions.enumerated()), id: \.offset) { _, tick in
        Path { path in
          path.move(to: CGPoint(x: 36, y: tick.y))
          path.addLine(to: CGPoint(x: 42, y: tick.y))
        }
        .stroke(Color(.systemGray3), lineWidth: 1.5)

        Text(tick.label)
          .font(.system(size: 11, weight: .regular, design: .monospaced))
          .foregroundStyle(Color.secondary)
          .frame(width: 34, alignment: .trailing)
          .position(x: 18, y: tick.y)
      }
    }
    .frame(width: 44, height: totalHeight)
    .accessibilityHidden(true)
  }

  private func formatDepth(_ depth: Double) -> String {
    if depth == 0.0 {
      return "0 m"
    }
    return String(format: "%.1f m", depth)
  }
}

#Preview {
  CPTPointProfilePopoverView()
    .padding()
    .background(Color(.systemBackground))
}
