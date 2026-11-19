import Foundation
import CoreLocation
import SwiftUI
@MainActor final class AccessibilityCaptionCenter {
 static let shared=AccessibilityCaptionCenter()
 func announce(_ text:String,soundDescription:String? = nil) {}
}
enum SheetDestination { case projectList }
enum UncertaintySufficiencyService { static let v32FeatureParityVerified=false }
enum CPTPipelineParityAttestation { static func verified(points:[CPTPointEntry],grid:CPTGridConfig)->Bool { false } }
enum CPTPipelineCoordinator {
 static func runPipeline(boundaryCoordinates:[CLLocationCoordinate2D],cptPoints:[CPTPointEntry],previousConsecutiveSufficientCount:Int,gridPolicy:CPTGridPolicy = .legacyDynamic,distancePolicy:CPTDistancePolicy = .legacyCellDiagonal,assessmentProject:Project? = nil)->CPTRecommendationResult {
  CPTRecommendationResult(coordinate:CLLocationCoordinate2D(latitude:-6.2418,longitude:106.8315),recommendationSource:"DQN V4.6-A Core ML",assessmentSource:"Sufficiency V3.2 experimental; STOP unavailable: DQN trajectory not verified")
 }
 static func recomputeFromScratch(boundaryCoordinates:[CLLocationCoordinate2D],cptPoints:[CPTPointEntry],gridPolicy:CPTGridPolicy = .legacyDynamic,distancePolicy:CPTDistancePolicy = .legacyCellDiagonal,assessmentProject:Project? = nil)->CPTRecommendationResult { runPipeline(boundaryCoordinates:boundaryCoordinates,cptPoints:cptPoints,previousConsecutiveSufficientCount:0,gridPolicy:gridPolicy,distancePolicy:distancePolicy,assessmentProject:assessmentProject) }
}
