import json,sys
from pathlib import Path
import joblib,numpy as np,pandas as pd
import sklearn.ensemble
from scipy.ndimage import distance_transform_edt
fixture=json.loads(Path(sys.argv[1]).read_text()); s=json.loads(Path(sys.argv[2]).read_text())
nx,ny,nz=s['shape_xyz']; dx,dy,dz=s['spacing_m']; shape=(nx,ny,nz)
swift_rec=np.asarray(s['reconstruction_xyz'],dtype=float).reshape(shape); valid=np.asarray(s['valid_xyz'],bool).reshape(shape); observed=np.asarray(s['observed_xyz'],bool).reshape(shape)
from dqn3d.v46.adapter import FrozenV4Reconstructor
from synthetic3d.v2.core import Grid
obs=np.zeros(shape,np.float32); refmask=np.zeros(shape,bool)
for profile in fixture['profiles']:
 for row in profile['rows']:
  iz=int(round(row['depth_m']/dz)); obs[profile['x'],profile['y'],iz]=row['ic']; refmask[profile['x'],profile['y'],iz]=True
assert np.array_equal(observed,refmask)
reconstructor=FrozenV4Reconstructor('model_export/SchemaGAN_V4_2/SchemaGAN_V4_2.pt','model_export/SchemaGAN_V4_2/normalization.json',device='cpu')
r,_=reconstructor.predict(obs,observed,valid,Grid(nx,ny,nz,dx,dy,dz))
d=np.abs(r.astype(float)-swift_rec); idx=np.unravel_index(np.argmax(d),shape)
print('independent SchemaGAN output max=',float(d[idx]),'xyz=',idx)
assert np.array_equal(valid,np.broadcast_to(np.asarray(fixture['valid_xy'],bool).reshape(nx,ny,1),shape))
assert sorted(s['sites'])==sorted([[p['x'],p['y']] for p in fixture['profiles']])
coords=np.argwhere(valid & ~observed); assert np.array_equal(coords,np.asarray(s['coords']))
measured=observed.any(axis=2); distance=distance_transform_edt(~measured,sampling=(dx,dy)); gx,gy,gz=np.gradient(r,dx,dy,dz); lateral=np.sqrt(gx**2+gy**2); vertical=np.abs(gz)
xx,yy=np.meshgrid(np.arange(nx)*dx,np.arange(ny)*dy,indexing='ij'); nearby=np.zeros((nx,ny),np.float32)
for x,y in np.argwhere(measured): nearby+=(np.sqrt((xx-x*dx)**2+(yy-y*dy)**2)<=25).astype(np.float32)
nearby/=float(len(s['sites']))
x,y,z=coords.T
names=['distance_to_cpt_m','depth_m','predicted_ic','lateral_gradient','vertical_gradient','nearby_cpt_fraction_25m','n_cpt','dx_m','dy_m','dz_m']
X=pd.DataFrame(dict(zip(names,[distance[x,y],z.astype(float)*dz,r[x,y,z],lateral[x,y,z],vertical[x,y,z],nearby[x,y],np.full(len(x),len(s['sites']),float),np.full(len(x),dx),np.full(len(x),dy),np.full(len(x),dz)])))[names]
model=joblib.load('results/uncertainty_v3/uncertainty_v3_quantile.joblib'); metadata=json.loads(Path('results/uncertainty_v3/model_metadata.json').read_text()); correction=metadata['calibration_correction']
raw=model.predict(X); final=np.maximum(0,raw)+correction; coverage=float(np.mean(final<=0.15))
all_ok=True
for i,name in enumerate(names):
 d=np.abs(X.to_numpy(dtype=float)[:,i]-np.asarray(s['features'])[:,i]); j=int(np.argmax(d)); tolerance=1e-6
 print(f'feature {name}: max={d[j]:.12g} xyz={tuple(coords[j])} python={X.iloc[j,i]:.12g} swift={s["features"][j][i]:.12g} tolerance={tolerance}'); all_ok &= d[j]<=tolerance
for name,a,b,tol in [('raw',raw,s['raw'],1e-9),('final',final,s['final'],1e-9)]:
 d=np.abs(a-np.asarray(b)); j=int(np.argmax(d)); print(f'{name}: max={d[j]:.12g} xyz={tuple(coords[j])} python={a[j]:.12g} swift={b[j]:.12g} tolerance={tol}'); all_ok &= d[j]<=tol
print('correction python=',correction,'swift=',s['correction'],'error=',abs(correction-s['correction'])); all_ok &= abs(correction-s['correction'])<=1e-15
print('coverage python=',coverage,'swift=',s['coverage'],'error=',abs(coverage-s['coverage']),'hidden_voxels=',len(coords)); all_ok &= abs(coverage-s['coverage'])<=1e-12
sys.exit(0 if all_ok else 1)
