"""Verify the two actual box supports bridge nose beam and floor.

This is a local contact check for these three box parts, not a full collision
or structural engineering claim. The mutation lowers actual support vertices.
"""
from pathlib import Path
import struct,json,sys
import numpy as np
root=Path(sys.argv[1]);b=(root/'models/c371-dm.m3dmodel').read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
t=np.array([[struct.unpack_from('<fff',b,start+i*52+4+j*16) for j in range(3)] for i in range(n)])
parent=list(range(n));owners={}
def find(i):
 while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
 return i
for i,tri in enumerate(t):
 for v in tri:
  key=tuple(np.round(v,5))
  if key in owners:parent[find(i)]=find(owners[key])
  else:owners[key]=i
components={}
for i in range(n):components.setdefault(find(i),[]).append(i)
boxes=[]
for indices in components.values():
 v=t[indices].reshape(-1,3);lo=v.min(axis=0);hi=v.max(axis=0)
 if len(indices)==12 and all(len(np.unique(np.round(v[:,k],5)))==2 for k in range(3)):boxes.append((indices,lo,hi))
def one(predicate):
 items=[x for x in boxes if predicate(x[1],x[2])];assert len(items)==1,len(items);return items[0]
floor=one(lambda lo,hi:hi[0]-lo[0]>23 and abs(lo[2]-.92)<1e-4 and abs(hi[2]-1.04)<1e-4)
beam=one(lambda lo,hi:11.18<lo[0]<11.20 and 11.44<hi[0]<11.46 and abs(lo[2]-.84)<1e-4 and abs(hi[2]-.96)<1e-4)
supports=[x for x in boxes if 11.29<x[1][0]<11.31 and 11.51<x[2][0]<11.53 and abs(x[1][2]-.74)<1e-4 and abs((x[1][1]+x[2][1])/2)>.9]
assert len(supports)==2,len(supports)
def contact(a,b):return bool((np.minimum(a[2],b[2])-np.maximum(a[1],b[1])>1e-5).all())
for support in supports:
 assert contact(support,beam) and contact(support,floor),'support does not bridge floor and beam'
 damaged=t[support[0]].copy();damaged[:,:,2]-=.05
 vertices=damaged.reshape(-1,3)
 shifted=(support[0],vertices.min(axis=0),vertices.max(axis=0))
 assert not contact(shifted,floor),'lowered support fault was accepted'
(root/'underframe-contact-verification.json').write_text(json.dumps({'status':'VERIFIED','supports':2,'actual_box_components':True,'floor_and_beam_overlap_each_axis':True,'lowered_support_50mm_rejected':True,'limits':'Local contact of identified solid boxes only; not full collision or real structural validation.'},indent=2)+'\n')
print('VERIFIED actual support boxes meet floor/beam; 50 mm lowered-support fault rejected')
