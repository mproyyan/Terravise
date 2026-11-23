#!/usr/bin/env python3
"""Run local parity harnesses and capture actual fingerprints; never certifies STOP."""
import hashlib,json,os,re,subprocess,sys,datetime
from pathlib import Path
root=Path(__file__).resolve().parents[2]; research=Path(os.environ.get('SCHEMAGAN_RESEARCH_ROOT',Path.home()/'Developer/cpt_super_learn')); fixture=Path(sys.argv[1]) if len(sys.argv)>1 else Path('/tmp/terravise-geosyn-00018/distributed_cpt3.json')
files={
 'swift_schemgan':root/'GeoSome/Features/CPTRecommendation/Services/SchemaGANService.swift',
 'swift_uncertainty_and_features':root/'GeoSome/Features/CPTRecommendation/Services/UncertaintySufficiencyService.swift',
 'swift_grid_mapping':root/'GeoSome/Features/CPTRecommendation/Models/CPTGridConfig.swift',
 'swift_cpt_input':root/'GeoSome/Features/CPTRecommendation/Models/CPTData.swift',
 'python_adapter':research/'dqn3d/v46/adapter.py',
 'python_evaluator':research/'scripts/spatial_representativeness/validate_v32_holdout2.py',
 'schema_checkpoint':research/'model_export/SchemaGAN_V4_2/SchemaGAN_V4_2.pt',
 'schema_normalization':research/'model_export/SchemaGAN_V4_2/normalization.json',
 'uncertainty_python':research/'results/uncertainty_v3/uncertainty_v3_quantile.joblib',
 'uncertainty_metadata':research/'results/uncertainty_v3/model_metadata.json',
 'uncertainty_swift':root/'GeoSome/Features/CPTRecommendation/Resources/UncertaintyV3.json',
 'classifier_swift':root/'GeoSome/Features/CPTRecommendation/Resources/SufficiencyV3_2.json',
 'classifier_python':research/'results/uncertainty_v3_2_dqn10/v3_2_dqn10_sufficiency.joblib',
 'fixture':fixture,
 'manifest_harness':Path(__file__).resolve(),
 'v32_feature_fixture':root/'GeoSome/Features/CPTRecommendation/Resources/SufficiencyV32FeatureParity.json',
 'v32_classifier_fixture':root/'Tests/PipelineParity/V32/classifier_inputs.json',
}
for folder in ['SchemaGANParity','UncertaintyV3Parity','PipelineParity']:
 for name in ['main.swift','compare.py','run.sh']:
  files[f'{folder}/{name}']=root/'Tests'/folder/name
for p in (root/'Tests/PipelineParity/V32').glob('*'):
 if p.is_file(): files['V32/'+p.name]=p
for p in (root/'GeoSome/Features/CPTRecommendation/Resources/SchemaGAN_V4_2_Flexible.mlpackage').rglob('*'):
 if p.is_file(): files['schema_package/'+str(p.relative_to(root/'GeoSome/Features/CPTRecommendation/Resources/SchemaGAN_V4_2_Flexible.mlpackage'))]=p
# Fingerprint the actual compiled Core ML files selected by the same run.sh find expression.
derived=Path.home()/'Library/Developer/Xcode/DerivedData'
models=sorted(derived.glob('*/Build/Products/Debug-iphonesimulator/GeoSome.app/SchemaGAN_V4_2_Flexible.mlmodelc'))
if models:
 for p in models[0].rglob('*'):
  if p.is_file(): files['compiled_model/'+str(p.relative_to(models[0]))]=p

def fingerprints():
 return {k:hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None for k,p in files.items()}
before=fingerprints(); stages={}
for name in ['SchemaGANParity','UncertaintyV3Parity','PipelineParity']:
 result=subprocess.run([str(root/'Tests'/name/'run.sh'),str(fixture)],cwd=root,text=True,capture_output=True)
 print(result.stdout,end=''); print(result.stderr,end='',file=sys.stderr)
 measurements=[]
 for line in result.stdout.splitlines():
  m=re.search(r'(?:^| )max(?:_error)?[=:]\s*([0-9.eE+-]+)',line)
  if m: measurements.append({'stage':line.split(':')[0], 'max_absolute_error':float(m.group(1)),'detail':line})
 stages[name]={'status':'PASS' if result.returncode==0 else 'FAIL','exit_code':result.returncode,'measurements':measurements,'tolerances':{'schema_input':1e-6,'schema_output':2e-5,'uncertainty_features':1e-6,'raw_and_final':1e-9,'correction':1e-15,'coverage':1e-12},'output':result.stdout,'stderr':result.stderr}
after=fingerprints(); unchanged=before==after and all(before.values()); f=json.loads(fixture.read_text())
pipeline_output=stages['PipelineParity']['output']
for key, marker, tolerance, fixture_key, coverage in [
 ('V32Features','V32_FEATURE',1e-10,'v32_feature_fixture','one 24x24x12 feature fixture'),
 ('V32Classifier','V32_CLASSIFIER',1e-9,'v32_classifier_fixture','100 feature vectors')]:
 match=re.search(r'^'+marker+r' max_error=([0-9.eE+-]+)',pipeline_output,re.MULTILINE)
 error=float(match.group(1)) if match else None
 stages[key]={'status':'PASS' if error is not None and error <= tolerance and stages['PipelineParity']['status']=='PASS' else 'FAIL',
              'max_absolute_error':error,'tolerance':tolerance,'fixture_sha256':before[fixture_key],
              'coverage':coverage,'source_sha256':before['swift_uncertainty_and_features'],
              'model_sha256':before['classifier_swift'] if key=='V32Classifier' else before['uncertainty_swift']}

overall='PASS' if unchanged and all(x['status']=='PASS' for x in stages.values()) else 'FAIL'
manifest={'format_version':1,'harness':'TerravisePipelineParity','harness_version':1,'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'overall_status':overall,'scope':{'fixture_sha256':before['fixture'],'shape_xyz':f['shape_xyz'],'spacing_m':f['spacing_m'],'cpt_count':len(f['profiles']),'scope':'only this exact synthetic fixture; not general grid or profile parity'},'fingerprints_before':before,'fingerprints_after':after,'files_unchanged_during_test':unchanged,'stages':stages}
out=Path(sys.argv[2]) if len(sys.argv)>2 else root/'Tests/PipelineParity/parity_manifest.json';out.write_text(json.dumps(manifest,indent=2)+'\n'); print('manifest:',out,'overall:',overall,'fingerprints stable:',unchanged);sys.exit(0 if overall=='PASS' else 1)
