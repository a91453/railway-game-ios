#!/usr/bin/env python3
"""Original studies recipes, native x forward / y port / z up, metres.
No runtime imports or registration. Closed solids; touching mounting faces.
"""
import argparse, collections, hashlib, json, math, struct
from pathlib import Path
P=dict(white=0xEDEFF0,blue=0x5F8BC0,red=0xC65A4E,green=0x5E8F86,steel=0x6E747B,dark=0x26385C,deck=0xDCD6C8,glass=0x9DB3C2,warm=0xFFE2A6,wood=0x8E6E52)
def add(a,b): return tuple(x+y for x,y in zip(a,b))
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def mul(a,s): return tuple(x*s for x in a)
def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def unit(a): return mul(a,1/math.sqrt(sum(x*x for x in a)))
class Mesh:
 def __init__(self): self.t=[]; self.solids=[]
 def solid(self,name,vertices,faces,color,glow=0):
  start=len(self.t)
  for f in faces:
   for i in range(1,len(f)-1): self.t.append(([vertices[k] for k in (f[0],f[i],f[i+1])],P.get(color,color),glow))
  self.solids.append(dict(name=name,start=start,count=len(self.t)-start))
 def box(self,name,x,y,z,l,w,h,c,glow=0):
  v=[(x+sx*l/2,y+sy*w/2,z+sz*h) for sz in (0,1) for sy in (-1,1) for sx in (-1,1)]
  self.solid(name,v,[[0,2,3,1],[4,5,7,6],[0,1,5,4],[1,3,7,5],[3,2,6,7],[2,0,4,6]],c,glow)
 def beam(self,name,a,b,r,c):
  d=unit(sub(b,a)); u=mul(unit(cross(d,(0,0,1) if abs(d[2])<.95 else (0,1,0))),r/2);v=mul(cross(d,unit(u)),r/2)
  p=[add(q,add(mul(u,s),mul(v,t))) for q in (a,b) for s,t in [(-1,-1),(1,-1),(1,1),(-1,1)]]
  self.solid(name,p,[[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]],c)
 def ring(self,name,x,y,z,r,c,n=16):
  # Vertical x/z torus; mounting plane y, no open ring ends.
  p=[];m=6
  for i in range(n):
   a=i*2*math.pi/n
   for j in range(m):
    b=j*2*math.pi/m; rr=r+.085*math.cos(b)
    p.append((x+rr*math.cos(a),y+.085*math.sin(b),z+rr*math.sin(a)))
  self.solid(name,p,[[i*m+(j+1)%m,((i+1)%n)*m+(j+1)%m,((i+1)%n)*m+j,i*m+j] for i in range(n) for j in range(m)],c)
 def rail(self,name,a,b,lod):
  # End posts seated on deck; rail ends meet post centres.
  steps=max(1,math.ceil(math.dist(a,b)/(3 if lod else 1.3)))
  for i in range(steps+1):
   p=add(a,mul(sub(b,a),i/steps));self.box(name+'-post',p[0],p[1],p[2],.065,.065,1.0,'steel')
  for h in ([1.] if lod else [.5,1.]): self.beam(name+'-rail',add(a,(0,0,h)),add(b,(0,0,h)),.055,'steel')
 def bench(self,x,y,z,lod):
  for dx in (-.6,.6): self.box('seat-leg',x+dx,y,z,.12,.45,.43,'steel')
  self.box('seat',x,y,z+.43,1.7,.48,.09,'blue')
  if not lod:self.box('seat-back',x,y+.20,z+.52,1.7,.08,.42,'blue')
 def transform(self,start,fn):
  self.t[start:]=[(list(map(fn,v)),c,g) for v,c,g in self.t[start:]]
 def validate(self):
  for s in self.solids:
   edges=collections.Counter();vol=0
   for v,c,g in self.t[s['start']:s['start']+s['count']]:
    assert all(math.isfinite(x) for p in v for x in p)
    assert math.sqrt(sum(x*x for x in cross(sub(v[1],v[0]),sub(v[2],v[0]))))>1e-8,(s,'zero area')
    vol+=sum(a*b for a,b in zip(v[0],cross(v[1],v[2])))/6
    for a,b in zip(v,v[1:]+v[:1]):edges[(a,b)]+=1
   assert all(edges[(b,a)]==n for (a,b),n in edges.items()),(s,'open or inconsistent edge')
   assert vol>0,(s,'inward winding',vol)
  assert 0<len(self.t)<=15000

 def support(self,kind,lod=False):
  if kind=='platform':
   self.box('island',0,0,0,8,3.3,.60,'deck')
   for y in (-1.57,1.57):self.box('edge-marking',0,y,.60,8,.16,.012,'warm')
   for i in range(3):self.box('access-step',-5.5+i*.6,0,0,.6,1.5,(i+1)*.2,'deck')
   if not lod:
    for x in [-3,-2,-1,0,1,2,3]:self.box('floor-joint',x,0,.60,.02,2.9,.008,'steel')
   return {'mount':[0,0,0],'boardingSurface':[0,0,.60],'edgeLeft':[0,1.65,.60],'edgeRight':[0,-1.65,.60], 'ropeLeft':[0,2.6,4.2],'ropeRight':[0,-2.6,4.2],'cabinFloor':.60,'nominalCabinSideGap':.10}
  if kind=='gate':
   for y in (-.77,.77):
    self.box('gate-foot',0,y,0,.38,.30,.06,'steel');self.box('gate-housing',0,y,.06,.26,.20,1.02,'white')
    self.box('gate-cap',0,y,1.08,.29,.23,.06,'green');self.box('gate-indicator',.136,y,.86,.012,.09,.10,'warm',1)
   self.beam('hinge', (0,-.65,.25),(0,-.65,1.0),.09,'steel')
   # Hinge attaches to the inner face of the negative-y housing.
   start=len(self.t)
   self.beam('leaf-top',(0,-.65,.95),(0,.65,.95),.06,'steel')
   self.beam('leaf-bottom',(0,-.65,.28),(0,.65,.28),.06,'steel')
   for y in ([-.65,.65] if lod else [-.65,-.325,0,.325,.65]):self.beam('leaf-upright',(0,y,.28),(0,y,.95),.05,'green')
   return {'mount':[0,0,0],'entry':[-.5,0,0],'exit':[.5,0,0],'joint':{'type':'rotation','units':'radians','pivot':[0,-.65,.60],'axis':[0,0,1],'limit':[0,math.pi/2],'rest':0.,'movingTriangleStart':start,'movingTriangleCount':len(self.t)-start}}
  if kind=='queue':
   for x in ([-1,1] if lod else [-1,0,1]):
    self.box('rail-foot',x,0,0,.23,.23,.05,'steel');self.box('rail-post',x,0,.05,.065,.065,.95,'steel')
   for z in ([1.] if lod else [.52,1.]):self.beam('queue-rail',(-1,0,z),(1,0,z),.055,'steel')
   return {'mount':[0,0,0],'endA':[-1,0,1],'endB':[1,0,1]}
  if kind=='catwalk':
   self.box('catwalk-pan',0,0,0,4,1.1,.16,'steel')
   if not lod:
    for i in range(19):self.box('grating-bar',-1.8+i*.2,0,.16,.025,1.0,.018,'deck')
   for y in (-.5,.5):self.rail('safety-rail',(-1.9,y,.16),(1.9,y,.16),lod)
   for x in (-1.7,1.7):self.box('mount-plate',x,0,0,.4,1.1,.05,'dark')
   return {'mountA':[-1.7,0,0],'mountB':[1.7,0,0],'surface':[0,0,.16],'installation':'mount underside z0 to a host beam; no invisible tower or floating support'}
  if kind=='kiosk':
   self.box('floor',0,0,0,2.4,2.2,.12,'deck')
   self.box('rear-wall',-.96,0,.12,.16,1.9,2.25,'white')
   for y in (-.87,.87):self.box('side-wall',0,y,.12,1.8,.16,2.25,'white')
   self.box('front-plinth',.86,0,.12,.12,1.8,.75,'white')
   self.box('front-glass',.86,0,.87,.08,1.8,1.2,'glass')
   self.box('front-header',.86,0,2.07,.12,1.8,.30,'white')
   self.box('roof',0,0,2.37,2.5,2.3,.14,'green')
   self.box('counter',1.0,0,.87,.42,1.6,.10,'wood')
   # Mounted display with an illuminated face, no branded signage.
   self.box('display-frame',.938,.45,1.35,.06,.5,.40,'dark')
   self.box('display',.971,.45,1.39,.006,.42,.32,'warm',1)
   if not lod:
    self.box('door',-.4,-.958,.12,.70,.016,1.92,'steel');self.box('door-handle',-.16,-.98,.95,.04,.028,.12,'dark')
   return {'mount':[0,0,0],'counter':[1,0,.97]}
  if kind=='assembly':
   placements=[('platform',(0,0,0)),('gate',(-1.4,0,.60)),('queue',(-2.7,-.85,.60)),('queue',(-2.7,.85,.60)),('queue',(1.0,-.85,.60)),('queue',(1.0,.85,.60)),('kiosk',(-7.5,2,0))]
   joints=[]
   for part,offset in placements:
    start=len(self.t);meta=self.support(part,lod);self.transform(start,lambda p:add(p,offset))
    if 'joint' in meta:
     j=meta['joint'];j['pivot']=list(add(j['pivot'],offset));j['movingTriangleStart']+=start;joints.append(j)
   # A separate supported maintenance module at an illustrative service bay.
   for x in (-1.7,1.7):self.box('service-stand',x,6,0,.25,1.0,2.0,'steel')
   start=len(self.t);self.support('catwalk',lod);self.transform(start,lambda p:add(p,(0,6,2)))
   return {'mount':[0,0,0],'ropeLeft':[0,2.6,4.2],'ropeRight':[0,-2.6,4.2],'boardingSurface':[0,0,.60],'joints':joints,'placements':[{'part':p,'translation':o} for p,o in placements]+[{'part':'catwalk','translation':[0,6,2]}]}
  raise ValueError(kind)

def write_model(root,id,name,mesh,meta):
 mesh.validate(); folder=root/id/'revision-1';folder.mkdir(parents=True,exist_ok=True)
 provenance=json.dumps({'asset':{'generator':'cable-support-studies/produce.py','version':'1'},'extras':{'id':id,'studiesOnly':True,'coordinates':'metres +x along rope +y left +z up','solids':mesh.solids}},separators=(',',':')).encode()
 out=bytearray(struct.pack('<4sHHII',b'M3DM',1,0,len(mesh.t),len(provenance))+provenance);out+=bytes((-len(provenance))%4)
 for v,c,g in mesh.t:
  out+=struct.pack('<I',g)
  rgba=(c>>16&255)|((c>>8&255)<<8)|((c&255)<<16)|0xff000000
  for p in v:out+=struct.pack('<fffI',*p,rgba)
 path=folder/(id+'.m3dmodel');path.write_bytes(out)
 return dict(id=id,name=name,native=str(path.relative_to(root)),triangles=len(mesh.t),connectors=meta,connectorNormals={k:([0,0,-1] if k.startswith('mount') else [0,0,1]) for k,v in meta.items() if (k.startswith('mount') or k in ['surface','boardingSurface']) and isinstance(v,list) and len(v)==3},solids=len(mesh.solids))

def main():
 ap=argparse.ArgumentParser();ap.add_argument('output',type=Path);ap.add_argument('--part',choices=['platform','gate','queue','catwalk','kiosk','assembly']);args=ap.parse_args();root=args.output.resolve()
 assert Path(__file__).resolve().parents[2] not in root.parents,'Private output required'
 root.mkdir(parents=True,exist_ok=True);mf=root/'manifest.json'
 manifest=json.loads(mf.read_text()) if mf.exists() else {'schema_version':1,'directions':['top','bottom','left','right','front','back','isometric'],'models':[],'compatibility':{'sourcePR':1782,'sourceCommit':'aaaaaca6f93da7e27d2e62df87fd0ac55979483d','ropeSpacing':5.2,'stationRopeHeight':4.2,'cabinDrop':3.6,'bodyWidth':1.7,'platformSurface':.6,'legacyStationPlatformTop':.9,'status':'studies; replace legacy platform, do not overlay; measured appearance unverified'}}
 names={'platform':'纜車乘降月台','gate':'乘降旋轉閘門','queue':'排隊欄杆','catwalk':'維修走台','kiosk':'站務售票小亭','assembly':'纜車站務組裝示例'}
 records=[]
 for kind in ([args.part] if args.part else names):
  for lod in (False,True):
   m=Mesh();meta=m.support(kind,lod);id=kind+('-lod' if lod else '-near')
   records.append(write_model(root,id,names[kind]+('・遠景' if lod else '・近景'),m,meta))
 ids={m['id'] for m in records};manifest['models']=[m for m in manifest['models'] if m['id'] not in ids]+records
 mf.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');print([(m['id'],m['triangles']) for m in records])
if __name__=='__main__':main()
