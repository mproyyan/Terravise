import json,sys
from pathlib import Path
import numpy as np
root=Path.home()/'Developer/cpt_super_learn';sys.path.insert(0,str(root))
from validate_dynamic_terravise_batch_20 import resample
p=root/'data/synthetic3d_v4_geosyn_qcfs/v2_full_24k/test/v4_test_00020.npz'; d=np.load(p); shape=(32,32,16); spacing=(7.139612356115623,7.134670784122269,0.7333333333333333)
arrays={}
for key in ('Ic','qc_mpa','fs_mpa'):
 a,mask=resample(d[key],d['valid_mask'],shape,spacing);assert mask.all();arrays[key]=a.ravel().astype(float).tolist()
json.dump(arrays,open(sys.argv[1],'w'))
