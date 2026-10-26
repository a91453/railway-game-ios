"""Independent PP native triangle rays/distances. No recipe station tables imported.
Tests all eight final PP near/far units; E500/comparison geometry is excluded.
Contact graph samples actual triangles, not merely overlapping bounding boxes.
"""
import sys,json,struct,collections
from pathlib import Path
import numpy as np
root=Path(sys.argv[1]);manifest=json.loads((root/'manifest.json').read_text())
def read(path):
 b=path.read_bytes();count,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4;p=[];c=[]
 for i in range(count):
  row=[struct.unpack_from('<fffI',b,start+i*52+4+j*16) for j in range(3)]
  p.append([v[:3] for v in row]);c.append([v[3] for v in row])
 return np.array(p),np.array(c,dtype=np.uint32)
def nearest(origin,direction,triangles,allow_contact=False):
 a=triangles[:,0];e1=triangles[:,1]-a;e2=triangles[:,2]-a;h=np.cross(direction,e2);det=np.einsum('ij,ij->i',e1,h);valid=np.abs(det)>1e-10
 f=np.zeros_like(det);f[valid]=1/det[valid];s=origin-a;u=f*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1);v=f*np.einsum('j,ij->i',direction,q);t=f*np.einsum('ij,ij->i',e2,q)
 mask=valid&(u>=-1e-6)&(v>=-1e-6)&(u+v<=1.000001)&(t>=-0.000001 if allow_contact else t>0.00001)
 return float(np.min(t[mask])) if mask.any() else float('inf')
def backing_distance(origin,triangles):
 # Exact point-to-triangle distance: planar projection when inside, otherwise
 # closest point on each edge. Unlike a tangent normal ray, a pane's thin
 # perimeter cannot manufacture a false gap to its supporting body.
 a=triangles[:,0];e=triangles[:,1]-a;f=triangles[:,2]-a;w=origin-a
 ee=np.einsum('ij,ij->i',e,e);ef=np.einsum('ij,ij->i',e,f);ff=np.einsum('ij,ij->i',f,f)
 ew=np.einsum('ij,ij->i',e,w);fw=np.einsum('ij,ij->i',f,w);den=ee*ff-ef*ef
 good=den>1e-16;u=np.zeros(len(a));v=np.zeros(len(a));u[good]=(ff[good]*ew[good]-ef[good]*fw[good])/den[good];v[good]=(ee[good]*fw[good]-ef[good]*ew[good])/den[good]
 inside=good&(u>=0)&(v>=0)&(u+v<=1)
 projected=a+e*u[:,None]+f*v[:,None];best=np.where(inside,np.einsum('ij,ij->i',origin-projected,origin-projected),np.inf)
 for j in range(3):
  x=triangles[:,j];d=triangles[:,(j+1)%3]-x;length=np.einsum('ij,ij->i',d,d);t=np.clip(np.divide(np.einsum('ij,ij->i',origin-x,d),length,out=np.zeros(len(x)),where=length>1e-16),0,1)
  delta=origin-x-d*t[:,None];best=np.minimum(best,np.einsum('ij,ij->i',delta,delta))
 return float(np.sqrt(best.min()))
def components(p):
 parent=list(range(len(p)));edges={}
 def find(i):
  while i!=parent[i]:parent[i]=parent[parent[i]];i=parent[i]
  return i
 for i,t in enumerate(p):
  for point in t:
   key=tuple(np.round(point,5));other=edges.setdefault(key,i);a,b=find(i),find(other);parent[a]=b
 groups=collections.defaultdict(list)
 for i in range(len(p)):groups[find(i)].append(i)
 return [np.array(v) for v in groups.values()]

glass=int(manifest['palette']['glass']);tire=int(manifest['palette']['tire']);records=[]
for m in manifest['models']:
 if m['category']!='section':continue
 p,c=read(root/m['native']);g=np.all(c==glass,axis=1);back=p[~g];dist=[];visibility=[]
 visible=np.ones(len(back),dtype=bool);dividers=0
 for ids in components(back):
  pts=back[ids].reshape(-1,3);lo=pts.min(axis=0);hi=pts.max(axis=0);span=hi-lo
  if .45<span[0]<.80 and span[1]<.02 and .020<span[2]<.030 and 2.73<lo[2]<2.75 and min(abs(lo[1]),abs(hi[1]))>1.46:
   visible[ids]=False;dividers+=1
 visible_back=back[visible]
 for t in p[g]:
  n=np.cross(t[1]-t[0],t[2]-t[0]);length=np.linalg.norm(n)
  if length<1e-10:continue
  n/=length;o=t.mean(axis=0)
  # Test the outer broad surface of every pane, excluding its intentional edge walls/back.
  outward=(abs(n[1])>.95 and n[1]*o[1]>0) or (abs(n[0])>.95 and n[0]*o[0]>0)
  if not outward:continue
  d=backing_distance(o,back);assert d<.080,(m['id'],'unsupported actual glass',d,o)
  hit=nearest(o+n*.001,n,visible_back);assert hit>.10,(m['id'],'actual glass hidden by shell/frame',hit,o)
  dist.append(d);visibility.append((o,n))
 assert len(visibility)>20,(m['id'],'missing pane front samples')
 # An entire genuine connected pane is moved; the non-glass shell remains fixed.
 gp=p[g];groups=components(gp)
 side_groups=[ids for ids in groups if abs(gp[ids].mean(axis=(0,1))[1])>1.40]
 ids=max(side_groups,key=len);solid=gp[ids];centre=solid.mean(axis=(0,1));n=np.array([0.,np.sign(centre[1]),0.])
 floating=solid+n;buried=solid-n*.20
 def supported_glass(s):
  for t in s:
   normal=np.cross(t[1]-t[0],t[2]-t[0]);norm=np.linalg.norm(normal)
   if norm<1e-10 or np.dot(normal/norm,n)<.95:continue
   assert backing_distance(t.mean(axis=0),back)<.080,'unsupported pane'
 def visible_glass(s):
  for t in s:
   normal=np.cross(t[1]-t[0],t[2]-t[0]);norm=np.linalg.norm(normal)
   if norm<1e-10 or np.dot(normal/norm,n)<.95:continue
   assert nearest(t.mean(axis=0)+n*.001,n,back)>.25,'buried pane'
 for mutation,check in [(floating,supported_glass),(buried,visible_glass)]:
  try:check(mutation)
  except AssertionError:pass
  else:raise AssertionError('connected pane mutation missed')
 def tread(points):assert abs(points[:,2].min())<1e-5,'floating tire'
 black=np.all(c==tire,axis=1);tp=p[black];wheel=[]
 for ids in components(tp):
  points=tp[ids].reshape(-1,3);lo=points.min(axis=0);hi=points.max(axis=0);size=hi-lo
  # Eight actual passenger-car tire solids, detected by shape/material, not recipe centres.
  if .80<size[0]<.90 and .14<size[1]<.20 and .80<size[2]<.90:
   tread(points);o=np.array([(lo[0]+hi[0])/2,(lo[1]+hi[1])/2,hi[2]])
   d=nearest(o,np.array([0.,0.,1.]),p[~black]);assert .04<d<.35,(m['id'],'wheel top clearance',d,o)
   raised=points.copy();raised[:,2]+=.25
   try:tread(raised)
   except AssertionError:pass
   else:raise AssertionError('raised-wheel mutation missed')
   wheel.append(d)
 assert len(wheel)==8,(m['id'],'actual independent tire count',len(wheel))
 groups=components(p);bounds=[(p[ids].min(axis=(0,1)),p[ids].max(axis=(0,1))) for ids in groups]
 roof=[i for i,(lo,hi) in enumerate(bounds) if lo[2]>=3.29]
 bogie=[i for i,(lo,hi) in enumerate(bounds) if hi[2]<1.04 and lo[0]*hi[0]>0 and min(abs(lo[0]),abs(hi[0]))>5 and max(abs(lo[0]),abs(hi[0]))<9.0 and max(abs(lo[1]),abs(hi[1]))<1.3]
 equipment=set(roof+bogie);roots=set(range(len(groups)))-equipment;graph=collections.defaultdict(set);axes=np.vstack((np.eye(3),-np.eye(3)))
 for i in sorted(equipment):
  lo,hi=bounds[i];points=np.concatenate((np.unique(p[groups[i]].reshape(-1,3),axis=0),p[groups[i]].mean(axis=1)))
  if len(points)>40:points=points[np.linspace(0,len(points)-1,40,dtype=int)]
  for j,(low,high) in enumerate(bounds):
   if i==j or np.any(hi+.065<low) or np.any(high+.065<lo):continue
   target=p[groups[j]];touch=False
   for o in points:
    if any(nearest(o,d,target,True)<=.065 for d in axes):touch=True;break
   if touch:graph[i].add(j);graph[j].add(i)
 reached=set(roots);stack=list(roots)
 while stack:
  for j in graph[stack.pop()]-reached:reached.add(j);stack.append(j)
 assert equipment<=reached,(m['id'],'equipment has no actual sampled support path',equipment-reached)
 # Verify large AC housings sit on the actual faceted roof, rather than burying
 # an arbitrary bottom deep in the car. Signed separation tolerates 20 mm of
 # differing polygon tessellation; it is a virtual display tolerance, not a real fit.
 shell=next(i for i,(lo,hi) in enumerate(bounds) if hi[0]-lo[0]>19 and hi[2]-lo[2]>2)
 housings=[i for i in roof if bounds[i][1][0]-bounds[i][0][0]>2 and bounds[i][1][1]-bounds[i][0][1]>2 and bounds[i][1][2]>4]
 assert len(housings)==2,(m['id'],'large AC casing count',len(housings))
 seats=[]
 for i in housings:
  for t in p[groups[i]]:
   normal=np.cross(t[1]-t[0],t[2]-t[0]);normal/=np.linalg.norm(normal)
   if normal[2]>-.3:continue
   d=nearest(t.mean(axis=0)+np.array([0.,0.,.03]),np.array([0.,0.,-1.]),p[groups[shell]])-.03
   assert -.020<d<.030,(m['id'],'AC casing is floating or buried',d)
   seats.append(d)
 selected=next(i for i in bogie if bounds[i][0][1]>.90 and bounds[i][1][0]-bounds[i][0][0]>3)
 moved=p[groups[selected]]+np.array([0.,2.,0.]);other=np.delete(p,groups[selected],axis=0)
 assert min(backing_distance(t.mean(axis=0),other) for t in moved)>.065,'floating actual bogie frame mutation missed'
 records.append({'id':m['id'],'expected_narrow_window_dividers_excluded':dividers,'outward_glazing_triangle_samples':len(visibility),'maximum_glass_backing_distance_m':max(dist),'actual_tires':len(wheel),'minimum_upper_tire_clearance_m':min(wheel),'roof_solids_with_sampled_support_path':len(roof),'bogie_solids_with_sampled_support_path':len(bogie),'AC_bottom_roof_signed_gap_range_m':[min(seats),max(seats)],'AC_bottom_triangle_samples':len(seats),'defect_mutations_rejected':['whole connected pane floated','whole connected pane buried','each tire raised','actual bogie side frame floated']})
 print('support',m['id'],len(visibility),'glass samples,',len(wheel),'tires',flush=True)
(root/'support-verification.json').write_text(json.dumps({'status':'VERIFIED','models':records,'limits':'Static triangle-centroid glass rays; each tire top centre clearance; 65mm contact graph with up to40 actual vertices/centroids in6 directions per solid; AC bottom +/-20/30mm virtual faceting tolerance. No exhaustive self-intersection/all-surface collision, hidden equipment, suspension or animation claim.'},indent=2)+'\n')
