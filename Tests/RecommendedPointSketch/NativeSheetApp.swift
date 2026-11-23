import SwiftUI
import UIKit
import Vision

@main struct RecommendedSheetProbe: App {
  private static var mode: String {
    let args = ProcessInfo.processInfo.arguments
    return args.firstIndex(of: "--mode").map { args[$0 + 1] } ?? "stop"
  }
  @State private var detent = Self.mode == "stop" ? CPTRecommendedPointSheetView.stopSheetDetent : (Self.mode == "continue" ? CPTRecommendationViewModel.recommendationSheetDetent : CPTRecommendationViewModel.sufficientSheetDetent)
  var body: some Scene {
    WindowGroup {
      Color.gray.opacity(0.35)
        .sheet(isPresented: .constant(true)) {
          CPTRecommendedPointSheetView(recommendation: Self.stopResult(), cptPointsCount: Self.mode == "stop" ? 1 : 30)
          // PRODUCTION_MODIFIERS
        }
        .task {
          try? await Task.sleep(for: .milliseconds(1500))
          capture()
        }
    }
  }
  static func stopResult() -> CPTRecommendationResult {
    var result = CPTRecommendationResult(isSufficient: mode == "stop", hasRecommendation: mode == "continue")
    result.stratigraphicDecision = .init(outcome: mode == "stop" ? .stop : .continue, reasons: [], stateID: "ui-fixture", metrics: [:], evidenceValid: true)
    return result
  }
  @MainActor private func capture() {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
      let window = scene.windows.first(where: \.isKeyWindow),
      let presented = window.rootViewController?.presentedViewController,
      let sheet = presented.sheetPresentationController else { return }
    let args=ProcessInfo.processInfo.arguments
    let mode = Self.mode
    let run=args.firstIndex(of: "--run-id").map{args[$0+1]} ?? "manual"
    let dir=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
    let image=UIGraphicsImageRenderer(bounds:window.bounds).image{_ in window.drawHierarchy(in:window.bounds,afterScreenUpdates:true)}
    try? image.pngData()?.write(to:dir.appendingPathComponent("\(run)-\(mode).png"))
    let frame=presented.view.convert(presented.view.bounds,to:window)
    let ocr = VNRecognizeTextRequest(); ocr.recognitionLevel = .accurate
    try? VNImageRequestHandler(cgImage: image.cgImage!).perform([ocr])
    let text = (ocr.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    let pass: Bool
    if mode == "stop" {
      pass = frame.width == 445 && frame.height == 286 && text.contains("CPT coverage is sufficient") && text.contains("Upload CPT Data")
    } else if mode == "continue" {
      pass = text.contains("Recommended Point") && text.contains("Run a CPT at this point") && !text.contains("coverage is sufficient")
    } else {
      pass = !text.contains("coverage is sufficient") && !text.contains("Site Fully Covered") && text.contains("Upload CPT Data")
    }
    let report:[String:Any] = ["width":frame.width,"height":frame.height,"x":frame.minX,"y":frame.minY,"grabberVisible":sheet.prefersGrabberVisible,"nativeSheet":true,"fixtureCount":mode == "stop" ? 1 : 30,"mode":mode,"visibleText":text,"pass":pass]
    try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("\(run)-\(mode).json"))
  }
}
