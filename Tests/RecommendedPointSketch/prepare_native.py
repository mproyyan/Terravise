from pathlib import Path
import re,sys
root=Path(__file__).resolve().parents[2];work=Path(sys.argv[1])
model=(root/'GeoSome/Features/CPTRecommendation/Models/CPTData.swift').read_text()
vm=(root/'GeoSome/Features/CPTRecommendation/ViewModels/CPTRecommendationViewModel.swift').read_text()
constants='\n'.join(re.findall(r'  static let \w+SheetDetent[^\n]+',vm))
helpers=(root/'GeoSome/Features/Result/Components/ResultLeftPlaceholderSheetView.swift').read_text().split('struct LegendMapItem:')[0]
(work/'ExistingSheetSizing.swift').write_text(helpers)
(work/'Dependencies.swift').write_text('import CoreLocation\nimport SwiftUI\n'+model[model.index('struct CPTCandidateSpacing:'):]+'\nenum CPTRecommendationViewModel {\n'+constants+'\n}\n')
view=(root/'GeoSome/Features/CPTRecommendation/Views/CPTRecommendationView.swift').read_text()
start=view.index('      .presentationPlacement(.leading)',view.index('.sheet(isPresented: sheetPresentedBinding)'))
end=view.index('\n    }\n    .toolbar',start)
modifiers=view[start:end].replace('activeSheetDetents','[CPTRecommendationViewModel.collapsedSheetDetent, CPTRecommendationViewModel.populatedSheetDetent, CPTRecommendationViewModel.sufficientSheetDetent, CPTRecommendedPointSheetView.stopSheetDetent, CPTRecommendationViewModel.recommendationSheetDetent, .large]').replace('activeSheetDetentBinding','$detent').replace('isInteractiveSheetDismissDisabled','true')
app=(root/'Tests/RecommendedPointSketch/NativeSheetApp.swift').read_text().replace('// PRODUCTION_MODIFIERS',modifiers)
(work/'NativeSheetApp.swift').write_text(app)
