import Foundation

/// Recorded only by submitCPTUpload, never inferred from matching coordinates or counts.
struct StratigraphicAcquisition: Codable, Hashable, Sendable {
  let cptID: UUID
  let before: String
  let after: String
}

/// One previous classified snapshot plus the two latest genuine transition summaries.
/// Absent on legacy projects; imported snapshots start a new history with index zero.
struct StratigraphicEvidence: Codable, Hashable, Sendable {
  var version: Int = 1
  var implementationID: String
  var contextID: String
  var cptStateID: String
  var frame: StratigraphicFrame
  var stateIndex: Int
  var recent: [StratigraphicTransition]
  var decision: StratigraphicDecision
}

enum StratigraphicHistory {
  static func advance(frame: StratigraphicFrame, cptStateID: String, previousPrefixID: String?,
                      contextID: String, implementationID: String, prior: StratigraphicEvidence?, acquisitionVerified: Bool = false) -> StratigraphicEvidence {
    var index=0; var recent:[StratigraphicTransition]=[]; var previous:StratigraphicFrame?
    if let old=prior, old.version==1, old.decision.contractID==StratigraphicStop.policyID, old.implementationID==implementationID, old.contextID==contextID,
       StratigraphicStop.compatible(old.frame,frame) {
      if old.cptStateID==cptStateID && old.frame==frame { return old }
      if acquisitionVerified && old.cptStateID==previousPrefixID && frame.count==old.frame.count+1 &&
          frame.sites.dropLast().elementsEqual(old.frame.sites,by:==),
          let transition=StratigraphicStop.transition(old.frame,frame) {
        // Previously measured profiles must be unchanged; only the new CPT may extend observation support.
        let preserved=old.frame.measured.indices.allSatisfy { old.frame.measured[$0]==255 || old.frame.measured[$0]==frame.measured[$0] }
        if preserved { index=old.stateIndex+1; recent=Array((old.recent+[transition]).suffix(2)); previous=old.frame }
      }
    }
    let decision=StratigraphicStop.evaluate(frame,previous:previous,recent:recent,stateIndex:index)
    // Missing genuine predecessors must remain UNDETERMINED even if a current ambiguity would normally justify CONTINUE.
    let result = previous==nil ? StratigraphicDecision.unavailable("GENUINE_PREDECESSOR_UNAVAILABLE",stateID:frame.stateID) : decision
    return .init(implementationID:implementationID,contextID:contextID,cptStateID:cptStateID,frame:frame,stateIndex:index,recent:recent,decision:result)
  }
}
