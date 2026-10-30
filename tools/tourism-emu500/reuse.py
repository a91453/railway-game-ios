"""Position multisets prove retained EMU500 bogie and roof output segments."""
from pathlib import Path
import json,struct,collections,sys
import numpy as np
from probes import read
base,run=map(Path,sys.argv[1:3]);rows=[]
def signature(t,select):
 return collections.Counter(tuple(sorted(tuple(np.round(v,5)) for v in tri)) for tri in t[select])
for fleet in ['haifeng','shanlan']:
 for role in ['emc','ep','et','em']:
  a,_=read(base/'models'/f'emu500-{role}.m3dmodel');b,_=read(run/fleet/'models'/f'{fleet}-emu500-{role}.m3dmodel')
  for name,fn in [('bogies',lambda t:(abs(t[:,:,0])>4.8).all(axis=1)&(abs(t[:,:,0])<8.6).all(axis=1)&(t[:,:,2]<.87).all(axis=1)),('roof equipment',lambda t:(t[:,:,2]>=3.65-1e-5).all(axis=1)&((abs(t[:,:,0]-7.8)<1.301).all(axis=1)|(abs(t[:,:,0]+7.8)<1.301).all(axis=1)))]:
   aa=signature(a,fn(a));bb=signature(b,fn(b));assert aa==bb,(fleet,role,name)
   rows.append(dict(fleet=fleet,role=role,retained=name,triangles=sum(aa.values()),positions_identical=True))
print(json.dumps(rows,indent=2))
