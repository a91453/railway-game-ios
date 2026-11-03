#!/usr/bin/env python3
"""Native triangle probes. Read/ray/component primitives adapted from this project's
Taoyuan audit; no Taoyuan vehicle dimensions or geometry used. Photo-fit limits.
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
def glazing(t,f):
 n=normals(t);c=t.mean(axis=1)
 mask=((f&2)!=0)&(((abs(c[:,1])>1.28)&(n[:,1]*np.sign(c[:,1])>.9))|((abs(c[:,0])>5.5)&(abs(c[:,1])<1.10)&(n[:,0]*np.sign(c[:,0])>.8)))
 ids=np.flatnonzero(mask);assert len(ids),'missing visible glass'
 for i in ids:
  ds=hits(t,c[i]+n[i]*.12,-n[i]);assert len(ds) and min(ds)>.1194,('glass occluded',int(i))
  ds=hits(t[(f&2)==0],c[i]-n[i]*.002,-n[i]);assert len(ds) and min(ds)<.065,('glass lacks backing',int(i),float(min(ds)) if len(ds) else None)
 return ids

def parts(t,groups,roof,cap,axle,lateral):
 tyres=[];guides=[];hvac=[];pivots=[];springs=[]
 for ids in groups:
  p=t[ids].reshape(-1,3);lo=p.min(axis=0);hi=p.max(axis=0);size=hi-lo;c=(hi+lo)/2
  if np.max(abs(size-np.array([.32,.32,.40])))<.0002:pivots.append((ids,c,lo,hi))
  if np.max(abs(size-np.array([.36,.36,.40])))<.0002:springs.append((ids,c,lo,hi))
  if np.max(abs(size-np.array([.8,.26,.8])))<.0002:tyres.append((ids,c,lo,hi))
  if np.max(abs(size-np.array([.4,.4,.15])))<.0002:guides.append((ids,c,lo,hi))
  if abs(size[0]-2.45)<.0002 and abs(size[1]-1.62)<.0002 and abs(size[2]-cap)<.0002:hvac.append((ids,c,lo,hi))
 assert len(pivots)==2 and len(springs)==4,'missing suspension/pivot support'
 for _,c,lo,hi in pivots+springs:
  assert min(abs(c[0]-axle),abs(c[0]+axle))<.0001 and abs(lo[2]-.48)<.0001 and abs(hi[2]-.88)<.0001,'suspension support leaves axle or floor'
 assert len(tyres)==4,('missing or wrong tyre type',len(tyres))
 assert len(guides)==8,('missing or wrong guide wheel type',len(guides))
 assert len(hvac)==2,('missing/duplicate HVAC',len(hvac))
 for x in [-axle,axle]:
  for y in [-lateral,lateral]:
   matches=[q for q in tyres if abs(q[1][0]-x)+abs(q[1][1]-y)<.001];assert len(matches)==1,'wrong tyre axis'
   _,_,lo,hi=matches[0];assert abs(lo[2])<.00001 and abs(hi[2]-.8)<.00001,'tyre leaves running surface'
 for x in [-axle,axle]:
  for dx in [-.68,.68]:
   for y in [-1.02,1.02]:
    assert sum(np.linalg.norm(c-np.array([x+dx,y,.385]))<.001 for _,c,_,_ in guides)==1,'guide wheel misplaced'
 for x in [-4.1,4.1]:
  q=[q for q in hvac if abs(q[1][0]-x)<.001];assert len(q)==1,'HVAC misplaced'
  _,_,lo,_=q[0];assert abs(lo[2]-roof)<.0001,'HVAC lifted'
  ds=hits(t[t[:,:,2].max(axis=1)<lo[2]+.0001],np.array([x,0,lo[2]+.01]),np.array([0.,0,-1.]))
  assert len(ds) and min(ds)<.0101,'HVAC support missing'
 # Axle and guide-wheel envelope separation; intended axle/hub contacts excluded.
 for _,c,_,_ in tyres:
  ds=hits(t,np.array([c[0],c[1],.81]),np.array([0.,0,1.]));assert len(ds) and min(ds)>.05,'load tyre/body clearance'
 for _,c,_,_ in tyres:
  for _,g,_,_ in guides:
   if np.sign(c[1])==np.sign(g[1]) and abs(c[0]-g[0])<1:
    assert abs(c[0]-g[0])>.60,'guide/load wheel envelopes overlap longitudinally'
 return tyres,guides,hvac

def reject(fn):
 try:fn()
 except AssertionError:return
 raise AssertionError('actual geometry fault escaped')
root=Path(sys.argv[1]);manifest=json.loads((root/'manifest.json').read_text());rows=[]
for m in manifest['models']:
 if m.get('native_kind')=='assembly':continue
 t,f=read(root/m['native']);groups=components(t);no_duplicates(t);glass=glazing(t,f);roof=3.30 if 'val256' in m['id'] else 3.38;cap=(.23 if roof==3.30 else .15)-(0 if m['id'].endswith('-far') else .008);axle=4.65 if roof==3.30 else 5.0;lateral=.94 if roof==3.30 else .99;tyres,guides,hvac=parts(t,groups,roof,cap,axle,lateral)
 exterior=set(int(i) for i in glass);glass_groups=[g for g in groups if any(int(i) in exterior for i in g)]
 for sign in [-1,1]:
  q=t.copy()
  for group in glass_groups:
   chosen=[i for i in group if int(i) in exterior];direction=normals(t)[chosen].mean(axis=0);direction/=np.linalg.norm(direction);q[group]+=sign*.15*direction
  reject(lambda:glazing(q,f))
 for axis,delta,ids in [(2,.04,tyres[0][0]),(0,.20,tyres[0][0]),(0,.20,guides[0][0]),(2,.08,hvac[0][0])]:
  q=t.copy();q[ids,:,axis]+=delta;reject(lambda:parts(q,components(q),roof,cap,axle,lateral))
 keep=np.ones(len(t),dtype=bool);keep[tyres[0][0]]=False;reject(lambda:parts(t[keep],components(t[keep]),roof,cap,axle,lateral))
 # Wrong rolling axis and axial tyre profile mutate the actual complete tyre solid.
 ids,c,_,_=tyres[0];q=t.copy();local=q[ids]-c;q[ids]=local[:,:,[0,2,1]]+c;reject(lambda:parts(q,components(q),roof,cap,axle,lateral))
 q=t.copy();q[ids,:,1]=c[1]+(q[ids,:,1]-c[1])*.5;reject(lambda:parts(q,components(q),roof,cap,axle,lateral))
 keep=np.ones(len(t),dtype=bool);keep[guides[0][0]]=False;reject(lambda:parts(t[keep],components(t[keep]),roof,cap,axle,lateral))
 reject(lambda:no_duplicates(np.concatenate([t,t[hvac[0][0]]])))
 q=t[hvac[0][0]].copy();q[:,:,0]+=.2;reject(lambda:parts(np.concatenate([t,q]),components(np.concatenate([t,q])),roof,cap,axle,lateral))
 body=max(groups,key=len);reject(lambda:no_duplicates(np.concatenate([t,t[body]])))
 rows.append({'id':m['id'],'glass_front_centroid_rays':len(glass),'actual_glass_groups':len(glass_groups),'load_tyres':4,'pivot_supports':2,'air_springs':4,'guide_wheels':8,'hvac':2,'thirteen_actual_geometry_faults_rejected':True})
(root/'contact-verification.json').write_text(json.dumps({'status':'VERIFIED','models':rows,'limits':'Exterior glass centroid visibility/backing rays, connected tyres/guide wheels/HVAC and fixed photo-fit envelope/contact probes. Hidden safety/turnout gear remains a source gap. Not all intersections, all pixels, engineering accuracy or device proof.'},indent=2)+'\n');print('VERIFIED',len(rows),'role/LOD contact and visibility probes; 13 actual-geometry failures each')
