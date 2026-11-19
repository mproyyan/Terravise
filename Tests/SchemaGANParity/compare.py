import json, sys
from pathlib import Path
import numpy as np
import torch
from dqn3d.v46.adapter import FrozenV4Reconstructor
from synthetic3d.v2.core import Grid
f=json.loads(Path(sys.argv[1]).read_text()); swift=json.loads(Path(sys.argv[2]).read_text())
nx,ny,nz=f['shape_xyz']; dx,dy,dz=f['spacing_m']; grid=Grid(nx,ny,nz,dx,dy,dz)
obs=np.zeros((nx,ny,nz),np.float32); mask=np.zeros_like(obs,dtype=bool); valid=np.broadcast_to(np.array(f['valid_xy'],bool).reshape(nx,ny,1),(nx,ny,nz)).copy()
for p in f['profiles']:
 for row in p['rows']:
  z=int(round(row['depth_m']/dz)); obs[p['x'],p['y'],z]=row['ic']; mask[p['x'],p['y'],z]=True
assert np.array_equal(mask,np.array(swift['observed_xyz']).reshape(nx,ny,nz))
assert np.array_equal(valid,np.array(swift['valid_xyz']).reshape(nx,ny,nz))
assert sorted([p['x'],p['y']] for p in f['profiles']) == sorted(swift['sites'])
model=FrozenV4Reconstructor(Path('model_export/SchemaGAN_V4_2/SchemaGAN_V4_2.pt'),Path('model_export/SchemaGAN_V4_2/normalization.json'),device='cpu')
captured=[]
hook=model.model.register_forward_pre_hook(lambda module, inputs: captured.append(inputs[0].detach().cpu().numpy().copy()))
pred,_=model.predict(obs,mask,valid,grid); hook.remove()
a=captured[0]; b=np.array(swift['input'],dtype=np.float32).reshape(1,7,nz,ny,nx)
print('model checkpoint sha256:',model.checkpoint_sha256)
print('input shape:',a.shape,'dtype:',a.dtype,'layout: BCZYX; output XYZ:',pred.shape)
for c in range(7):
 d=np.abs(a[0,c].astype(np.float64)-b[0,c]); idx=np.unravel_index(d.argmax(),d.shape); print(f'channel {c}: max={d[idx]:.12g} zyx={idx} python={a[(0,c,*idx)]:.12g} swift={b[(0,c,*idx)]:.12g}')
d=np.abs(pred.astype(np.float64)-np.array(swift['output_xyz']).reshape(nx,ny,nz)); idx=np.unravel_index(d.argmax(),d.shape)
print(f'output: max={d[idx]:.12g} xyz={idx} python={pred[idx]:.12g} swift={np.array(swift["output_xyz"]).reshape(nx,ny,nz)[idx]:.12g}')
inputerr=float(np.max(np.abs(a.astype(np.float64)-b))); outer=float(d.max()); print('INPUT', 'PASS' if inputerr<=1e-6 else 'FAIL', 'OUTPUT', 'PASS' if outer<=2e-5 else 'FAIL'); sys.exit(0 if inputerr<=1e-6 and outer<=2e-5 else 1)
