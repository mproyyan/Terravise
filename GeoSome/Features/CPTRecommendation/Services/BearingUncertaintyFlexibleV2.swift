import Foundation

struct BearingUncertaintyFlexibleV2: Decodable {
  typealias Trees = BearingDepthUncertaintyModel.Trees
  typealias Isotonic = BearingDepthUncertaintyModel.Isotonic
  typealias Criteria = BearingDepthUncertaintyModel.Criteria
  static let featureOrder = ["log_nearest_cpt_m", "normalized_nearest_cpt_distance", "log2_cpt_count", "pred_candidate", "qc_max_mpa", "qc_mean_mpa", "qc_fraction_ge_12", "qc_fraction_ge_15", "qc_fraction_ge_18", "predicted_top_depth_m", "predicted_top_thickness_m", "predicted_interval_count", "predicted_second_interval_gap_m", "predicted_local_candidate_fraction", "predicted_vertical_candidate_fraction"]
  let version: Int, status: String, featureCount: Int
  let featureNames: [String], evaluatedCPTRange: [Int]
  let fixedCriteria: Criteria
  let matchClassifier: Trees, missClassifier: Trees, depthRegressor: Trees
  let matchIsotonic: Isotonic, missIsotonic: Isotonic
  let depthMarginM: Double
  enum CodingKeys: String, CodingKey {
    case version, status
    case featureCount = "feature_count", featureNames = "feature_names", evaluatedCPTRange = "evaluated_cpt_range"
    case fixedCriteria = "fixed_criteria", matchClassifier = "match_classifier", missClassifier = "miss_classifier"
    case depthRegressor = "depth_regressor", matchIsotonic = "match_isotonic", missIsotonic = "miss_isotonic", depthMarginM = "depth_margin_m"
  }
  enum Failure: Error { case invalidContract, missingModel }
  static func load(bundle: Bundle = .main) throws -> Self {
    guard let url = bundle.url(forResource: "bearing_uncertainty_v2_flexible", withExtension: "json") else { throw Failure.missingModel }
    return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
  }
  func predict(_ features: [Double]) throws -> (match: Double, miss: Double, depthM: Double) {
    guard version == 2, status == "EXPERIMENTAL", featureCount == 15, featureNames == Self.featureOrder,
          evaluatedCPTRange == [1,32], features.count == 15, features.allSatisfy(\.isFinite),
          fixedCriteria.qcMinMPa == 15, fixedCriteria.minThicknessM == 2,
          fixedCriteria.minLateralFraction == 0.05, !fixedCriteria.icFilterEnabled, depthMarginM.isFinite else { throw Failure.invalidContract }
    func probability(_ trees: Trees, _ calibration: Isotonic) throws -> Double {
      let raw = try BearingDepthUncertaintyModel.evaluate(trees, features)
      let p = raw >= 0 ? 1 / (1 + exp(-raw)) : exp(raw) / (1 + exp(raw))
      let x = calibration.xThresholds, y = calibration.yThresholds
      guard calibration.outOfBounds == "clip", !x.isEmpty, x.count == y.count,
            zip(x, x.dropFirst()).allSatisfy({ $0 < $1 }) else { throw Failure.invalidContract }
      if p <= x[0] { return y[0] }; if p >= x[x.count - 1] { return y[y.count - 1] }
      var lo = 0, hi = x.count - 1
      while hi - lo > 1 { let mid = (lo + hi) / 2; if x[mid] <= p { lo = mid } else { hi = mid } }
      return y[lo] + (p - x[lo]) * (y[hi] - y[lo]) / (x[hi] - x[lo])
    }
    let match = try probability(matchClassifier, matchIsotonic)
    let miss = try probability(missClassifier, missIsotonic)
    let depth = max(0, try BearingDepthUncertaintyModel.evaluate(depthRegressor, features)) + depthMarginM
    guard match.isFinite, miss.isFinite, depth.isFinite, depth >= 0 else { throw Failure.invalidContract }
    return (match, miss, depth)
  }
}
