"""Revision5: real revision4 native diff and side-envelope preservation."""
from pathlib import Path
import sys,json,struct,hashlib,collections
import numpy as np
old,new=map(Path,sys.argv[1:3]);sha=lambda b:hashlib.sha256(b).hexdigest()
def read(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 return [b[start+i*52:start+(i+1)*52] for i in range(n)]
def points(t):return np.array([struct.unpack_from('<fff',t,4+j*16) for j in range(3)])
def color(t):return struct.unpack_from('<I',t,16)[0]
a_manifest=json.loads((old/'manifest.json').read_text());assert a_manifest['producer_commit']=='4b6352d8f3bb27b6ff312e7d375ad8da124eea41'
b_manifest=json.loads((new/'manifest.json').read_text());white=b_manifest['palette']['body'];mask=b_manifest['palette']['mask'];seam=(white&0xff000000)|sum(int(np.floor(np.float32((white>>s)&255)*np.float32(.74)+.5))<<s for s in [0,8,16]);rows=[]
def shell(ts):
 selected=[t for t in ts if color(t) in [white,mask]];p=np.array([points(t) for t in selected]);parent=list(range(len(p)));vertices={}
 def find(i):
  while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
  return i
 for i,t in enumerate(p):
  for v in t:
   k=tuple(np.round(v,5));j=vertices.setdefault(k,i);parent[find(i)]=find(j)
 groups=collections.defaultdict(list)
 for i in range(len(p)):groups[find(i)].append(i)
 return p[max(groups.values(),key=len)]
def envelope(p,x):
 hits=[]
 for i in range(3):
  a=p[:,i];b=p[:,(i+1)%3];good=(a[:,0]-x)*(b[:,0]-x)<0;a=a[good];b=b[good]
  if len(a):hits.extend((a[:,2]+(b[:,2]-a[:,2])*(x-a[:,0])/(b[:,0]-a[:,0])).tolist())
 return np.array([min(hits),max(hits)])
for m in b_manifest['models']:
 if m['category']!='section':continue
 a=read(old/m['native']);b=read(new/m['native']);tail='tail' in m['id'];cab=tail or '-ed' in m['id'];sign=-1 if tail else 1
 if not cab:assert a==b,(m['id'],'intermediate unit changed')
 before,after=collections.Counter(a),collections.Counter(b);removed=list((before-after).elements());added=list((after-before).elements());profile_error=0
 if cab:
  assert removed and added
  for t in removed+added:assert np.all(points(t)[:,0]*sign>=6.19999),(m['id'],'outside frontal cab',points(t))
  def gear(ts):return collections.Counter(t for t in ts if color(t) not in [white,seam] and np.all(points(t)[:,2]<1.1))
  assert gear(a)==gear(b),(m['id'],'running gear/underfloor/coupler changed')
  sa,sb=shell(a),shell(b);sa[:,:,0]*=sign;sb[:,:,0]*=sign
  for x in np.linspace(6.21,10.66,101):profile_error=max(profile_error,float(abs(envelope(sa,x)-envelope(sb,x)).max()))
  assert profile_error<.00002,(m['id'],'accepted side envelope changed',profile_error)
 preserved=before&after;old_m=next(x for x in a_manifest['models'] if x['id']==m['id']);assert m['minimum']==old_m['minimum'] and m['maximum']==old_m['maximum'],'overall bounds changed'
 rows.append({'id':m['id'],'old_triangles':len(a),'new_triangles':len(b),'removed_triangles':len(removed),'added_triangles':len(added),'preserved_triangles':sum(preserved.values()),'side_envelope_max_error_m':profile_error,'preserved_payload_sha256':sha(b''.join(sorted(preserved.elements()))),'preserved':'full intermediate payload' if not cab else 'all geometry behind x6.2; running gear/underfloor/couplers; overall bounds; actual upper/lower side envelope at101 planes'})
(new/'revision-verification.json').write_text(json.dumps({'status':'VERIFIED','previous_producer':a_manifest['producer_commit'],'method':'actual native triangle multisets; 12 intermediate payloads byte-identical; cab changes in front of x6.2; 101 actual hull-plane intersections preserve accepted side top/bottom envelope within20micrometres; virtual model measurements, not engineering dimensions','models':rows},indent=2)+'\n')
print('VERIFIED12 unchanged intermediate payloads; front cab only; 101 side-envelope planes per cab/LOD unchanged')
