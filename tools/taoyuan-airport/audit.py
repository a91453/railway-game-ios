#!/usr/bin/env python3
"""Actual-triangle probes; centroid rays are not exhaustive collision proof.
Read/normal/ray primitives adapted from main 39aaec02 tools/taichung-green/audit.py.
Only this vehicle's dimensions and fault probes are used.
"""
import json,sys,struct
from pathlib import Path
import numpy as np

def read(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);o=16+(size+3)//4*4
 t=[];f=[]
 for i in range(n):
  f.append(struct.unpack_from('<I',b,o+i*52)[0]);t.append([struct.unpack_from('<fff',b,o+i*52+4+j*16) for j in range(3)])
 return np.array(t),np.array(f)
def normals(t):
 n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);return n/np.linalg.norm(n,axis=1)[:,None]
def hits(t,o,d):
 e1=t[:,1]-t[:,0];e2=t[:,2]-t[:,0];h=np.cross(np.broadcast_to(d,e2.shape),e2);a=np.sum(e1*h,axis=1);ok=np.abs(a)>1e-9
 inv=np.divide(1,a,out=np.zeros_like(a),where=ok);s=o-t[:,0];u=inv*np.sum(s*h,axis=1);q=np.cross(s,e1);v=inv*np.sum(d*q,axis=1);dist=inv*np.sum(e2*q,axis=1)
 return dist[ok&(u>=-1e-6)&(v>=-1e-6)&(u+v<=1+1e-6)&(dist>1e-6)]
def glazing(t,f):
 n=normals(t);c=t.mean(axis=1);sel=((f&2)!=0)&(((abs(c[:,1])>1.52)&(n[:,1]*c[:,1]>1))|((n[:,0]>.8)&(c[:,0]>9)))
 ids=np.flatnonzero(sel);assert len(ids)>0,'missing glass'
 for i in ids:
  ds=hits(t,c[i]+n[i]*.30,-n[i]);assert len(ds) and min(ds)>.297,'glass occluded'
  # Interior support within 65mm of actual glass front, excluding glass itself.
  ds=hits(t[(f&2)==0],c[i]-n[i]*.001,-n[i]);assert len(ds) and min(ds)<.065,('glass floats',i,c[i].tolist(),float(min(ds)) if len(ds) else None)
 return ids

def wheels(t):
 p=t.reshape(-1,3)
 for x in [-7.8,-5.7,5.7,7.8]:
  for y in [-.7675,.7675]:
   q=p[(abs(p[:,0]-x)<.426)&(abs(p[:,1]-y)<.051)&(p[:,2]<.851)]
   assert len(q)>10 and abs(q[:,2].min())<1e-5,'missing/lifted wheel'
   ds=hits(t,np.array([x,y,.86]),np.array([0.,0,1.]));assert len(ds) and min(ds)>.05,'tyre body clearance'
def roof(t,baggage):
 p=t.reshape(-1,3)
 for x in ([8.05] if baggage else [-6.25,6.25]):
  q=p[(abs(p[:,0]-x)<1.7)&(abs(p[:,1])<.7)&(p[:,2]>3.76)]
  assert len(q) and abs(q[:,2].min()-3.763)<.001,'HVAC lifted'
  ds=hits(t[t[:,:,2].max(axis=1)<3.764],np.array([x,0,3.77]),np.array([0.,0,-1.]));assert len(ds) and min(ds)<.01,'roof support missing'
def rejected(fn):
 try:fn()
 except AssertionError:return
 raise AssertionError('fault escaped')
def components(t):
 parent=list(range(len(t)));edge={}
 def find(i):
  while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
  return i
 points=np.rint(t*1e5).astype(np.int64)
 for i,tri in enumerate(points):
  keys=[tuple(p) for p in tri]
  for j in range(3):
   k=tuple(sorted((keys[j],keys[(j+1)%3])))
   if k in edge:parent[find(i)]=find(edge[k])
   else:edge[k]=i
 groups={}
 for i in range(len(t)):groups.setdefault(find(i),[]).append(i)
 return [np.array(v,dtype=int) for v in groups.values()]
def no_duplicates(t):
 seen=set()
 for tri in np.rint(t*1e5).astype(np.int64):
  keys=[tuple(p) for p in tri];key=min(tuple(keys[i:]+keys[:i]) for i in range(3))
  assert key not in seen,'same-oriented duplicated surface/equipment'
  seen.add(key)
def wheels_components(t,groups):
 found=[]
 for ids in groups:
  p=t[ids].reshape(-1,3);lo=p.min(axis=0);hi=p.max(axis=0);size=hi-lo;c=(lo+hi)/2
  if abs(c[2]-.425)<.001 and size[0]>.848 and size[2]>.848 and .095<size[1]<.105:found.append((ids,c))
 assert len(found)==8,('missing/extra solid tyre',len(found))
 expected=[(x,y) for x in [-7.8,-5.7,5.7,7.8] for y in [-.7675,.7675]]
 for x,y in expected:assert sum(abs(c[0]-x)+abs(c[1]-y)<.001 for _,c in found)==1,'wrong axle station/gauge'
 return [ids for ids,_ in found]
def hvac_components(t,groups,baggage):
 found=[]
 for ids in groups:
  p=t[ids].reshape(-1,3);lo=p.min(axis=0);hi=p.max(axis=0);size=hi-lo;c=(lo+hi)/2
  if abs(lo[2]-3.763)<.0001 and size[0]>1.7 and abs(size[1]-1.35)<.001 and abs(size[2]-.14)<.001:found.append((ids,c))
 expected=[8.05] if baggage else [-6.25,6.25]
 assert len(found)==len(expected),'missing/duplicated HVAC shell'
 for x in expected:assert sum(abs(c[0]-x)<.001 for _,c in found)==1,'HVAC moved'
 return [ids for ids,_ in found]
def socket(t,half):
 ds=hits(t,np.array([half+.20,0,.805]),np.array([-1.,0,0]))
 assert len(ds) and min(ds)>.35,'coupler socket filled or plate protrudes'
root=Path(sys.argv[1]);manifest=json.loads((root/'manifest.json').read_text());rows=[]
for m in manifest['models']:
 if m.get('native_kind')=='assembly':continue
 t,f=read(root/m['native']);groups=components(t);ids=glazing(t,f);wheels(t);roof(t,'-dmb' in m['id']);no_duplicates(t)
 tyres=wheels_components(t,groups);hvac=hvac_components(t,groups,'-dmb' in m['id'])
 # Move each actual connected glass solid, including its backing and walls.
 glass_set=set(int(i) for i in ids)
 glass_groups=[g for g in groups if any(int(i) in glass_set for i in g)]
 q=t.copy()
 for group in glass_groups:
  chosen=[i for i in group if int(i) in glass_set];direction=normals(t)[chosen].mean(axis=0);direction/=np.linalg.norm(direction)
  q[group]-=direction*.15
 rejected(lambda:glazing(q,f))
 q=t.copy()
 for group in glass_groups:
  chosen=[i for i in group if int(i) in glass_set];direction=normals(t)[chosen].mean(axis=0);direction/=np.linalg.norm(direction)
  q[group]+=direction*.15
 rejected(lambda:glazing(q,f))
 q=t.copy();q[tyres[0],:,2]+=.04;rejected(lambda:wheels_components(q,components(q)))
 keep=np.ones(len(t),dtype=bool);keep[tyres[0]]=False;rejected(lambda:wheels_components(t[keep],components(t[keep])))
 q=t.copy();q[tyres[0],:,0]+=.20;rejected(lambda:wheels_components(q,components(q)))
 q=t.copy();q[hvac[0],:,2]+=.08;rejected(lambda:hvac_components(q,components(q),'-dmb' in m['id']))
 q=np.concatenate([t,t[hvac[0]]]);rejected(lambda:no_duplicates(q))
 shifted=t[hvac[0]].copy();shifted[:,:,0]+=.20;q=np.concatenate([t,shifted]);rejected(lambda:hvac_components(q,components(q),'-dmb' in m['id']))
 q=np.concatenate([t,t[:20]]);rejected(lambda:no_duplicates(q))
 cab=any('-'+r in m['id'] for r in ['dmc1','dmc2','dme1','dmb'])
 if cab:
  socket(t,10.39)
  plug=np.array([[[10.39,-.11,.69],[10.39,.11,.69],[10.39,.11,.92]],[[10.39,-.11,.69],[10.39,.11,.92],[10.39,-.11,.92]]])
  rejected(lambda:socket(np.concatenate([t,plug]),10.39))
 rows.append({'id':m['id'],'glass_samples':len(ids),'glass_solids':len(glass_groups),'solid_tyres':len(tyres),'hvac_shells':len(hvac),'nine_actual_geometry_faults_rejected':True,'coupler_socket_and_plate_fault':cab})
def formation(spec, fleet, far):
 suffix='-far' if far else ''
 roles=['dmc1','mc1','mc2','dmc2'] if fleet=='1000' else ['dme1','me1','me3','me4','dmb']
 expected=['taoyuan-airport-'+r+suffix for r in roles]
 assert [x['unit'] for x in spec['placements']]==expected,'missing baggage/wrong role/order'
 assert [x['rotation_degrees'] for x in spec['placements']]==[0]*(len(roles)-1)+[180],'direction/double reversal'
 lengths=[20.78 if r in ['dmc1','dmc2','dme1','dmb'] else 20.25 for r in roles];cursor=sum(lengths)/2
 for p,length in zip(spec['placements'],lengths):
  x=cursor-length/2;cursor-=length
  assert np.max(np.abs(np.array(p['translation'])-[x,0,0]))<1e-5,'wrong placement'
for m in manifest['models']:
 if m.get('native_kind')!='assembly':continue
 fleet='1000' if '1000' in m['id'] else '2000';far=m['id'].endswith('-far')
 spec=json.loads((root/m['native']).read_text());formation(spec,fleet,far)
 import copy
 q=copy.deepcopy(spec);q['placements'].pop();rejected(lambda:formation(q,fleet,far))
 q=copy.deepcopy(spec);q['placements'][-1]['rotation_degrees']=0;rejected(lambda:formation(q,fleet,far))
 q=copy.deepcopy(spec);q['placements'][0]['translation'][0]+=.1;rejected(lambda:formation(q,fleet,far))
 q=copy.deepcopy(spec);q['placements'][0],q['placements'][1]=q['placements'][1],q['placements'][0];rejected(lambda:formation(q,fleet,far))
(root/'taoyuan-verification.json').write_text(json.dumps({'status':'VERIFIED','models':rows,'assembly_faults':['lost baggage/role','wrong order','double reversal','100mm misplaced car'],'limits':'actual connected solids and centroid visibility/support rays; not exhaustive collision or engineering certification'},indent=2)+'\n')
print('VERIFIED',len(rows),'units, nine actual-geometry faults each and four assembly fault classes')
