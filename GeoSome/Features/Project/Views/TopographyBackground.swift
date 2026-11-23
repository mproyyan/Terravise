import SwiftUI

struct TopographyBackground: View {
  var darkOverlayOpacity: Double
  var alignment: UnitPoint

  private let artworkSize = CGSize(width: 4480, height: 2500)

  init(
    darkOverlayOpacity: Double = 0.58,
    alignment: UnitPoint = .center
  ) {
    self.darkOverlayOpacity = darkOverlayOpacity
    self.alignment = alignment
  }

  var body: some View {
    GeometryReader { geometry in
      let containerSize = geometry.size
      let imageSize = imageSize(filling: containerSize)
      let imageOrigin = CGPoint(
        x: (containerSize.width - imageSize.width) * alignment.x,
        y: (containerSize.height - imageSize.height) * alignment.y
      )

      ZStack(alignment: .topLeading) {
        Image("contours-topographic")
          .resizable()
          .interpolation(.high)
          .frame(width: imageSize.width, height: imageSize.height)
          .position(
            x: imageOrigin.x + imageSize.width / 2,
            y: imageOrigin.y + imageSize.height / 2
          )
      }
      .frame(width: containerSize.width, height: containerSize.height)
      .overlay {
        Color.black.opacity(darkOverlayOpacity)
      }
      .clipped()
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  private func imageSize(filling containerSize: CGSize) -> CGSize {
    let scale = max(
      containerSize.width / artworkSize.width,
      containerSize.height / artworkSize.height
    )

    return CGSize(
      width: artworkSize.width * scale,
      height: artworkSize.height * scale
    )
  }
}

#Preview {
  TopographyBackground()
    .frame(width: 834, height: 520)
}
