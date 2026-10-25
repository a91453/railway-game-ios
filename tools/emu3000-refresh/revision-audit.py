"""Compare real revision1 native payloads and cross sections against revision2."""
from pathlib import Path
import sys,json,struct,hashlib
import numpy as np
old,new=map(Path,sys.argv[1:3]);sha=lambda b:hashlib.sha256(b).hexdigest()
def read(path):
 b=path.read_bytes();n,size=struct.unpack_from('<II',b,8);start=16+(size+3)//4*4
 payload=b[start:];tri=[]
 for i in range(n):tri.append([struct.unpack_from('<fffI',b,start+i*52+4+j*16) for j in range(3)])
 return payload,np.array(tri)
def section(t,x):
 points=[]
 for triangle in t:
  for i in range(3):
   a,b=triangle[i,:3],triangle[(i+1)%3,:3]
   if (a[0]-x)*(b[0]-x)<0:points.append(a+(b-a)*((x-a[0])/(b[0]-a[0])))
 p=np.array(points);assert len(p);return {'width_m':float(np.ptp(p[:,1])),'height_m':float(np.ptp(p[:,2]))}
rows=[]
for unit in ['em','et','em6','ep3','ep7','ep10']:
 for far in [False,True]:
  name='emu3000-'+unit+('-far' if far else '')+'.m3dmodel';a,ta=read(old/'models'/name);b,tb=read(new/'models'/name)
  if far:assert a==b,(name,'unrequested far intermediate unit changed');digest=sha(a)
  else:
   def below(payload,t):return b''.join(payload[i*52:(i+1)*52] for i in range(len(t)) if np.all(t[i,:,2]<3.39))
   aa,bb=below(a,ta),below(b,tb);assert aa==bb,(name,'body/doors/windows/wheels/underfloor changed');digest=sha(aa)
  rows.append({'id':name,'preserved':'all geometry' if far else 'all triangles below3.39m; body/windows/doors/running gear/underfloor','payload_sha256':digest})
a,ta=read(old/'models/emu3000-ed.m3dmodel');b,tb=read(new/'models/emu3000-ed.m3dmodel')
before,after=section(ta,10.60),section(tb,10.60)
assert after['height_m']>before['height_m']+0.2,'nose did not become visibly rounder/thicker'
report={'status':'VERIFIED','previous_producer':'3ab845507ec17d19eddc3ec60f0bfc976e12ff87','method':'actual native triangle payloads and intersection with model X=10.60m plane; these are model measurements, not engineering dimensions','nose_section_before':before,'nose_section_after':after,'preserved':rows}
(new/'revision-verification.json').write_text(json.dumps(report,indent=2)+'\n');print('VERIFIED previous native snapshot, rounder nose section and12 preserved intermediate regions')
