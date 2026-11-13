import SwiftUI

struct ResultBearingDepthLegendView: View {
  var shallowestLimitText: String = "≤ 2.75m"
  var deepestLimitText: String = "≥ 4.75m"

  private static let gradientColors: [Color] = [
    Color(red: 0.96, green: 0.51, blue: 0.13), // Orange (Shallowest)
    Color(red: 0.90, green: 0.82, blue: 0.22), // Yellow
    Color(red: 0.42, green: 0.78, blue: 0.39), // Green
    Color(red: 0.14, green: 0.62, blue: 0.68), // Cyan/Teal
    Color(red: 0.05, green: 0.35, blue: 0.60)  // Deep Blue (Deepest)
  ]

  var body: some View {
    VStack(spacing: 4) {
      // Gradient Pill Bar
      Capsule()
        .fill(
          LinearGradient(
            colors: Self.gradientColors,
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .frame(width: 220, height: 14)

      // Bracket Axis Line with End Ticks
      Canvas { context, size in
        var path = Path()
        let tickHeight: CGFloat = 5
        // Left tick
        path.move(to: CGPoint(x: 1, y: tickHeight))
        path.addLine(to: CGPoint(x: 1, y: 0.5))
        // Horizontal line
        path.addLine(to: CGPoint(x: size.width - 1, y: 0.5))
        // Right tick
        path.addLine(to: CGPoint(x: size.width - 1, y: tickHeight))

        context.stroke(
          path,
          with: .color(Color.secondary.opacity(0.6)),
          lineWidth: 1
        )
      }
      .frame(width: 220, height: 6)

      // Labels Row
      HStack {
        VStack(alignment: .center, spacing: 1) {
          Text("Shallowest")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.primary)
          Text(shallowestLimitText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.primary)
        }

        Spacer()

        VStack(alignment: .center, spacing: 1) {
          Text("Deepest")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.primary)
          Text(deepestLimitText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.primary)
        }
      }
      .frame(width: 244)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Bearing layer depth legend: Shallowest \(shallowestLimitText) in orange to Deepest \(deepestLimitText) in deep blue")
  }
}

#Preview {
  ResultBearingDepthLegendView()
    .padding()
}
