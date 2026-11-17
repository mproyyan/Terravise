import Foundation

/// GeoSyn research model; scores are experimental and not foundation safety probabilities.
struct BearingUncertaintyV3Model: Decodable {
  typealias Node = BearingDepthUncertaintyModel.Node
  struct Forest: Decodable { let kind: String; let baseline: Double; let trees: [[Node]] }
  struct Calibrator: Decodable { let mean: [Double], scale: [Double], coef: [Double], intercept: Double }
  let version: String, featureCount: Int, icAlwaysEnabled: Bool, highRiskThreshold: Double
  let featureNames: [String]
  let match: Forest, miss: Forest, depth: Forest
  let matchCalibrator: Calibrator, missCalibrator: Calibrator
  enum CodingKeys: String, CodingKey {
    case version, match, miss, depth
    case featureCount = "feature_count", icAlwaysEnabled = "ic_always_enabled", highRiskThreshold = "high_risk_threshold"
    case featureNames = "feature_names", matchCalibrator = "match_calibrator", missCalibrator = "miss_calibrator"
  }
  static let expectedFeatures = BearingUncertaintyFlexibleV2.featureOrder + ["qc_min_mpa", "requested_thickness_m", "lateral_fraction", "dz_m", "effective_thickness_m", "ic_max", "predicted_ic_column_mean", "predicted_ic_column_min", "predicted_ic_fraction_le_max"]
  enum Failure: Error { case invalidContract, missingModel }
  static func load(bundle: Bundle = .main) throws -> Self {
    guard let url = bundle.url(forResource: "bearing_uncertainty_v3", withExtension: "json") else { throw Failure.missingModel }
    return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
  }
  func predict(_ features: [Double], cptCount: Int, qc: Double, ic: Double, thickness: Double) throws -> (match: Double, miss: Double, depth: Double) {
    guard version == "V3_STEP9B_RESEARCH", featureCount == 24, featureNames == Self.expectedFeatures,
          icAlwaysEnabled, highRiskThreshold == 0.2, features.count == 24,
          features.allSatisfy(\.isFinite), cptCount > 0, qc.isFinite, ic.isFinite, thickness.isFinite,
          match.kind == "classifier", miss.kind == "classifier", depth.kind == "regressor" else { throw Failure.invalidContract }
    func raw(_ forest: Forest) throws -> Double {
      try BearingDepthUncertaintyModel.evaluate(.init(baseline: forest.baseline, trees: forest.trees), features)
    }
    func sigmoid(_ x: Double) -> Double { x >= 0 ? 1 / (1 + exp(-x)) : exp(x) / (1 + exp(x)) }
    func calibrated(_ forest: Forest, _ c: Calibrator) throws -> Double {
      let p = min(max(sigmoid(try raw(forest)), 1e-6), 1 - 1e-6)
      let values = [log(p / (1-p)), log2(Double(cptCount)), qc, ic, thickness]
      guard c.mean.count == 5, c.scale.count == 5, c.coef.count == 5,
            c.scale.allSatisfy({ $0.isFinite && $0 > 0 }) else { throw Failure.invalidContract }
      let score = (0..<5).reduce(c.intercept) { $0 + (values[$1] - c.mean[$1]) / c.scale[$1] * c.coef[$1] }
      return sigmoid(score)
    }
    let result = (try calibrated(match, matchCalibrator), try calibrated(miss, missCalibrator), try raw(depth))
    guard result.0.isFinite, result.1.isFinite, result.2.isFinite else { throw Failure.invalidContract }
    return result
  }
}
