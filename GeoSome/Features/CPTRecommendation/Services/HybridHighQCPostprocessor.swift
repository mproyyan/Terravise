import Foundation

/// Classification-only postprocessing for a calibrated 32-unique-CPT High-QC head.
/// The current QCFS_CNN_V3 Core ML export exposes residual qc/fs only, so this
/// component must not be called with its continuous qc output as `cnnScore`.
enum HybridHighQCPostprocessor {
  static let physicalThresholdMPa = 15.0
  static let alpha = 0.25
  static let temperatureMPa = 4.0
  static let cutoff = 0.5019683223200602

  enum CNNScore {
    case probability(Double)
    case logit(Double)
  }

  struct Classification {
    let cnnProbability: Double
    let idwProbability: Double
    let hybridProbability: Double
    let isHighQC: Bool
  }

  static func isCalibratedConfiguration(uniqueCPTCount: Int, qcThresholdMPa: Double) -> Bool {
    uniqueCPTCount == 32 && qcThresholdMPa == physicalThresholdMPa
  }

  static func classify(cnnScore: CNNScore, idwQCMPa: Double) -> Classification? {
    guard idwQCMPa.isFinite else { return nil }
    let cnnProbability: Double
    switch cnnScore {
    case .probability(let value):
      guard value.isFinite, (0...1).contains(value) else { return nil }
      cnnProbability = value // Already a probability: never apply sigmoid again.
    case .logit(let value):
      guard value.isFinite else { return nil }
      cnnProbability = sigmoid(value)
    }
    let idwProbability = sigmoid((idwQCMPa - physicalThresholdMPa) / temperatureMPa)
    let hybridProbability = alpha * cnnProbability + (1 - alpha) * idwProbability
    return Classification(
      cnnProbability: cnnProbability,
      idwProbability: idwProbability,
      hybridProbability: hybridProbability,
      isHighQC: hybridProbability >= cutoff
    )
  }

  private static func sigmoid(_ x: Double) -> Double {
    if x >= 0 { return 1 / (1 + exp(-x)) }
    let e = exp(x)
    return e / (1 + e)
  }
}
