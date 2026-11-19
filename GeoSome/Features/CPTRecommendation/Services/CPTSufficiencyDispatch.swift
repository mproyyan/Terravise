import Foundation

/// Shared coordinator decision. The recommendation closure is evaluated only when STOP is not valid.
enum CPTSufficiencyDispatch {
  static func decide<Candidate>(project: Project?, points: [CPTPointEntry], grid: CPTGridConfig,
                                history: [CPTSufficiencyObservation], modelInputsValid: Bool,
                                recommend: () -> Candidate?) -> (candidate: Candidate?, stop: Bool, positives: Int, compatible: Bool) {
    let compatibility = CPTSufficiencyHistory.validate(project: project, points: points, grid: grid)
    let count = CPTSufficiencyHistory.consecutivePositive(history, threshold: UncertaintySufficiencyService.defaultThreshold)
    let stop = compatibility.permitsModelDecision && modelInputsValid && count >= UncertaintySufficiencyService.defaultPersistence
    return (stop ? nil : recommend(), stop, count, compatibility.permitsModelDecision)
  }
}
