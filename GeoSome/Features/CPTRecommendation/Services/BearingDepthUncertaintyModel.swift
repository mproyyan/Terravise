import Foundation

/// Experimental frozen estimator. Its output is not a site-wide confidence value.
struct BearingDepthUncertaintyModel: Decodable {
  struct Node: Decodable {
    let leaf: Bool, value: Double
    let feature: Int?, threshold: Double?, missingLeft: Bool?, left: Int?, right: Int?
    enum CodingKeys: String, CodingKey {
      case leaf, value, feature, threshold, left, right
      case missingLeft = "missing_left"
    }
  }
  struct Trees: Decodable { let baseline: Double; let trees: [[Node]] }
  struct Isotonic: Decodable {
    let xThresholds: [Double], yThresholds: [Double], outOfBounds: String
    enum CodingKeys: String, CodingKey {
      case xThresholds = "x_thresholds", yThresholds = "y_thresholds", outOfBounds = "out_of_bounds"
    }
  }
  struct Criteria: Decodable {
    let qcMinMPa: Double, minThicknessM: Double, minLateralFraction: Double, icFilterEnabled: Bool
    enum CodingKeys: String, CodingKey {
      case qcMinMPa = "qc_min_mpa", minThicknessM = "min_thickness_m"
      case minLateralFraction = "min_lateral_fraction", icFilterEnabled = "ic_filter_enabled"
    }
  }
  let version: Int, status: String, cptCount: Int, featureCount: Int
  let modelSelection: String
  let classifier: Trees, isotonic: Isotonic, depthRegressor: Trees
  let depthMarginM: Double
  let criteria: Criteria
  enum CodingKeys: String, CodingKey {
    case version, status, classifier, isotonic, criteria
    case cptCount = "cpt_count", featureCount = "feature_count", modelSelection = "model_selection"
    case depthRegressor = "depth_regressor", depthMarginM = "depth_margin_m"
  }
  enum Failure: Error { case invalidContract, invalidTree }

  static func load(count: Int, bundle: Bundle = .main) throws -> Self {
    guard [3, 8, 32].contains(count),
          let url = bundle.url(forResource: "bearing_uncertainty_cpt\(count)", withExtension: "json") else {
      throw Failure.invalidContract
    }
    return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
  }

  func predict(_ features: [Double]) throws -> (matchScore: Double, depthBoundM: Double) {
    guard version == 1, status == "EXPERIMENTAL", [3, 8, 32].contains(cptCount),
          featureCount == (cptCount == 32 ? 15 : 9), features.count == featureCount,
          features.allSatisfy({ $0.isFinite || $0.isNaN }), depthMarginM.isFinite,
          criteria.qcMinMPa == 15, criteria.minThicknessM == 2,
          criteria.minLateralFraction == 0.05, !criteria.icFilterEnabled else { throw Failure.invalidContract }
    let raw = try Self.evaluate(classifier, features)
    let probability = raw >= 0 ? 1 / (1 + exp(-raw)) : exp(raw) / (1 + exp(raw))
    let x = isotonic.xThresholds, y = isotonic.yThresholds
    guard isotonic.outOfBounds == "clip", !x.isEmpty, x.count == y.count,
          zip(x, x.dropFirst()).allSatisfy({ $0 < $1 }) else { throw Failure.invalidContract }
    var calibrated = y[0]
    if probability >= x[x.count - 1] { calibrated = y[y.count - 1] }
    else if probability > x[0] {
      var low = 0, high = x.count - 1
      while high - low > 1 {
        let middle = (low + high) / 2
        if x[middle] <= probability { low = middle } else { high = middle }
      }
      calibrated = y[low] + (probability - x[low]) * (y[high] - y[low]) / (x[high] - x[low])
    }
    return (calibrated, max(0, try Self.evaluate(depthRegressor, features)) + depthMarginM)
  }

  static func evaluate(_ model: Trees, _ features: [Double]) throws -> Double {
    var value = model.baseline
    for tree in model.trees {
      var index = 0, steps = 0
      while true {
        guard tree.indices.contains(index), steps <= tree.count else { throw Failure.invalidTree }
        let node = tree[index]
        if node.leaf { value += node.value; break }
        guard let feature = node.feature, features.indices.contains(feature),
              let threshold = node.threshold, let missing = node.missingLeft,
              let left = node.left, let right = node.right else { throw Failure.invalidTree }
        let v = features[feature]
        index = v.isNaN ? (missing ? left : right) : (v <= threshold ? left : right)
        steps += 1
      }
    }
    return value
  }
}
