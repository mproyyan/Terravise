import CryptoKit
import Foundation

/// Verifies implementation identity; the parity fixture is not a universal input validation.
enum CPTPipelineParityAttestation {
  private struct Envelope: Decodable { let format_version: Int; let valid: Bool; let manifest_sha256: String; let manifest: Data; let fixture: Data; let fingerprints: [String:String] }
  private struct Stage: Decodable { let status: String }
  private struct Scope: Decodable { let fixture_sha256: String; let shape_xyz: [Int]; let spacing_m: [Double]; let cpt_count: Int }
  private struct Manifest: Decodable { let format_version: Int; let overall_status: String; let files_unchanged_during_test: Bool; let fingerprints_before: [String:String]; let fingerprints_after: [String:String]; let stages: [String:Stage]; let scope: Scope }
  private struct Fixture: Decodable { let shape_xyz:[Int]; let spacing_m:[Double]; let valid_xy:[Bool]; let profiles:[Profile] }
  private struct Profile: Decodable { let x:Int; let y:Int; let rows:[Row] }
  private struct Row: Decodable { let depth_m:Double; let qc_mpa:Double; let fs_kpa:Double; let ic:Double }
  private static func hash(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
  /// Verifies build/model identity independently of any project's CPT state.
  /// This identifies the tested implementation; it does not establish parity for other inputs.
  static func implementationVerified(bundle:Bundle = .main) -> Bool {
    guard let url=bundle.url(forResource:"CPTParityAttestation",withExtension:"json"), let data=try? Data(contentsOf:url), let envelope=try? JSONDecoder().decode(Envelope.self,from:data), envelope.format_version==1, envelope.valid, hash(envelope.manifest)==envelope.manifest_sha256,
      let manifest=try? JSONDecoder().decode(Manifest.self,from:envelope.manifest), manifest.format_version==1, manifest.overall_status=="PASS", manifest.files_unchanged_during_test, manifest.fingerprints_before==manifest.fingerprints_after,
      ["SchemaGANParity","UncertaintyV3Parity","PipelineParity","V32Features","V32Classifier"].allSatisfy({ manifest.stages[$0]?.status == "PASS" }),
      Set(envelope.fingerprints.keys) == Set(["swift_schemgan","swift_uncertainty_and_features","swift_grid_mapping","swift_cpt_input","uncertainty_swift","classifier_swift","v32_feature_fixture","fixture","schema_package/Manifest.json","schema_package/Data/com.apple.CoreML/model.mlmodel","schema_package/Data/com.apple.CoreML/weights/weight.bin"]),
      envelope.fingerprints.allSatisfy({ manifest.fingerprints_before[$0.key] == $0.value }), hash(envelope.fixture)==manifest.scope.fixture_sha256 else { return false }
    for (name,key) in [("UncertaintyV3","uncertainty_swift"),("SufficiencyV3_2","classifier_swift")] {
      guard let url=bundle.url(forResource:name,withExtension:"json"), let bytes=try? Data(contentsOf:url), hash(bytes)==manifest.fingerprints_before[key] else { return false }
    }
    guard let model=bundle.url(forResource:"SchemaGAN_V4_2_Flexible",withExtension:"mlmodelc") else { return false }
    for path in ["metadata.json","model.mil","coremldata.bin","weights/weight.bin","analytics/coremldata.bin"] {
      guard let bytes=try? Data(contentsOf:model.appendingPathComponent(path)), hash(bytes)==manifest.fingerprints_before["compiled_model/"+path] else { return false }
    }
    return true
  }
  /// Runtime data and grid are validated separately; this checks implementation identity only.
  static func verified(points: [CPTPointEntry], grid: CPTGridConfig, bundle: Bundle = .main) -> Bool {
    implementationVerified(bundle: bundle)
  }
}
