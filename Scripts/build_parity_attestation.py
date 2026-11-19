#!/usr/bin/env python3
"""Bind parity evidence to the source and model used by this build; fail closed."""
import base64,hashlib,json,os,pathlib
root=pathlib.Path(os.environ['SRCROOT']); out=pathlib.Path(os.environ['TARGET_BUILD_DIR'])/os.environ['UNLOCALIZED_RESOURCES_FOLDER_PATH']/'CPTParityAttestation.json'
def sha(path):
 try: return hashlib.sha256(path.read_bytes()).hexdigest()
 except OSError: return None
resources=root/'GeoSome/Features/CPTRecommendation/Resources'
paths={'swift_schemgan':root/'GeoSome/Features/CPTRecommendation/Services/SchemaGANService.swift','swift_uncertainty_and_features':root/'GeoSome/Features/CPTRecommendation/Services/UncertaintySufficiencyService.swift','swift_grid_mapping':root/'GeoSome/Features/CPTRecommendation/Models/CPTGridConfig.swift','swift_cpt_input':root/'GeoSome/Features/CPTRecommendation/Models/CPTData.swift','uncertainty_swift':resources/'UncertaintyV3.json','classifier_swift':resources/'SufficiencyV3_2.json','v32_feature_fixture':resources/'SufficiencyV32FeatureParity.json','fixture':root/'Tests/PipelineParity/attested_fixture.json'}
package=resources/'SchemaGAN_V4_2_Flexible.mlpackage'
for rel in ['Manifest.json','Data/com.apple.CoreML/model.mlmodel','Data/com.apple.CoreML/weights/weight.bin']: paths['schema_package/'+rel]=package/rel
manifest_path=root/'Tests/PipelineParity/parity_manifest.json'
result={'format_version':1,'valid':False}
try:
 m=json.loads(manifest_path.read_text()); expected=m['fingerprints_before']; actual={k:sha(p) for k,p in paths.items()}
 critical=['SchemaGANParity','UncertaintyV3Parity','PipelineParity','V32Features','V32Classifier']
 valid=(m['overall_status']=='PASS' and m['files_unchanged_during_test'] is True and m['fingerprints_after']==expected and all(m['stages'][k]['status']=='PASS' for k in critical) and all(v is not None and expected.get(k)==v for k,v in actual.items()))
 fixture=json.loads(paths['fixture'].read_text())
 result.update(valid=valid,manifest_sha256=sha(manifest_path),manifest=base64.b64encode(manifest_path.read_bytes()).decode(),fixture=base64.b64encode(paths['fixture'].read_bytes()).decode(),fingerprints=actual)
except (OSError,ValueError,KeyError,TypeError): pass
out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,separators=(',',':')))
print('CPT parity build attestation:', 'verified' if result['valid'] else 'unavailable (fail closed)')
