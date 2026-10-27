"""Actual solid surface contacts, independent of recipe station tables.
1mm tolerance; full triangle edges, not AABB or minimum sampled proximity.
"""
import sys,json
from pathlib import Path
import numpy as np
source=(Path(__file__).with_name('support.py')).read_text().split('# Palette is recorded')[0]
exec(source)
EPS=.001

def intersects(a,b):
 # Edge against every opposite triangle, including either segment endpoint.
 for x,y in [(a,b),(b,a)]:
  ta=y[:,0];e=y[:,1]-ta;f=y[:,2]-ta
  for tri in x:
   for i in range(3):
    o=tri[i];v=tri[(i+1)%3]-o;length=np.linalg.norm(v)
    if length<1e-9:continue
    direction=v/length;h=np.cross(direction,f);det=(e*h).sum(1);ok=np.abs(det)>1e-10
    inv=np.divide(1,det,out=np.zeros_like(det),where=ok);s=o-ta;u=inv*(s*h).sum(1);q=np.cross(s,e);w=inv*(q*direction).sum(1);t=inv*(f*q).sum(1)
    if np.any(ok&(u>=-1e-6)&(w>=-1e-6)&(u+w<=1.000001)&(t>=-EPS)&(t<=length+EPS)):return True
  # Coplanar containment/contacts; edge crossing is handled above unless
  # coplanar, and a small contained face has at least one contained vertex.
  points=np.unique(x.reshape(-1,3),axis=0)
  for o in points:
   if backing_distance(o,y)<=EPS:return True
 return False

def analyse(p):
 groups=components(p);bb=[(p[g].min(axis=(0,1)),p[g].max(axis=(0,1))) for g in groups];graph={i:set() for i in range(len(groups))}
 for i in range(len(groups)):
  for j in range(i):
   if np.any(bb[i][1]+EPS<bb[j][0]) or np.any(bb[j][1]+EPS<bb[i][0]):continue
   if intersects(p[groups[i]],p[groups[j]]):graph[i].add(j);graph[j].add(i)
 roots={i for i,(lo,hi) in enumerate(bb) if hi[0]-lo[0]>10 and hi[2]-lo[2]>2}
 reached=set(roots);stack=list(roots)
 while stack:
  for j in graph[stack.pop()]-reached:reached.add(j);stack.append(j)
 floating=[{'component':i,'triangles':len(groups[i]),'minimum':bb[i][0].tolist(),'maximum':bb[i][1].tolist()} for i in graph if i not in reached]
 return groups,bb,{'components':len(groups),'reached_body':len(reached),'floating':floating,'contacts':[[i,j] for i in graph for j in graph[i] if i<j]}

rows=[];mutations=[]
for m in manifest['models']:
 if m['category']!='section':continue
 p,c=read(root/m['native']);groups,bb,row=analyse(p);row['id']=m['id'];rows.append(row)
 print(m['id'],'floating',len(row['floating']),flush=True)
 if m['id']=='taipei610-a' and not row['floating']:
  target=max((i for i,(lo,hi) in enumerate(bb) if hi[2]<.9),key=lambda i:bb[i][1][0])
  moved=p.copy();moved[groups[target]]+=np.array([1.,0.,0.]);_,_,bad=analyse(moved)
  assert bad['floating'],'moving actual coupler did not fail'
  hanger=next(i for i,(lo,hi) in enumerate(bb) if lo[0]>7.8 and abs(lo[2]-.77)<1e-5 and abs(hi[2]-.89)<1e-5)
  removed=np.delete(p,groups[hanger],axis=0);_,_,missing=analyse(removed)
  assert len(missing['floating'])>=2,'deleting actual drawbar hanger did not disconnect drawbar and coupler'
  mutations.append({'id':m['id'],'translated_actual_coupler_component':target,'translation_m':[1,0,0],'removed_actual_hanger_component':hanger,'removed_triangles':len(groups[hanger]),'shifted_coupler_rejected':True,'missing_hanger_rejected':True})
report={'platform':'Linux NumPy; independent native triangles','tolerance_m':EPS,'method':'AABB only prunes candidates; full segment-triangle intersections plus <=1mm coplanar point-triangle contact; every component must have a contact graph path to main body; no 65mm proximity exceptions','models':rows,'actual_geometry_mutations':mutations,'limits':'static connectivity and declared 1mm tolerance, not load/stress or full dynamic collision certification'}
(root/'contact-graph-verification.json').write_text(json.dumps(report,indent=2))
assert not any(r['floating'] for r in rows),'Actual components have no contact path to body'
