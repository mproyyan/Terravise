import Foundation

/// Informational interpretation of the persisted stratigraphic decision.
/// This type has no authority over STOP, DQN, or the acquisition history.
struct StratigraphicCharacterization: Codable, Hashable, Sendable {
  enum ObservedStatus: String, Codable, Sendable {
    case sufficient = "SUFFICIENT"
    case insufficient = "INSUFFICIENT"
    case undetermined = "UNDETERMINED"
  }

  enum UnobservedRisk: String, Codable, Sendable {
    case notQuantified = "NOT_QUANTIFIED"
  }

  let observedCharacterizationStatus: ObservedStatus
  let unobservedGeologyRisk: UnobservedRisk
  let reasonCodes: [String]

  private enum CodingKeys: String, CodingKey {
    case observedCharacterizationStatus = "observed_characterization_status"
    case unobservedGeologyRisk = "unobserved_geology_risk"
    case reasonCodes = "reason_codes"
  }

  static func evaluate(
    _ decision: StratigraphicDecision?,
    evaluatedCPTCount: Int? = nil,
    currentCPTCount: Int? = nil
  ) -> Self {
    func result(_ status: ObservedStatus, _ reasons: [String]) -> Self {
      .init(observedCharacterizationStatus: status, unobservedGeologyRisk: .notQuantified, reasonCodes: reasons)
    }
    if let currentCPTCount, evaluatedCPTCount != currentCPTCount {
      return result(.undetermined, ["CURRENT_CPT_STATE_NOT_EVALUATED"])
    }
    guard let decision else { return result(.undetermined, ["CHARACTERIZATION_NOT_EVALUATED"]) }
    guard ["strat-stop-v1-primary", StratigraphicStop.policyID].contains(decision.contractID) else {
      return result(.undetermined, ["CHARACTERIZATION_EVALUATOR_UNSUPPORTED"])
    }
    let reasons = decision.reasons.isEmpty ? ["CHARACTERIZATION_EVIDENCE_UNAVAILABLE"] : decision.reasons
    guard decision.evidenceValid else {
      return result(.undetermined, (reasons == ["ALL_FROZEN_RESEARCH_CRITERIA_MET"] || reasons == ["AREA_SPREAD_STABILITY_AND_COVERAGE_ACCEPTABLE"])
        ? ["CHARACTERIZATION_EVIDENCE_UNAVAILABLE"] : reasons)
    }
    guard !decision.stateID.isEmpty, !decision.metrics.isEmpty, decision.metrics.values.allSatisfy(\.isFinite) else {
      return result(.undetermined, ["CHARACTERIZATION_EVIDENCE_UNAVAILABLE"])
    }
    // Missing qualifying history cannot become a characterization finding merely
    // because another current-state criterion returned CONTINUE.
    let missingQualification: Set<String> = [
      "TWO_DISTINCT_CONSECUTIVE_GENUINE_STATE_IDENTITIES_NOT_AVAILABLE", "RECENT_UPDATE_STATE_INVALID"
    ]
    if !missingQualification.isDisjoint(with: reasons) { return result(.undetermined, reasons) }
    switch decision.outcome {
    case .stop:
      // Trust the validated producer, never numeric confidence or a fresh rule.
      guard reasons == ["ALL_FROZEN_RESEARCH_CRITERIA_MET"] || (decision.contractID == StratigraphicStop.policyID && reasons == ["AREA_SPREAD_STABILITY_AND_COVERAGE_ACCEPTABLE"]) else {
        return result(.undetermined, ["CHARACTERIZATION_EVIDENCE_UNAVAILABLE"])
      }
      return result(.sufficient, reasons)
    case .continue:
      let failures: Set<String> = [
        "AREA_SPREAD_INSUFFICIENT", "LATEST_CPT_CHANGES_MAIN_STRATIGRAPHY", "LATEST_CPT_REVEALS_MATERIAL_PROFILE_MISMATCH", "PREDICTED_COVERAGE_BELOW_EXISTING_080_TARGET",
        "SPATIAL_OBSERVATION_GAP", "COHERENT_OR_WIDESPREAD_CLASS_AMBIGUITY", "UNRESOLVED_COHERENT_OR_WIDESPREAD_AMBIGUITY",
        "NEW_CPT_REVEALS_COHERENT_SBT_SEQUENCE_MISMATCH", "MAJOR_INFERRED_UNIT_WITHOUT_CPT_SUPPORT",
        "RECENT_COHERENT_RECONSTRUCTION_OR_BOUNDARY_REVISION"
      ]
      return result(failures.isDisjoint(with: reasons) ? .undetermined : .insufficient, reasons)
    case .undetermined:
      return result(.undetermined, reasons)
    }
  }

  var explanation: String {
    switch observedCharacterizationStatus {
    case .sufficient:
      "The current CPT evidence and reconstruction meet the active stratigraphic characterization criteria."
    case .insufficient:
      "The current evidence does not meet the active stratigraphic characterization criteria. This is not proof that another CPT is mandatory."
    case .undetermined:
      "Characterization cannot yet be determined from the available stratigraphic evidence."
    }
  }

  var reasonDescriptions: [String] {
    var seen = Set<String>()
    return reasonCodes.map { Self.descriptions[$0] ?? "The evaluator could not establish a supported characterization result." }
      .filter { seen.insert($0).inserted }
  }

  private static let descriptions: [String: String] = [
    "AREA_SPREAD_STABILITY_AND_COVERAGE_ACCEPTABLE": "Global CPT spread, the latest stable acquisition and Uncertainty V3 coverage meet preliminary exploratory criteria; this does not certify design sufficiency.",
    "AREA_SPREAD_INSUFFICIENT": "The CPT spread does not yet meet the global area support criterion.",
    "LATEST_CPT_CHANGES_MAIN_STRATIGRAPHY": "The latest CPT changes the main reconstructed layers, boundaries or continuity.",
    "LATEST_CPT_REVEALS_MATERIAL_PROFILE_MISMATCH": "The latest CPT differs materially from the preceding interpreted profile.",
    "PREDICTED_COVERAGE_BELOW_EXISTING_080_TARGET": "Uncertainty V3 coverage is below the exploratory policy target; this is not a probability of geological error.",
    "VALID_COVERAGE_UNAVAILABLE": "Current coverage evidence is missing or inconsistent.",
    "GENUINE_CURRENT_CONFIRMATION_UNAVAILABLE": "A genuine current acquisition transition is unavailable.",
    "SHORT_ALTERNATIVE_SEQUENCES_SPATIALLY_WITNESSED": "Both short SBT patterns have measured CPT support; residual ambiguity and the remaining STOP criteria pass.",
    "UNRESOLVED_COHERENT_OR_WIDESPREAD_AMBIGUITY": "Unresolved SBT class ambiguity remains widespread or spatially coherent.",
    "UNRESOLVED_AMBIGUITY_INDETERMINATE_BAND": "Unresolved SBT ambiguity remains within the indeterminate range.",
    "TWO_GENUINE_STABLE_TRANSITIONS_REQUIRED": "Two qualifying genuine CPT updates are not available for this assessment.",
    "NUMERIC_INTERVAL_EVIDENCE_INVALID": "Numeric reconstruction and uncertainty evidence is missing or invalid.",
    "NUMERIC_CLASS_OR_AMBIGUITY_MISMATCH": "Numeric reconstruction and uncertainty do not match the saved classes or masks.",
    "ALL_FROZEN_RESEARCH_CRITERIA_MET": "Spatial support, represented SBT units, ambiguity and genuine-update stability meet the V1 research criteria.",
    "SPATIAL_OBSERVATION_GAP": "Some parts of the valid project area lack sufficient nearby CPT support.",
    "COHERENT_OR_WIDESPREAD_CLASS_AMBIGUITY": "SBT class ambiguity remains widespread or spatially coherent.",
    "NEW_CPT_REVEALS_COHERENT_SBT_SEQUENCE_MISMATCH": "A newly observed CPT disagrees with the previously predicted SBT sequence across consecutive depths.",
    "MAJOR_INFERRED_UNIT_WITHOUT_CPT_SUPPORT": "A reconstructed major SBT unit lacks supporting CPT observations.",
    "RECENT_COHERENT_RECONSTRUCTION_OR_BOUNDARY_REVISION": "Recent genuine CPT updates still change reconstructed units or layer boundaries.",
    "SINGLE_DEPTH_CELL_PROFILE_MISMATCH_INDETERMINATE": "A single-depth-cell SBT discrepancy remains unresolved.",
    "TWO_DISTINCT_CONSECUTIVE_GENUINE_STATE_IDENTITIES_NOT_AVAILABLE": "Two qualifying genuine CPT updates are not available for this assessment.",
    "RECENT_UPDATE_STATE_INVALID": "The recent CPT update sequence could not be verified.",
    "SPATIAL_SUPPORT_INDETERMINATE_BAND": "Spatial CPT support is within V1's indeterminate range.",
    "AMBIGUITY_INDETERMINATE_BAND": "SBT ambiguity is within V1's indeterminate range.",
    "GENUINE_PREDECESSOR_UNAVAILABLE": "A compatible, genuinely observed predecessor state is not available.",
    "CHARACTERIZATION_NOT_EVALUATED": "No stratigraphic characterization has been evaluated for this result.",
    "CURRENT_CPT_STATE_NOT_EVALUATED": "The CPT data changed; a matching assessment is not yet available.",
    "CHARACTERIZATION_EVALUATOR_UNSUPPORTED": "This saved result does not identify a supported stratigraphic evaluator.",
    "CHARACTERIZATION_EVIDENCE_UNAVAILABLE": "The evaluator evidence is missing or incomplete.",
    "IMPLEMENTATION_OR_PROJECT_EVIDENCE_UNAVAILABLE": "Verified evaluator or project evidence is unavailable.",
    "PROJECT_STATE_MISMATCH": "The assessment does not match the current project data.",
    "INVALID_PROJECT_POLYGON": "A valid project investigation boundary is unavailable.",
    "INVALID_OR_FALLBACK_RECONSTRUCTION_OR_UNCERTAINTY": "Supported reconstruction and uncertainty outputs are unavailable.",
    "CPT_CELL_COLLISION_OR_MAPPING_MISMATCH": "CPT locations could not be aligned consistently with the reconstruction grid.",
    "CPT_STATE_ID_UNAVAILABLE": "The current CPT state could not be verified.",
    "VOLUME_SHAPE_MISMATCH": "Reconstruction and uncertainty volumes do not share a valid grid.",
    "NONFINITE_OR_MASK_INVALID_EVIDENCE": "Reconstruction values or valid/observed masks are invalid.",
    "PARTIAL_DEPTH_OBSERVATION_UNVERIFIED": "CPT depth coverage is outside the supported evaluation contract.",
    "MASK_OR_CLASS_MISMATCH": "SBT classes and valid observation masks do not align.",
    "INVALID_OR_EMPTY_DOMAIN": "A valid nonempty investigation domain is unavailable.",
    "GRID_MISMATCH": "The current and previous observations use incompatible grids.",
    "INVALID_DISTANCE_MAP": "Physical CPT support distances could not be evaluated."
  ]
}
