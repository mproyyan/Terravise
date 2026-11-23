from pathlib import Path
import sys,re
root=Path(__file__).resolve().parents[2];work=Path(sys.argv[1])
view=(root/'GeoSome/Features/Result/Views/ResultAnalysisView.swift').read_text()
start=view.index('        .frame(width: oneThirdSheetWidth)',view.index('.sheet(isPresented: leftSheetPresentedBinding)'))
end=view.index('\n      }\n    }\n    .toolbar',start)
modifiers=view[start:end]
assert modifiers.count('.presentationDetents(')==1
assert '.presentationBackground(' not in modifiers
assert '.presentationCornerRadius(' not in modifiers
modifiers=modifiers.replace('$viewModel.selectedSheetDetent','$detent')
app=(root/'Tests/BearingSubsurfaceSheetReuse/NativeSheetApp.swift').read_text().replace('// PRODUCTION_PRESENTATION_MODIFIERS',modifiers)
(work/'NativeSheetApp.swift').write_text(app)
model=(root/'GeoSome/Features/Result/Models/SubsurfaceVoxelModels.swift').read_text()
soil=model[model.index('enum SoilLayerType:'):model.index('/// Pure domain data model for a single 1m² ×')]
vm=(root/'GeoSome/Features/Result/ViewModels/ResultAnalysisViewModel.swift').read_text()
detents='\n'.join(re.findall(r'  static let (?:collapsed|default|expanded)SheetDetent[^\n]+',vm))
assert len(detents.splitlines())==3
(work/'TestDependencies.swift').write_text('import UIKit\nimport SwiftUI\n'+soil+'\nenum ResultAnalysisViewModel {\n'+detents+'\n}\n')
(work/'production-modifiers.swift.txt').write_text(modifiers)
