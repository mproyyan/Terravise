import SwiftUI

struct CPTMapControlsView: View {
  var isSatelliteStyle: Bool
  var onToggleMapLayer: (() -> Void)?
  var onFocusBoundary: (() -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
  @ScaledMetric(relativeTo: .body) private var controlDimension: CGFloat = 46

  init(
    isSatelliteStyle: Bool = false,
    onToggleMapLayer: (() -> Void)? = nil,
    onFocusBoundary: (() -> Void)? = nil
  ) {
    self.isSatelliteStyle = isSatelliteStyle
    self.onToggleMapLayer = onToggleMapLayer
    self.onFocusBoundary = onFocusBoundary
  }

  private var resolvedDimension: CGFloat {
    max(controlDimension, 44)
  }

  var body: some View {
    VStack(spacing: 0) {
      // Map Layer Toggle Button
      Button(action: {
        onToggleMapLayer?()
      }) {
        VStack(spacing: 2) {
          Image(systemName: isSatelliteStyle ? "globe.americas.fill" : "map")
            .font(.body.weight(.medium))
            .imageScale(.large)
            .foregroundStyle(.primary)

          if differentiateWithoutColor {
            Text(isSatelliteStyle ? "SAT" : "MAP")
              .font(.caption2.weight(.bold))
              .foregroundStyle(.primary)
          }
        }
        .frame(minWidth: resolvedDimension, minHeight: resolvedDimension)
        .padding(.vertical, differentiateWithoutColor ? 4 : 0)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Change map layer")
      .accessibilityValue(isSatelliteStyle ? "Satellite" : "Standard")
      .accessibilityHint("Switches between standard and satellite map views")
      .accessibilityInputLabels(["Map Layer", "Toggle Map Layer", "Satellite", "Map Style"])

      Divider()
        .frame(width: resolvedDimension)

      // Focus Boundary Location Button
      Button(action: {
        onFocusBoundary?()
      }) {
        Image(systemName: differentiateWithoutColor ? "location.fill" : "location")
          .font(.body.weight(.medium))
          .imageScale(.large)
          .foregroundStyle(contrast == .increased ? Color.primary : Color.blue)
          .frame(minWidth: resolvedDimension, minHeight: resolvedDimension)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Focus on project boundary")
      .accessibilityHint("Centers the map on the project boundary area")
      .accessibilityInputLabels(["Focus Boundary", "Center Boundary", "Center Map"])
    }
    .frame(width: resolvedDimension)
    .background {
      if reduceTransparency || contrast == .increased {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color(.secondarySystemBackground))
      }
    }
    .glassEffect(
      .regular.interactive(),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.45 : 0.12),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
  }
}

#Preview {
  ZStack {
    Color.gray.opacity(0.3).ignoresSafeArea()
    CPTMapControlsView()
  }
}
