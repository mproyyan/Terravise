import json,sys
from pathlib import Path
import numpy as np
root=Path.home()/'Developer/cpt_super_learn';sys.path.insert(0,str(root))
from validate_dynamic_terravise_batch_20 import resample
batch=json.loads((root/'results/terravise_v32_dynamic_batch_20.json').read_text()); selected=next(r for r in batch['results'] if r['stop_cpt']); d=np.load(root/'data/synthetic3d_v4_geosyn/full_24k/test'/selected['volume']);shape=batch['target_shape'];spacing=batch['target_spacing_m']; truth,mask=resample(d['Ic'],d['valid_mask'],shape,spacing)
assert mask.all(); json.dump({'grid':{'nx':shape[0],'ny':shape[1],'nz':shape[2],'dx_m':spacing[0],'dy_m':spacing[1],'dz_m':spacing[2]},'truth':truth.ravel().tolist(),'expected':selected},open(sys.argv[1],'w'))
