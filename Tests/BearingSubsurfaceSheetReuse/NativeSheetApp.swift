import SwiftUI
import UIKit

// Standalone UI verification app. All sheet views/helpers are production sources.
@main struct NativeSheetApp: App {
  @State private var detent = ResultAnalysisViewModel.defaultSheetDetent
  private let mode = ProcessInfo.processInfo.arguments.value(after: "--mode") ?? "bearing"
  var body: some Scene {
    WindowGroup {
      GeometryReader { proxy in
        let oneThirdSheetWidth = max((proxy.size.width / 3.0).rounded(), 280)
        ZStack {
          Color.white
          HStack {
            Spacer(minLength: 250)
            Rectangle().fill(Color.orange).frame(width: 700, height: 400)
            Spacer(minLength: 0)
          }
          VStack {
            Text("UI verification fixture — not project measurements").padding()
            Spacer()
          }
        }
        .sheet(isPresented: .constant(true)) {
          Group {
            if mode == "subsurface" {
              ResultLeftPlaceholderSheetView(
                groundConditionsSummary: "UI verification fixture. Reconstructed stratigraphy is shown here only to compare the unchanged Subsurface Conditions card, typography, native material, borders and scroll behavior. These values are test inputs, not measured project results.",
                legendItems: [.siltMixtures, .sandMixtures, .cleanSands, .denseSandToGravelly].map { LegendMapItem(soilType: $0) },
                predictionUncertaintyPercent: 31, cptPointsCount: 30)
            } else {
              ResultBearingLayerSheetView(shallowestDepthText: "7.3 m", deepestDepthText: "17.5 m",
                variationDepthText: "10.2 m", highUncertaintyAreaPercentText: "11.3%")
            }
          }
          // PRODUCTION_PRESENTATION_MODIFIERS
        }
      }
      .task {
        try? await Task.sleep(for: .milliseconds(1500))
        await verify()
      }
    }
  }
  @MainActor private func verify() async {
    let run = ProcessInfo.processInfo.arguments.value(after: "--run-id") ?? "manual"
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    var result: [String: Any] = ["mode": mode, "pass": false]
    defer {
      let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
      try? data?.write(to: directory.appendingPathComponent("\(run)-\(mode).json"))
    }
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
      let window = scene.windows.first(where: \.isKeyWindow),
      let presented = window.rootViewController?.presentedViewController,
      let sheet = presented.sheetPresentationController else { result["error"] = "No native sheet"; return }
    func scrolls(_ view: UIView) -> [UIScrollView] {
      (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrolls($0) }
    }
    guard let scroll = scrolls(presented.view).first else { result["error"] = "No native scroll"; return }
    let frame = presented.view.convert(presented.view.bounds, to: window)
    let expectedWidth = max((window.bounds.width / 3).rounded(), 280)
    result["width"] = frame.width; result["height"] = frame.height
    result["x"] = frame.minX; result["y"] = frame.minY
    result["expectedSharedWidth"] = expectedWidth
    result["grabberVisible"] = sheet.prefersGrabberVisible
    result["cornerRadiusOverride"] = sheet.preferredCornerRadius ?? NSNull()
    result["scrollEnabled"] = scroll.isScrollEnabled
    result["contentHeight"] = scroll.contentSize.height
    result["viewportHeight"] = scroll.bounds.height
    result["atTop"] = abs(scroll.contentOffset.y + scroll.adjustedContentInset.top) < 1
    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
      window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    try? image.pngData()?.write(to: directory.appendingPathComponent("\(run)-\(mode).png"))
    detent = .large
    try? await Task.sleep(for: .milliseconds(650))
    result["expandedHeight"] = presented.view.bounds.height
    let expandedImage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
      window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    try? expandedImage.pngData()?.write(to: directory.appendingPathComponent("\(run)-\(mode)-expanded.png"))
    let expanded = presented.view.bounds.height > frame.height
    detent = ResultAnalysisViewModel.collapsedSheetDetent
    try? await Task.sleep(for: .milliseconds(650))
    result["collapsedHeight"] = presented.view.bounds.height
    let collapsed = abs(presented.view.bounds.height - 74) < 1
    detent = ResultAnalysisViewModel.defaultSheetDetent
    try? await Task.sleep(for: .milliseconds(650))
    result["restoredHeight"] = presented.view.bounds.height
    let restored = abs(presented.view.bounds.height - 460) < 1
    let oldOffset = scroll.contentOffset.y
    scroll.setContentOffset(CGPoint(x: 0, y: 40), animated: false)
    result["scrollOffsetChanged"] = scroll.contentOffset.y != oldOffset
    result["pass"] = abs(frame.width - expectedWidth) < 1 && abs(frame.height - 460) < 1 &&
      sheet.prefersGrabberVisible && sheet.preferredCornerRadius == nil && scroll.isScrollEnabled &&
      (result["atTop"] as? Bool == true) && expanded && collapsed && restored &&
      (result["scrollOffsetChanged"] as? Bool == true)
  }
}
private extension Array where Element == String {
  func value(after argument: String) -> String? {
    guard let index = firstIndex(of: argument), index + 1 < count else { return nil }
    return self[index + 1]
  }
}
