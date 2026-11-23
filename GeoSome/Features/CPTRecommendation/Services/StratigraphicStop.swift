import Foundation

/// Frozen research contract. Arrays are XYZ, z-fastest. SBT 255 means invalid/unobserved.
struct StratigraphicFrame: Codable, Hashable, Sendable {
  var nx: Int; var ny: Int; var nz: Int
  var dx: Double; var dy: Double; var dz: Double; var area: Double
  var valid: [Bool]; var classes: [UInt8]; var measured: [UInt8]; var ambiguity: [Bool]
  var sites: [[Int]]
  var stateID: String
  var count: Int
  // Same-snapshot numeric evidence; absent in legacy saved frames.
  var predictedIc: [Double]? = nil
  var halfWidthIc: [Double]? = nil
  // Direct current Uncertainty V3 output; optional for legacy Codable frames.
  var predictedCoverage: Double? = nil
  var size: Int { nx * ny * nz }
  func index(_ x: Int, _ y: Int, _ z: Int) -> Int { (x * ny + y) * nz + z }
}

struct StratigraphicTransition: Codable, Hashable, Sendable {
  var from: String; var to: String
  var coherentRevision: Bool
  var changedVoxels: Int
  var coherentChangedComponents: Int
  var coherentBoundaryComponents: Int
  var majorContinuityChanges: Int
  var boundaryP90M: Double
  var boundaryMaxShiftCells: Int
}

struct StratigraphicDecision: Codable, Hashable, Sendable {
  enum Outcome: String, Codable, Sendable {
    case stop = "STOP", `continue` = "CONTINUE", undetermined = "UNDETERMINED"
    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer(), value = try container.decode(String.self)
      // Read historical decisions without rewriting saved projects.
      if value == "STOP_CANDIDATE" { self = .stop }
      else if let outcome = Self(rawValue: value) { self = outcome }
      else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown stratigraphic outcome") }
    }
  }
  var outcome: Outcome
  var reasons: [String]
  var stateID: String
  var metrics: [String: Double]
  var evidenceValid: Bool
  var contractID: String = StratigraphicStop.policyID
  var uiStatus: String { outcome == .stop ? "STOP CANDIDATE" : "CONTINUE" }
  static func unavailable(_ reason: String, stateID: String = "") -> Self {
    .init(outcome: .undetermined, reasons: [reason], stateID: stateID, metrics: [:], evidenceValid: false)
  }
}

enum StratigraphicStop {
  static let policyID = "practical-dynamic-stop-research-1"
  static func dispatch<Candidate>(_ result: StratigraphicDecision, recommend: () -> Candidate?) -> (candidate: Candidate?, stop: Bool) {
    let stop=result.outcome == .stop && result.evidenceValid && result.contractID == policyID
    return (stop ? nil : recommend(),stop)
  }
  static let contractHash = "6dae1dd778d5fd1c8da21556e88323f2c37b25584141624729de4457f1329c0b"
  static let configHash = "5656c8ba2c2e7caff27982075e5bbf68de72bdd36ef9027980b33870ece78138"
  static let cuts = [1.31, 2.05, 2.60, 2.95, 3.60]
  static func band(_ ic: Double) -> UInt8 { UInt8(cuts.filter { ic >= $0 }.count) }
  struct Component { var cells: [Int]; var low: [Int]; var high: [Int]
    var coherent: Bool { cells.count >= 8 && zip(low, high).allSatisfy { $1 - $0 + 1 >= 2 } }
  }
  static func components(_ mask: [Bool], nx: Int, ny: Int, nz: Int) -> [Component] {
    var seen = Array(repeating: false, count: mask.count); var result: [Component] = []
    for start in mask.indices where mask[start] && !seen[start] {
      var queue = [start]; seen[start] = true; var head = 0
      var lo = [nx,ny,nz], hi = [0,0,0]
      while head < queue.count {
        let i = queue[head]; head += 1
        let x = i / (ny*nz), y = (i/nz)%ny, z = i%nz
        for (a,v) in [x,y,z].enumerated() { lo[a] = min(lo[a],v); hi[a] = max(hi[a],v) }
        var neighbors: [Int] = []
        if x>0 { neighbors.append(i-ny*nz) }; if x+1<nx { neighbors.append(i+ny*nz) }
        if y>0 { neighbors.append(i-nz) }; if y+1<ny { neighbors.append(i+nz) }
        if z>0 { neighbors.append(i-1) }; if z+1<nz { neighbors.append(i+1) }
        for j in neighbors where mask[j] && !seen[j] { seen[j]=true; queue.append(j) }
      }
      result.append(.init(cells: queue, low: lo, high: hi))
    }
    return result
  }
  /// NumPy's default quantile: linear interpolation at (n-1)*q.
  static func quantile(_ values: [Double], _ q: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let v = values.sorted(), p = Double(values.count-1)*q, a = Int(floor(p)), b = Int(ceil(p))
    return v[a] + (v[b]-v[a])*(p-Double(a))
  }
  static func compatible(_ a: StratigraphicFrame, _ b: StratigraphicFrame) -> Bool {
    a.nx==b.nx && a.ny==b.ny && a.nz==b.nz && a.dx==b.dx && a.dy==b.dy && a.dz==b.dz && a.area==b.area && a.valid==b.valid
  }
  static func valid(_ f: StratigraphicFrame) -> Bool {
    guard f.nx>0, f.ny>0, f.nz>0, [f.dx,f.dy,f.dz,f.area].allSatisfy({ $0.isFinite && $0>0 }),
      f.valid.count==f.size, f.classes.count==f.size, f.measured.count==f.size, f.ambiguity.count==f.size,
      f.count>0, f.sites.count==f.count, Set(f.sites.map { "\($0)" }).count==f.count else { return false }
    for i in 0..<f.size {
      if f.valid[i] { if f.classes[i]>5 { return false } }
      else if f.classes[i] != 255 || f.measured[i] != 255 || f.ambiguity[i] { return false }
      if f.measured[i] != 255 && (f.measured[i]>5 || f.ambiguity[i]) { return false }
    }
    return f.sites.allSatisfy { $0.count==2 && (0..<f.nx).contains($0[0]) && (0..<f.ny).contains($0[1]) }
  }
  static func transition(_ previous: StratigraphicFrame, _ f: StratigraphicFrame) -> StratigraphicTransition? {
    guard valid(previous), valid(f), compatible(previous,f) else { return nil }
    let changed = (0..<f.size).map { f.valid[$0] && f.measured[$0]==255 && previous.classes[$0] != f.classes[$0] }
    let cc = components(changed,nx:f.nx,ny:f.ny,nz:f.nz).filter(\.coherent).count
    var majorChanges = 0
    for band in UInt8(0)...UInt8(5) {
      let before = (0..<f.size).map { f.valid[$0] && previous.classes[$0]==band }
      let after = (0..<f.size).map { f.valid[$0] && f.classes[$0]==band }
      if components(before,nx:f.nx,ny:f.ny,nz:f.nz).filter(\.coherent).count != components(after,nx:f.nx,ny:f.ny,nz:f.nz).filter(\.coherent).count { majorChanges += 1 }
    }
    var shifted = Array(repeating:false,count:f.nx*f.ny), shifts:[Double]=[], maxShift=0
    for x in 0..<f.nx { for y in 0..<f.ny {
      var before:[Int:[Int]]=[:],after:[Int:[Int]]=[:]
      if f.nz>1 { for z in 0..<(f.nz-1) {
        let i=f.index(x,y,z)
        guard f.valid[i] && f.valid[i+1] else { continue }
        if previous.classes[i] != previous.classes[i+1] { before[Int(previous.classes[i])*6+Int(previous.classes[i+1]),default:[]].append(z) }
        if f.classes[i] != f.classes[i+1] { after[Int(f.classes[i])*6+Int(f.classes[i+1]),default:[]].append(z) }
      } }
      for code in before.keys.sorted() {
        var remaining = after[code] ?? []
        for old in before[code]! {
          guard let new=remaining.min(by: { abs($0-old)==abs($1-old) ? $0<$1 : abs($0-old)<abs($1-old) }) else { break }
          remaining.removeAll { $0==new }; let delta=abs(new-old)
          shifts.append(Double(delta)*f.dz); maxShift=max(maxShift,delta)
          if delta>=2 { shifted[x*f.ny+y]=true }
        }
      }
    } }
    let bc = components(shifted,nx:f.nx,ny:f.ny,nz:1).filter { $0.cells.count>=4 && $0.high[0]-$0.low[0]+1>=2 && $0.high[1]-$0.low[1]+1>=2 }.count
    return .init(from:previous.stateID,to:f.stateID,coherentRevision:cc>0 || bc>0 || majorChanges>0,changedVoxels:changed.filter{$0}.count,coherentChangedComponents:cc,coherentBoundaryComponents:bc,majorContinuityChanges:majorChanges,boundaryP90M:quantile(shifts,0.9),boundaryMaxShiftCells:maxShift)
  }
  /// Literal three-condition Practical STOP, for early exploratory investigation.
  /// Uncertainty coverage is consumed from the existing service, never a risk probability.
  static func evaluate(_ f: StratigraphicFrame, previous: StratigraphicFrame?, recent: [StratigraphicTransition], stateIndex: Int) -> StratigraphicDecision {
    guard valid(f) else { return .unavailable("INVALID_OR_EMPTY_DOMAIN",stateID:f.stateID) }
    let hidden=(0..<f.size).filter { f.valid[$0] && f.measured[$0]==255 }
    var metrics:[String:Double]=["hidden_valid_voxels":Double(hidden.count)]
    if let coverage=f.predictedCoverage,coverage.isFinite { metrics["predicted_coverage"]=coverage }
    func result(_ reason:String, stop:Bool=false) -> StratigraphicDecision {
      .init(outcome:stop ? .stop : .continue,reasons:[reason],stateID:f.stateID,metrics:metrics,evidenceValid:true)
    }
    var distances:[Double]=[]
    for x in 0..<f.nx { for y in 0..<f.ny where (0..<f.nz).contains(where:{ f.valid[f.index(x,y,$0)] }) {
      distances.append(Double(Float(f.sites.map { hypot(Double(x-$0[0])*f.dx,Double(y-$0[1])*f.dy) }.min()!)))
    } }
    guard !distances.isEmpty else { return .unavailable("INVALID_DISTANCE_MAP",stateID:f.stateID) }
    let pitch=sqrt(f.area/Double(f.count)),diagonal=sqrt(2.0)*pitch
    let p95=quantile(distances,0.95)/diagonal,maximum=distances.max()!/diagonal
    metrics["spatial_pitch_m"]=pitch;metrics["ideal_equal_area_cell_diagonal_m"]=diagonal
    metrics["spatial_support_p95_ratio"]=p95;metrics["spatial_support_max_ratio"]=maximum
    // 1. Global area spread, with unchanged physical support limits.
    guard p95<=1 && maximum<=1.75 else { return result("AREA_SPREAD_INSUFFICIENT") }
    // 2. Exactly one genuine confirming addition. Legacy/reopened states do not
    // create acquisition evidence; History verifies the original upload chain.
    guard let previous,valid(previous),compatible(previous,f),previous.count+1==f.count,
      previous.stateID != f.stateID,previous.sites==Array(f.sites.dropLast()) else {
      return result("GENUINE_CURRENT_CONFIRMATION_UNAVAILABLE")
    }
    guard (0..<f.size).allSatisfy({previous.measured[$0]==255 || previous.measured[$0]==f.measured[$0]}) else {
      return result("PREVIOUS_OBSERVATIONS_EDITED")
    }
    guard let site=f.sites.last,!f.sites.dropLast().contains(site) else { return result("REPEATED_LOCATION_NOT_CONFIRMATION") }
    guard let last=recent.last,last.from==previous.stateID,last.to==f.stateID else {
      return result("GENUINE_CURRENT_CONFIRMATION_UNAVAILABLE")
    }
    guard !last.coherentRevision else { return result("LATEST_CPT_CHANGES_MAIN_STRATIGRAPHY") }
    var run=0,maxRun=0
    for z in 0..<f.nz {
      let i=f.index(site[0],site[1],z)
      if f.valid[i] && f.measured[i] != 255 && previous.classes[i] != f.measured[i] { run+=1;maxRun=max(maxRun,run) } else { run=0 }
    }
    metrics["max_new_profile_mismatch_run_voxels"]=Double(maxRun)
    guard maxRun<2 else { return result("LATEST_CPT_REVEALS_MATERIAL_PROFILE_MISMATCH") }
    // 3. The existing research coverage target, without ambiguity or unit vetoes.
    guard let coverage=f.predictedCoverage,coverage.isFinite,(0...1).contains(coverage),!hidden.isEmpty else {
      return result("VALID_COVERAGE_UNAVAILABLE")
    }
    guard coverage>=0.80 else { return result("PREDICTED_COVERAGE_BELOW_EXISTING_080_TARGET") }
    return result("AREA_SPREAD_STABILITY_AND_COVERAGE_ACCEPTABLE",stop:true)
  }
}
