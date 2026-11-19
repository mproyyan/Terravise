import SwiftUI

struct ResultBearingPointPopoverView: View {
  var title: String = "Bearing Layer - 02"
  var depthText: String = "4.72 m"
  var northingText: String = "9,312,450 m"
  var eastingText: String = "699,250 m"
  var indicatorColor: Color = Color.orange
  var isCompared: Bool = false
  var onAddToCompare: (() -> Void)? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      // Top: Capsule Indicator + Title & Depth
      HStack(alignment: .center, spacing: 10) {
        Capsule()
          .fill(indicatorColor)
          .frame(width: 7, height: 32)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.subheadline)
            .foregroundStyle(Color.secondary)

          Text(depthText)
            .font(.title3.weight(.bold))
            .foregroundStyle(Color.primary)
        }
      }

      // Middle: Coordinates (Northing & Easting)
      HStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Northing (N)")
            .font(.caption)
            .foregroundStyle(Color.secondary)

          Text(northingText)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)
        }

        VStack(alignment: .leading, spacing: 3) {
          Text("Easting (E)")
            .font(.caption)
            .foregroundStyle(Color.secondary)

          Text(eastingText)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.primary)
        }
      }

      // Bottom: Add to Compare Button
      Button(action: {
        onAddToCompare?()
      }) {
        Text(isCompared ? "Added to Compare" : "Add to Compare")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Color.blue)
          .frame(maxWidth: .infinity)
          .frame(height: 38)
          .background(
            Capsule()
              .fill(Color(.tertiarySystemFill))
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isCompared ? "Added to Compare" : "Add to Compare")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .accessibilityElement(children: .contain)
  }
}

// MARK: - Native-styled Popover Bubble Shape with Vertical Pointer

struct BearingPopoverBubbleShape: Shape {
  enum ArrowPosition {
    case bottom
    case top
  }

  var arrowPosition: ArrowPosition = .bottom
  var arrowX: CGFloat
  var cornerRadius: CGFloat = 18
  var arrowWidth: CGFloat = 16
  var arrowHeight: CGFloat = 10

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let minY = arrowPosition == .top ? rect.minY + arrowHeight : rect.minY
    let maxY = arrowPosition == .bottom ? rect.maxY - arrowHeight : rect.maxY
    let minX = rect.minX
    let maxX = rect.maxX
    let clampedArrowX = min(
      max(arrowX, minX + cornerRadius + arrowWidth * 0.5),
      maxX - cornerRadius - arrowWidth * 0.5
    )

    // Start at top-left
    path.move(to: CGPoint(x: minX + cornerRadius, y: minY))

    // Top edge & top arrow
    if arrowPosition == .top {
      path.addLine(to: CGPoint(x: clampedArrowX - arrowWidth * 0.5, y: minY))
      path.addLine(to: CGPoint(x: clampedArrowX, y: rect.minY))
      path.addLine(to: CGPoint(x: clampedArrowX + arrowWidth * 0.5, y: minY))
    }
    path.addLine(to: CGPoint(x: maxX - cornerRadius, y: minY))

    // Top-right corner
    path.addArc(
      center: CGPoint(x: maxX - cornerRadius, y: minY + cornerRadius),
      radius: cornerRadius,
      startAngle: .degrees(-90),
      endAngle: .degrees(0),
      clockwise: false
    )

    // Right edge
    path.addLine(to: CGPoint(x: maxX, y: maxY - cornerRadius))

    // Bottom-right corner
    path.addArc(
      center: CGPoint(x: maxX - cornerRadius, y: maxY - cornerRadius),
      radius: cornerRadius,
      startAngle: .degrees(0),
      endAngle: .degrees(90),
      clockwise: false
    )

    // Bottom edge & bottom arrow
    if arrowPosition == .bottom {
      path.addLine(to: CGPoint(x: clampedArrowX + arrowWidth * 0.5, y: maxY))
      path.addLine(to: CGPoint(x: clampedArrowX, y: rect.maxY))
      path.addLine(to: CGPoint(x: clampedArrowX - arrowWidth * 0.5, y: maxY))
    }
    path.addLine(to: CGPoint(x: minX + cornerRadius, y: maxY))

    // Bottom-left corner
    path.addArc(
      center: CGPoint(x: minX + cornerRadius, y: maxY - cornerRadius),
      radius: cornerRadius,
      startAngle: .degrees(90),
      endAngle: .degrees(180),
      clockwise: false
    )

    // Left edge
    path.addLine(to: CGPoint(x: minX, y: minY + cornerRadius))

    // Top-left corner
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

#Preview {
  ZStack {
    Color.gray.opacity(0.2).ignoresSafeArea()

    ResultBearingPointPopoverView()
      .padding(.bottom, 10)
      .frame(width: 250)
      .background {
        BearingPopoverBubbleShape(
          arrowPosition: .bottom,
          arrowX: 125,
          cornerRadius: 18,
          arrowWidth: 16,
          arrowHeight: 10
        )
        .fill(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.15), radius: 14, x: 0, y: 5)
      }
  }
}
