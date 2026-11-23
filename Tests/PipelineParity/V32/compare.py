import json,sys
import joblib,numpy as np
from pathlib import Path
f=json.loads(Path(sys.argv[1]).read_text()); samples=json.loads(Path(sys.argv[2]).read_text()); swift=json.loads(Path(sys.argv[3]).read_text())
nx,ny,nz=(f[k] for k in ('nx','ny','nz')); dx,dy=f['dx'],f['dy']; valid=np.array(f['valid'],bool); obs=np.array(f['observed'],bool); sites=np.array(f['sites']); raw=np.array(f['rawBounds']); correction=f['correction']
assert raw.size==np.count_nonzero(valid & ~obs)
coverage=np.mean(np.maximum(0,raw)+correction<=.15); xy=np.argwhere(valid.any(axis=2)); dist=np.sqrt(np.sum(((xy[:,None,:]-sites[None,:,:])*[dx,dy])**2,axis=2)); maxdist=dist.min(axis=1).max()
w=(nx-1)*dx; h=(ny-1)*dy; diagonal=np.hypot(w,h); area=w*h; n=len(sites)
expected=np.array([coverage,maxdist/diagonal,n,w,h,diagonal,area,np.sqrt(area/n),maxdist,max(w,h)/min(w,h)])
actual=np.array(swift['features']); diffs=abs(expected-actual); names=['predicted_coverage','max_distance_fraction','n_cpt','site_width_m','site_height_m','site_diagonal_m','site_area_m2','mean_cpt_spacing_m','max_nearest_distance_m','aspect_ratio']
for name,a,b,d in zip(names,expected,actual,diffs): print(f'{name}: python={a:.17g} swift={b:.17g} error={d:.17g}')
model=joblib.load('results/uncertainty_v3_2_dqn10/v3_2_dqn10_sufficiency.joblib'); probabilities=model.predict_proba(np.array([s['features'] for s in samples]))[:,1]; err=abs(probabilities-np.array(swift['probabilities'])); i=int(err.argmax())
print(f'V32_FEATURE max_error={diffs.max():.17g} tolerance=1e-10')
print(f'V32_CLASSIFIER max_error={err[i]:.17g} tolerance=1e-9 index={i} fixtures={len(samples)}')
sys.exit(0 if len(samples)==100 and diffs.max()<=1e-10 and err[i]<=1e-9 else 1)
