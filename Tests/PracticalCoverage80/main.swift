import Foundation
struct Fixture:Decodable {
 let name:String;let frame:StratigraphicFrame;let recent:[StratigraphicTransition];let outcome:String;let reasons:[String]
}
@main struct PracticalParity {
 static func main() throws {
  let stream=try FileHandle(forReadingFrom:URL(fileURLWithPath:CommandLine.arguments[1]))
  var buffer=Data(),source="",previous:StratigraphicFrame?,history:StratigraphicEvidence?
  var states=0,stops=0,continues=0,historyChecks=0,firstStops:[String:Int]=[:],specialChecked=false
  func check(_ bytes:Data) throws {
   let q=try JSONDecoder().decode(Fixture.self,from:bytes)
   if source != q.name {source=q.name;previous=nil;history=nil}
   let f=q.frame,r=StratigraphicStop.evaluate(f,previous:previous,recent:q.recent,stateIndex:f.count-1)
   precondition(r.outcome.rawValue==q.outcome,"\(q.name)/\(f.count): \(r.outcome) vs \(q.outcome): \(r.reasons)")
   precondition(r.reasons==q.reasons,"reason mismatch \(q.name)/\(f.count): \(r.reasons) vs \(q.reasons)")
   var calls=0;let dispatched=StratigraphicStop.dispatch(r){calls+=1;return 42}
   precondition(calls==(r.outcome == .stop ? 0:1) && dispatched.stop==(r.outcome == .stop))
   if dispatched.stop {stops+=1;if firstStops[q.name]==nil {firstStops[q.name]=f.count}} else {continues+=1}
   let current=StratigraphicHistory.advance(frame:f,cptStateID:f.stateID,previousPrefixID:history?.cptStateID,contextID:source,implementationID:"practical-test",prior:history,acquisitionVerified:true)
   if previous != nil {precondition(current.decision.outcome==r.outcome && current.decision.reasons==r.reasons,"history divergence \(q.name)/\(f.count)");historyChecks+=1}
   else {precondition(current.decision.outcome == .undetermined && !current.decision.evidenceValid)}
   let saved=try JSONDecoder().decode(StratigraphicEvidence.self,from:JSONEncoder().encode(current))
   let reopened=StratigraphicHistory.advance(frame:f,cptStateID:f.stateID,previousPrefixID:nil,contextID:source,implementationID:"practical-test",prior:saved)
   precondition(reopened==saved,"reopen advanced or changed history")
   if !specialChecked,r.outcome == .stop,let old=history {
    specialChecked=true
    for (context,implementation,prior,verified) in [("changed","practical-test",old,true),(source,"changed",old,true),(source,"practical-test",old,false)] {
     let invalid=StratigraphicHistory.advance(frame:f,cptStateID:f.stateID,previousPrefixID:old.cptStateID,contextID:context,implementationID:implementation,prior:prior,acquisitionVerified:verified)
     precondition(invalid.decision.outcome == .undetermined && !StratigraphicStop.dispatch(invalid.decision){42}.stop)
    }
    var legacy=old;legacy.decision.contractID="strat-stop-witnessed-short-sequence-v3"
    let migrated=StratigraphicHistory.advance(frame:f,cptStateID:f.stateID,previousPrefixID:old.cptStateID,contextID:source,implementationID:"practical-test",prior:legacy,acquisitionVerified:true)
    precondition(migrated.decision.outcome == .undetermined)
    var legacyStop=r;legacyStop.contractID="strat-stop-witnessed-short-sequence-v3"
    precondition(!StratigraphicStop.dispatch(legacyStop){42}.stop)
    var changed=f;changed.predictedCoverage=0.0
    let changedEvidence=StratigraphicHistory.advance(frame:changed,cptStateID:f.stateID,previousPrefixID:nil,contextID:source,implementationID:"practical-test",prior:current)
    precondition(changedEvidence.decision.outcome == .undetermined)
    changed=f;changed.measured[old.frame.measured.firstIndex(where:{$0 != 255})!]=5
    let edited=StratigraphicHistory.advance(frame:changed,cptStateID:f.stateID,previousPrefixID:old.cptStateID,contextID:source,implementationID:"practical-test",prior:old,acquisitionVerified:true)
    precondition(edited.decision.outcome == .undetermined)
    var missing=f;missing.predictedCoverage=nil
    precondition(StratigraphicStop.evaluate(missing,previous:previous,recent:q.recent,stateIndex:f.count-1).outcome != .stop)
    missing=f;missing.predictedCoverage=0.8.nextDown
    precondition(StratigraphicStop.evaluate(missing,previous:previous,recent:q.recent,stateIndex:f.count-1).outcome != .stop)
    missing.predictedCoverage=0.8
    precondition(StratigraphicStop.evaluate(missing,previous:previous,recent:q.recent,stateIndex:f.count-1).outcome == .stop)
   }
   history=current;previous=f;states+=1
  }
  while let chunk=try stream.read(upToCount:1024*1024),!chunk.isEmpty {
   buffer.append(chunk)
   while let n=buffer.firstIndex(of:10) {let line=Data(buffer[..<n]);buffer.removeSubrange(...n);if !line.isEmpty {try check(line)}}
  }
  precondition(buffer.isEmpty && states==4489 && specialChecked)
  precondition(firstStops["actual26"]==3 && firstStops["01_undulating_05"]==3)
  // Exact first STOP map is also checked against Python output.
  let result:[String:Any]=["status":"PASS","states":states,"synthetic_sources":140,"history_checks":historyChecks,"STOP_dispatch":stops,"CONTINUE_dispatch":continues,"actual26_first_STOP":firstStops["actual26"]!,"known_undulating_failure_first_STOP":firstStops["01_undulating_05"]!,"first_stops":firstStops,"save_reopen_invalidation_migration":"PASS"]
  let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]);try data.write(to:URL(fileURLWithPath:CommandLine.arguments[2]));print("PRACTICAL PARITY PASS: \(states) states, reason codes exact, \(historyChecks) history checks; STOP dispatch \(stops), CONTINUE \(continues)")
 }
}
