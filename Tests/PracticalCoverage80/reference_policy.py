"""Three-principle practical candidate using existing Uncertainty V3 coverage."""
import sys
sys.dont_write_bytecode=True
from pathlib import Path
import numpy as np,pandas as pd
ROOT=Path.home()/'Developer/cpt_super_learn'
VERSION='practical-dynamic-stop-research-1'
# Existing research target, not fitted here and not a field safety standard.
COVERAGE_THRESHOLD=.80
IC_TOLERANCE=.15
class Closure:
 def __init__(self):
  self.source=None;self.previous=None
  table=pd.read_csv(ROOT/'results/stratigraphic_uncertainty_v1/coverage_pipeline_stop/state_decisions.csv',float_precision='round_trip')
  assert not table.duplicated(['source','n']).any()
  self.coverage={(q.source,int(q.n)):(float(q.predicted_coverage),int(q.hidden_valid_voxels)) for q in table.itertuples()}
 def score(self,source,base,v3,c,m,v,a,sites,spacing,p,b,recent,state_id,config,raw_sequences=None):
  if source!=self.source:self.source=source;self.previous=None
  old=self.previous
  self.previous=dict(n=len(sites),id=state_id,sites=sites.copy(),m=m.copy(),v=v.copy())
  hidden=v&(m==255);count=int(hidden.sum())
  if raw_sequences is None:
   coverage,recorded_count=self.coverage.get((source,len(sites)),(np.nan,-1));origin='existing native-contract full-precision coverage artifact'
  else:
   coverage=float(np.count_nonzero(b[hidden]<=IC_TOLERANCE)/count) if count and b is not None and np.isfinite(b[hidden]).all() and (b[hidden]>=0).all() else np.nan
   recorded_count=count;origin='same coverage formula on saved native calibrated frame bounds; no fresh native UI execution'
  metrics=dict(baseline_v3=v3['decision'],baseline_v3_reasons=v3['reason_codes'],new_certificate=False,predicted_coverage=coverage,coverage_source=origin,hidden_valid_voxels=count,ambiguity_fraction=float(a.sum()/max(1,count)))
  def result(reason,stop=False):
   metrics['new_certificate']=bool(stop and v3['decision']!='STOP_CANDIDATE')
   return dict(configuration_id=VERSION,decision='STOP_CANDIDATE' if stop else 'CONTINUE',reason_codes=[reason],metrics=metrics)
  # 1. Area representation: original global support, no per-pattern veto.
  bm=base['metrics']
  if bm.get('spatial_support_status')!='PASS':return result('AREA_SPREAD_INSUFFICIENT')
  # 2. One genuine stable addition; reopen/edited observations are not additions.
  if old is None or old['n']+1!=len(sites) or old['id']==state_id or not np.array_equal(old['sites'],sites[:-1]) or not np.array_equal(old['v'],v):return result('GENUINE_CURRENT_CONFIRMATION_UNAVAILABLE')
  if not np.array_equal(m[old['m']!=255],old['m'][old['m']!=255]):return result('PREVIOUS_OBSERVATIONS_EDITED')
  if any(np.array_equal(sites[-1],q) for q in sites[:-1]):return result('REPEATED_LOCATION_NOT_CONFIRMATION')
  if not recent or recent[-1].get('from_state_id')!=old['id'] or recent[-1].get('to_state_id')!=state_id:return result('GENUINE_CURRENT_CONFIRMATION_UNAVAILABLE')
  if recent[-1]['coherent_revision']:return result('LATEST_CPT_CHANGES_MAIN_STRATIGRAPHY')
  if bm.get('max_new_profile_mismatch_run_voxels',2)>=config['thresholds']['profile_mismatch_run_min_voxels']:return result('LATEST_CPT_REVEALS_MATERIAL_PROFILE_MISMATCH')
  # 3. Accept existing predicted coverage target; no ambiguity/novelty veto.
  if not np.isfinite(coverage) or not 0<=coverage<=1 or count<=0 or count!=recorded_count:return result('VALID_COVERAGE_UNAVAILABLE')
  if coverage<COVERAGE_THRESHOLD:return result('PREDICTED_COVERAGE_BELOW_EXISTING_080_TARGET')
  if raw_sequences is not None:metrics['raw_scope']='two repeated uploaded templates; raw depth fidelity and independent origin not certified by coverage'
  return result('AREA_SPREAD_STABILITY_AND_COVERAGE_ACCEPTABLE',True)
