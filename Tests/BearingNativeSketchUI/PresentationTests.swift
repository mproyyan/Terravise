import XCTest
import SwiftUI
import UIKit
import Vision
@testable import BearingPresentation

@MainActor final class PresentationTests: XCTestCase {
  let footer = "High uncertainty is concentrated in the southern sector, where CPT coverage is limited."
  private func text(_ image: UIImage) throws -> String {
    let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
  }
  private func render(_ main: String? = nil, _ area: String = "21.8%", footer: String? = nil) throws -> UIImage {
    let view = BearingRenderContent(shallowestDepthText: "7.3 m", deepestDepthText: "17.5 m",
      variationDepthText: "10.2 m", relativeUncertaintyText: main,
      highUncertaintyAreaPercentText: area, highUncertaintyDescription: footer)
    let renderer = ImageRenderer(content: view.frame(width: 400, height: 580)
      .background(Color(white: 0.975)).environment(\.colorScheme, .light))
    renderer.scale = 2
    return try XCTUnwrap(renderer.uiImage)
  }
  func testIdentificationCopyAndDynamicValues() throws {
    let image = try render("37.4%", "21.8%", footer: nil)
    let found = try text(image)
    XCTAssertGreaterThan(found.count, 150)
    for expected in ["Bearing Layer", "Depth Summary", "Prediction Uncertainty", "7.3 m", "17.5 m", "10.2 m", "37.4%", "21.8%", "High Uncertainty Area", "Bearing-layer identification uncertainty", "of total investigation area", "Shows uncertainty in bearing-layer identification."] {
      XCTAssertTrue(found.contains(expected), "Missing \(expected): \(found)")
    }
    for forbidden in ["Experimental", "P90", "GeoSyn", "Relative prediction uncertainty", "valid investigation", "southern", "±"] {
      XCTAssertFalse(found.contains(forbidden), found)
    }
    let attachment = XCTAttachment(image: image); attachment.name = "Current data availability — UI test depth and area values"; attachment.lifetime = .keepAlways; add(attachment)
    let updated = try text(render("64.2%", "8.7%"))
    XCTAssertTrue(updated.contains("64.2%"), updated)
    XCTAssertFalse(updated.contains("37.4%"), updated)
    XCTAssertTrue(updated.contains("8.7%"), updated)
    XCTAssertFalse(updated.contains("21.8%"), updated)
  }
  func testUnavailableIdentificationMetricAndLocationAreNotInvented() throws {
    let view = ResultBearingLayerSheetView()
    XCTAssertNil(view.relativeUncertaintyText)
    XCTAssertNil(view.highUncertaintyDescription)
    XCTAssertEqual(view.highUncertaintyAreaPercentText, "—")
    let found = try text(render())
    XCTAssertFalse(found.contains("0.0%"), found)
    XCTAssertFalse(found.contains("southern"), found)
    // Optional presentation inputs can display verified data; these are UI-only fixtures.
    let supplied = try text(render("37.4%", "21.8%", footer: footer))
    XCTAssertTrue(supplied.contains("37.4%"), supplied)
    XCTAssertFalse(supplied.contains("±"), supplied)
    XCTAssertTrue(supplied.contains("southern sector"), supplied)
  }
}
