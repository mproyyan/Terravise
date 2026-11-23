"""Re-evaluate only existing captured states with the authorized 0.80 target."""
import sys
sys.dont_write_bytecode=True
from pathlib import Path
import json,hashlib
import numpy as np,pandas as pd
from reference_policy import Closure
source=Path('/tmp/terravise-practical-integration/fixtures.jsonl')
out=Path(sys.argv[1]);out.parent.mkdir(parents=True,exist_ok=True)
engine=Closure();previous=None;name=None;rows=[]
with source.open() as inp,out.open('w') as fh:
 for line in inp:
  q=json.loads(line);f=q['frame'];shape=(f['nx'],f['ny'],f['nz']);v=np.array(f['valid'],bool).reshape(shape);m=np.array(f['measured'],np.uint8).reshape(shape);c=np.array(f['classes'],np.uint8).reshape(shape);a=np.array(f['ambiguity'],bool).reshape(shape);sites=np.array(f['sites']);spacing=np.array([f['dx'],f['dy'],f['dz']])
  if name!=q['name']:previous=None;name=q['name']
  xy=np.argwhere(v.any(2));dist=np.linalg.norm((xy[:,None]-sites[None])*spacing[:2],axis=2).min(1).astype(np.float32).astype(float);radius=np.sqrt(2)*np.sqrt(f['area']/f['count']);p95=float(np.quantile(dist,.95)/radius);maximum=float(dist.max()/radius)
  maxrun=run=0
  if previous is not None:
   x,y=sites[-1]
   for z in range(shape[2]):
    run=run+1 if v[x,y,z] and m[x,y,z]!=255 and previous[x,y,z]!=m[x,y,z] else 0
    maxrun=max(maxrun,run)
  recent=[dict(from_state_id=t['from'],to_state_id=t['to'],coherent_revision=t['coherentRevision']) for t in q['recent']]
  base=dict(metrics=dict(spatial_support_status='PASS' if p95<=1 and maximum<=1.75 else 'CONTINUE',max_new_profile_mismatch_run_voxels=maxrun))
  # Exact stored same-prefix scalar, including actual26 coverage computed from native saved bounds.
  engine.coverage[(name,f['count'])]=(f['predictedCoverage'],int((v&(m==255)).sum()))
  r=engine.score(name,base,dict(decision=q['outcome'],reason_codes=q['reasons']),c,m,v,a,sites,spacing,None,None,recent,f['stateID'],dict(thresholds={'profile_mismatch_run_min_voxels':2}))
  rows.append(dict(source=name,n=f['count'],coverage=f['predictedCoverage'],old90=q['outcome'],candidate=r['decision'],reasons='|'.join(r['reason_codes'])))
  q['outcome']='STOP' if r['decision']=='STOP_CANDIDATE' else r['decision'];q['reasons']=r['reason_codes'];fh.write(json.dumps(q,separators=(',',':'))+'\n');previous=c
pd.DataFrame(rows).to_csv(out.parent/'states80.csv',index=False)
(out.parent/'input_fingerprint.json').write_text(json.dumps(dict(existing_fixture_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),states=len(rows),new_inference=0,new_geology=0),indent=2)+'\n')
assert len(rows)==4489
print('Existing-state Python evaluation80 complete:',len(rows))
