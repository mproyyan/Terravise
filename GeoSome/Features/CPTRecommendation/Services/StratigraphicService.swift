import CryptoKit
import Foundation

/// Adapt existing inference outputs without a second inference or synthetic predecessor replay.
enum StratigraphicService {
  static func hash(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
  static func canonical<T: Encodable>(_ value:T) -> Data { let e=JSONEncoder();e.outputFormatting=[.sortedKeys];return try! e.encode(value) }
  private struct ReconstructionIdentity: Encodable {
    let frame: StratigraphicFrame
    let predicted: [[[Double]]]
    let observed: [[[Double]]]
    let bounds: [[[Double]]]
  }
  struct Identity: Decodable { let sources: [String:String]; let resources: [String:String] }
  static let implementationID: String? = {
    guard let u=Bundle.main.url(forResource:"StratigraphicImplementationIdentity",withExtension:"json"),let bytes=try? Data(contentsOf:u),let id=try? JSONDecoder().decode(Identity.self,from:bytes),
      let cfg=Bundle.main.url(forResource:"StratigraphicStopConfig",withExtension:"json"),let cb=try? Data(contentsOf:cfg),hash(cb)==StratigraphicStop.configHash,
      let contract=Bundle.main.url(forResource:"StratigraphicStopContract",withExtension:"md"),let mb=try? Data(contentsOf:contract),hash(mb)==StratigraphicStop.contractHash,
      let model=Bundle.main.url(forResource:"SchemaGAN_V4_2_Flexible",withExtension:"mlmodelc"),!id.sources.isEmpty,!id.resources.isEmpty else { return nil }
    for (path,digest) in id.resources {
      let url:URL?
      if path.hasPrefix("schema/") { url=model.appendingPathComponent(String(path.dropFirst(7))) }
      else { url=Bundle.main.url(forResource:path,withExtension:nil) }
      guard let url,let data=try? Data(contentsOf:url),hash(data)==digest else { return nil }
    }
    return hash(bytes)
  }()
  static func assess(project: Project?, points:[CPTPointEntry], grid:CPTGridConfig,
                     reconstruction:SchemaGANReconstructionOutput, uncertainty:UncertaintySufficiencyEvaluation) -> (StratigraphicDecision,StratigraphicEvidence?) {
    guard let project, let implementationID else { return (.unavailable("IMPLEMENTATION_OR_PROJECT_EVIDENCE_UNAVAILABLE"),nil) }
    guard CPTSufficiencyHistory.stateID(projectID:project.id,gridPolicy:project.gridPolicy,distancePolicy:project.cptDistancePolicy,boundary:project.boundaryPoints,points:project.cptPoints) == CPTSufficiencyHistory.stateID(projectID:project.id,gridPolicy:project.gridPolicy,distancePolicy:project.cptDistancePolicy,boundary:project.boundaryPoints,points:points) else { return (.unavailable("PROJECT_STATE_MISMATCH"),nil) }
    guard grid.hasValidBoundary(project.boundaryCoordinates) else { return (.unavailable("INVALID_PROJECT_POLYGON"),nil) }
    guard reconstruction.inferenceSource=="SchemaGAN V4.2 Flexible Core ML", uncertainty.spatialEvidenceValid,
      let bounds=uncertainty.spatialBounds, reconstruction.grid.hasSamePhysicalGrid(as:grid),grid.siteAreaM2>0 else { return (.unavailable("INVALID_OR_FALLBACK_RECONSTRUCTION_OR_UNCERTAINTY"),nil) }
    let sites=reconstruction.observedSitesXY
    guard points.count==sites.count,points.enumerated().allSatisfy({ i,p in
      let raw=grid.gridIndices(for:p.coordinate)
      return grid.contains(p.coordinate,in:project.boundaryCoordinates) && raw.ix==sites[i].ix && raw.iy==sites[i].iy
    }) else { return (.unavailable("CPT_CELL_COLLISION_OR_MAPPING_MISMATCH"),nil) }
    guard let cptID=CPTSufficiencyHistory.stateID(projectID:project.id,gridPolicy:project.gridPolicy,distancePolicy:project.cptDistancePolicy,boundary:project.boundaryPoints,points:points) else { return (.unavailable("CPT_STATE_ID_UNAVAILABLE"),nil) }
    let prefix=CPTSufficiencyHistory.stateID(projectID:project.id,gridPolicy:project.gridPolicy,distancePolicy:project.cptDistancePolicy,boundary:project.boundaryPoints,points:Array(points.dropLast()))
    let shape=[grid.nx,grid.ny,grid.nz]
    guard [reconstruction.reconstructedIc,reconstruction.observedIc,bounds].allSatisfy({ a in a.count==shape[0] && a.allSatisfy{$0.count==shape[1] && $0.allSatisfy{$0.count==shape[2]}} }),
      [reconstruction.validMask,reconstruction.observedMask].allSatisfy({a in a.count==shape[0] && a.allSatisfy{$0.count==shape[1] && $0.allSatisfy{$0.count==shape[2]}}}) else { return (.unavailable("VOLUME_SHAPE_MISMATCH"),nil) }
    var valid:[Bool]=[],classes:[UInt8]=[],measured:[UInt8]=[],ambiguity:[Bool]=[]
    for x in 0..<grid.nx { for y in 0..<grid.ny { for z in 0..<grid.nz {
      let v=reconstruction.validMask[x][y][z],o=reconstruction.observedMask[x][y][z]
      let p=reconstruction.reconstructedIc[x][y][z],m=reconstruction.observedIc[x][y][z],b=bounds[x][y][z]
      guard v==grid.validXYMask[x][y],!o || v,!v || p.isFinite,!o || m.isFinite,!o || abs(p-m)<=1e-6,
        !v || o || (b.isFinite && b>=0) else { return (.unavailable("NONFINITE_OR_MASK_INVALID_EVIDENCE"),nil) }
      valid.append(v);classes.append(v ? StratigraphicStop.band(p):255);measured.append(o ? StratigraphicStop.band(m):255)
      ambiguity.append(v && !o && StratigraphicStop.cuts.contains { p-b <= $0 && p+b >= $0 })
    } } }
    // Consume the existing scalar. Count its calibrated hidden bounds only to
    // validate domain/value consistency; do not replace or recalculate uncertainty.
    let hiddenIndices=valid.indices.filter { valid[$0] && measured[$0]==255 }
    let flatBounds=bounds.flatMap{$0.flatMap{$0}}
    guard !hiddenIndices.isEmpty,uncertainty.predictedCoverage.isFinite,
      (0...1).contains(uncertainty.predictedCoverage),
      abs(uncertainty.predictedCoverage - Double(hiddenIndices.filter{flatBounds[$0]<=0.15}.count)/Double(hiddenIndices.count))<=1e-12 else {
      return (.unavailable("COVERAGE_DOMAIN_OR_VALUE_MISMATCH"),nil)
    }
    // The frozen acquisition pipeline observes full-depth profiles; partial profiles are outside its demonstrated contract.
    guard sites.allSatisfy({s in (0..<grid.nz).allSatisfy{ reconstruction.observedMask[s.ix][s.iy][$0] }}) else { return (.unavailable("PARTIAL_DEPTH_OBSERVATION_UNVERIFIED"),nil) }
    let context=hash(canonical([String(grid.nx),String(grid.ny),String(grid.nz),String(grid.dxM),String(grid.dyM),String(grid.dzM),String(grid.originLatitude),String(grid.originLongitude),String(grid.siteAreaM2),implementationID]))
    var frame=StratigraphicFrame(nx:grid.nx,ny:grid.ny,nz:grid.nz,dx:grid.dxM,dy:grid.dyM,dz:grid.dzM,area:grid.siteAreaM2,valid:valid,classes:classes,measured:measured,ambiguity:ambiguity,sites:sites.map{[$0.ix,$0.iy]},stateID:cptID,count:points.count,predictedIc:reconstruction.reconstructedIc.flatMap{$0.flatMap{$0}},halfWidthIc:flatBounds,predictedCoverage:uncertainty.predictedCoverage)
    // Bind immutable state to both measured input and actual model outputs.
    frame.stateID=hash(canonical(ReconstructionIdentity(frame:frame,predicted:reconstruction.reconstructedIc,observed:reconstruction.observedIc,bounds:bounds)))
    let evidence=StratigraphicHistory.advance(frame:frame,cptStateID:cptID,previousPrefixID:prefix,contextID:context,implementationID:implementationID,prior:project.stratigraphicEvidence,acquisitionVerified:project.stratigraphicAcquisitions.contains { $0.cptID==points.last?.id && $0.before==prefix && $0.after==cptID })
    return (evidence.decision,evidence)
  }
}
