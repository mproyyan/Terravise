from pathlib import Path
import sys
root=Path(__file__).resolve().parents[2]
vm=(root/'GeoSome/Features/Result/ViewModels/ResultAnalysisViewModel.swift').read_text()
start=vm.index('  private func updateBearingSummaryMetrics() {')
end=vm.index('\n  private func updateGeotechnicalConcernsAndSummary()', start)
method=vm[start:end].replace('private func updateBearingSummaryMetrics()', 'func updateBearingSummaryMetrics()', 1)
view=(root/'GeoSome/Features/Result/Views/ResultAnalysisView.swift').read_text()
start=view.index('relativeUncertaintyText: viewModel.bearingUncertaintyExperimentalInferenceReady')
end=view.index(',\n',start)
binding=view[start:end].split(': ',1)[1].replace('viewModel.', 'self.')
support='''import Foundation
// Test-only controlled model outcomes; no geologic observations or ML algorithm.
struct ProbeVolume {
  var id: String
  var meanRiskPercent: Double
  var highRiskAreaPercent: Double
  var fails = false
}
struct ProbeOutput {
  struct Summary { var shallowestTopDepthM: Double? = 7.3; var deepestBottomDepthM: Double? = 17.5 }
  var summary = Summary()
}
typealias BearingRuleOutput = ProbeOutput
enum ProbeQCFSResult { case coreML(ProbeVolume) }
enum ProbeBearingEvaluation { case candidateDetected(ProbeOutput), noCandidateDetected(ProbeOutput), unavailable }
struct BearingUncertaintyV3Model { static func load() throws -> Self { Self() } }
enum BearingUncertaintyV3Service {
  struct Result { let meanRiskPercent: Double, highRiskAreaPercent: Double, meanDepthM: Double? }
  enum Failure: Error { case unavailable }
  static func evaluate(volume: ProbeVolume, output: ProbeOutput, qcMinimum: Double,
      icMaximum: Double, thickness: Double, model: BearingUncertaintyV3Model) throws -> Result {
    if volume.fails { throw Failure.unavailable }
    return Result(meanRiskPercent: volume.meanRiskPercent,
      highRiskAreaPercent: volume.highRiskAreaPercent, meanDepthM: 0.9)
  }
}
@MainActor final class BearingSummaryProbe {
  var bearingUncertaintyExperimentalInferenceReady = false
  var relativeUncertaintyText = "—", highUncertaintyAreaPercentText = "—"
  var bearingDepthErrorBoundText = "Not available"
  var shallowestBearingDepthText = "—", deepestBearingDepthText = "—", variationBearingDepthText = "—"
  var highUncertaintyDescription = "", bearingStatusText = "Unavailable"
  var bearingRuleEvaluation: ProbeBearingEvaluation?
  var bearingIcFilterActive = true
  var qcfsResult: ProbeQCFSResult?
  var coneResistanceQc = 15.0, soilBehaviorIndexIc = 1.8, minLayerThickness = 2.0
'''
Path(sys.argv[1]).write_text(support+'\n  var displayedUncertainty: String? { '+binding+' }\n'+method+'\n}\n')
