import SwiftUI

struct CPTEmptyStateSheetView: View {
  var onUploadTap: (() -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast
  @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = 48

  init(onUploadTap: (() -> Void)? = nil) {
    self.onUploadTap = onUploadTap
  }

  private var resolvedButtonHeight: CGFloat {
    max(buttonHeight, 44)
  }

  var body: some View {
    VStack(spacing: 14) {
      // Inner Info Card
      VStack(alignment: .leading, spacing: 8) {
        Text("Upload your CPT data to get started")
          .font(.headline.weight(.bold))
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)

        Text("Your data will help identify areas where additional CPT testing may be useful.")
          .font(.subheadline)
          .foregroundStyle(contrast == .increased ? Color.primary : Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 16)
      .padding(.horizontal, 16)
      .background(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(Color(.secondarySystemGroupedBackground))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(
            Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
            lineWidth: contrast == .increased ? 1.5 : 1
          )
      )
      .shadow(
        color: Color.black.opacity(contrast == .increased ? 0 : 0.04),
        radius: 6,
        x: 0,
        y: 2
      )

      // Upload Button
      Button(action: {
        onUploadTap?()
      }) {
        HStack(spacing: 8) {
          Image(systemName: "square.and.arrow.up")
            .font(.body.weight(.semibold))

          Text("Upload Data CPT")
            .font(.body.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(minHeight: resolvedButtonHeight)
        .background(Color.blue, in: Capsule())
        .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Upload Data CPT")
      .accessibilityHint("Uploads your cone penetration testing dataset to begin recommendations")
      .accessibilityInputLabels(["Upload Data CPT", "Upload Data", "Upload CPT"])
    }
    .padding(.horizontal, 20)
    .padding(.top, 16)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .accessibilityElement(children: .contain)
  }
}

#Preview {
  @Previewable @State var isPresented = true
  Color.gray.opacity(0.3).ignoresSafeArea()
    .sheet(isPresented: $isPresented) {
      CPTEmptyStateSheetView()
        .presentationPlacement(.leading)
        .presentationDetents([.height(260), .medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
    }
}
