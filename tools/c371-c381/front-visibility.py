"""Front +X ray samples on delivered triangles; reject backing peeking through.

Samples are model review regions, not claims of exact real-train dimensions.
The glass mutation moves actual glass triangles into the shell, not parameters.
"""
import json,struct,sys
from pathlib import Path
import numpy as np
root=Path(sys.argv[1]); b=(root/'models/c371-dm.m3dmodel').read_bytes()
n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
tri=np.array([[struct.unpack_from('<fff',b,start+i*52+4+j*16) for j in range(3)] for i in range(n)])
colors=np.array([struct.unpack_from('<I',b,start+i*52+16)[0] for i in range(n)])
# Anchor colours from unobstructed points; all other samples must agree.
# A defect at an anchor alone cannot silently pass the region checks.
front=tri[:,:,0].min(axis=1)>11.5
mask=None
# glass is the largest repeated colour in the two windshield interiors, found
# by an unobstructed central sample (and checked against both windows below).
def visible(t,y,z):
 a=t[:,0,1:];u=t[:,1,1:]-a;v=t[:,2,1:]-a;q=np.array([y,z])-a
 det=u[:,0]*v[:,1]-u[:,1]*v[:,0];ok=abs(det)>1e-10
 f=np.divide(q[:,0]*v[:,1]-q[:,1]*v[:,0],det,out=np.zeros(n),where=ok)
 g=np.divide(u[:,0]*q[:,1]-u[:,1]*q[:,0],det,out=np.zeros(n),where=ok)
 hits=ok&(f>=-1e-6)&(g>=-1e-6)&(f+g<=1.000001)
 xs=t[:,0,0]+f*(t[:,1,0]-t[:,0,0])+g*(t[:,2,0]-t[:,0,0]);xs[~hits]=-np.inf
 i=int(xs.argmax());assert xs[i]>11.5;return int(colors[i])
mask=visible(tri,0.42,2.8)
glass=visible(tri,0.90,2.75)
assert glass!=mask
mask_samples=[(sign*y,z) for sign in [-1,1] for y in [0.415,0.425,1.38] for z in np.linspace(2.05,2.95,19)]
# Foot/wiper paths are excluded by using high central window samples.
glass_samples=[(sign*y,z) for sign in [-1,1] for y in [.70,.90,1.10] for z in [2.65,2.80,2.90]]
def check(t):
 assert all(visible(t,y,z)==mask for y,z in mask_samples),'backing visible through mask'
 assert all(visible(t,y,z)==glass for y,z in glass_samples),'windshield obstructed'
check(tri)
broken=tri.copy();broken[(colors==glass)&front,:,0]-=.30
try:check(broken)
except AssertionError:pass
else:raise AssertionError('buried actual glass mutation was accepted')
(root/'front-visibility-verification.json').write_text(json.dumps({'status':'VERIFIED','mask_samples':len(mask_samples),'glass_samples':len(glass_samples),'buried_glass_300mm_rejected':True,'limits':'Front orthographic sampled regions only, not exhaustive intersections or all-view visibility.'},indent=2)+'\n')
print('VERIFIED front mask/glass ray samples and actual buried-glass rejection')
