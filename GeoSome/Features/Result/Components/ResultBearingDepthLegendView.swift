import SwiftUI

struct ResultBearingDepthLegendView: View {
  var shallowestLimitText: String = "≤ 2.75m"
  var deepestLimitText: String = "≥ 4.75m"
  var shallowestDepthM: Double?
  var deepestDepthM: Double?
  var activeDepthM: Double?

  @Environment(\.colorSchemeContrast) private var contrast

  private static let gradientColors: [Color] = [
    Color(red: 0.98, green: 0.54, blue: 0.04), // Orange (Shallowest)
    Color(red: 0.98, green: 0.80, blue: 0.08), // Yellow
    Color(red: 0.65, green: 0.84, blue: 0.22), // Lime / Yellow-Green
    Color(red: 0.18, green: 0.76, blue: 0.46), // Green / Emerald
    Color(red: 0.08, green: 0.62, blue: 0.68), // Cyan / Teal
    Color(red: 0.06, green: 0.40, blue: 0.65)  // Deep Blue (Deepest)
  ]

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      // Left: Shallowest
      VStack(alignment: .leading, spacing: 2) {
        Text(shallowestLimitText)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Color.primary)

        Text("Shallowest")
          .font(.caption)
          .foregroundStyle(Color.secondary)
      }

      // Center: Gradient Capsule Bar
      ZStack(alignment: .leading) {
        Capsule()
          .fill(
            LinearGradient(
              colors: Self.gradientColors,
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(width: 200, height: 16)
        if let shallowestDepthM, let deepestDepthM, let activeDepthM,
           deepestDepthM > shallowestDepthM {
          let fraction = min(max((activeDepthM - shallowestDepthM) / (deepestDepthM - shallowestDepthM), 0), 1)
          Capsule()
            .fill(Color.primary)
            .frame(width: 3, height: 22)
            .overlay(Capsule().stroke(Color(.systemBackground), lineWidth: 1))
            .offset(x: CGFloat(fraction) * 197)
            .accessibilityLabel(String(format: "Kedalaman aktif %.1f meter", activeDepthM))
        }
      }
      .frame(width: 200, height: 16)

      // Right: Deepest
      VStack(alignment: .leading, spacing: 2) {
        Text(deepestLimitText)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Color.primary)

        Text("Deepest")
          .font(.caption)
          .foregroundStyle(Color.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.06),
          lineWidth: 1
        )
    )
    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Bearing layer depth legend: Shallowest \(shallowestLimitText) in orange to Deepest \(deepestLimitText) in deep blue")
  }
}

#Preview {
  ResultBearingDepthLegendView()
    .padding()
    .background(Color(.systemGroupedBackground))
}
