import Foundation

private struct Fixture: Decodable {
  struct Expected: Decodable { let match: Double, miss: Double, depth: Double }
  let features: [Double], cptCount: Int, criteria: [Double], expected: Expected
  enum CodingKeys: String, CodingKey { case features, criteria, expected; case cptCount = "cpt_count" }
}
@main enum ModelContractTests {
  static func main() throws {
    let model = try JSONDecoder().decode(BearingUncertaintyV3Model.self,
      from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
    let fixtures = try JSONDecoder().decode([Fixture].self,
      from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
    precondition(fixtures.count == 288)
    var errors = [Double](repeating: 0, count: 3)
    for f in fixtures {
      let result = try model.predict(f.features, cptCount: f.cptCount, qc: f.criteria[0], ic: f.criteria[1], thickness: f.criteria[2])
      for (i,pair) in zip([result.match,result.miss,result.depth],[f.expected.match,f.expected.miss,f.expected.depth]).enumerated() {
        precondition(pair.0.isFinite)
        errors[i] = max(errors[i],abs(pair.0-pair.1))
      }
    }
    precondition(errors.allSatisfy { $0 <= 1e-6 })
    let f = fixtures[0]
    var rejected = 0
    func mustReject(_ features: [Double], count: Int? = nil, qc: Double? = nil, ic: Double? = nil, thickness: Double? = nil) {
      do {
        _ = try model.predict(features,cptCount:count ?? f.cptCount,qc:qc ?? f.criteria[0],ic:ic ?? f.criteria[1],thickness:thickness ?? f.criteria[2])
        preconditionFailure("Invalid input unexpectedly accepted")
      } catch { rejected += 1 }
    }
    mustReject(Array(f.features.dropLast()))
    for value in [Double.nan, Double.infinity, -Double.infinity] {
      var features = f.features; features[9] = value
      mustReject(features)
    }
    mustReject(f.features,count:0)
    mustReject(f.features,count:-1)
    mustReject(f.features,qc:Double.nan)
    mustReject(f.features,ic:Double.infinity)
    mustReject(f.features,thickness:Double.nan)
    precondition(rejected == 9)
    let report:[String:Any] = ["status":"PASS","existing_parity_fixtures":fixtures.count,
      "max_absolute_errors_match_miss_depth":errors,"invalid_inputs_rejected":rejected,
      "new_training_or_datasets":false,"scope":"Existing frozen model contract; no site relative percentage is inferred"]
    print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
  }
}
