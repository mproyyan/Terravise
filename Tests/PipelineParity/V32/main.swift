import Foundation
struct CPTGridConfig { let nx:Int,ny:Int,nz:Int; let dxM:Double,dyM:Double,dzM:Double,siteDiagonalM:Double; let validXYMask:[[Bool]] }
struct SchemaGANReconstructionOutput { let reconstructedIc:[[[Double]]]; let observedMask:[[[Bool]]]; let validMask:[[[Bool]]]; let observedSitesXY:[(ix:Int,iy:Int)]; let inferenceSource:String }
struct GridFixture:Decodable { let nx:Int,ny:Int,nz:Int; let dx:Double,dy:Double; let valid:[[[Bool]]],observed:[[[Bool]]]; let sites:[[Int]]; let rawBounds:[Double],correction:Double }
struct Sample:Decodable { let features:[Double] }
@main struct Main { static func main() throws {
 let decoder=JSONDecoder(); let f=try decoder.decode(GridFixture.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
 guard let values=UncertaintySufficiencyService.v32Features(nx:f.nx,ny:f.ny,nz:f.nz,dx:f.dx,dy:f.dy,valid:f.valid,observed:f.observed,sites:f.sites.map{($0[0],$0[1])},rawBounds:f.rawBounds,correction:f.correction) else { fatalError("invalid feature fixture") }
 let samples=try decoder.decode([Sample].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
 let url=URL(fileURLWithPath:CommandLine.arguments[3]); let probabilities=try samples.map{try UncertaintySufficiencyService.v32ParityProbability(modelURL:url,features:$0.features)}
 let output:[String:Any] = ["features":values,"probabilities":probabilities]
 try JSONSerialization.data(withJSONObject:output).write(to:URL(fileURLWithPath:CommandLine.arguments[4]))
} }
