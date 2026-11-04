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
 def hull(self,L,W,double=False):
  # Closed, solid lower hull with chine and sealed deck; no hollow back faces.
  outline=[(-L/2,-W*.31),(-L*.38,-W/2),(L*.32,-W/2),(L/2,-W*.18),(L/2,W*.18),(L*.32,W/2),(-L*.38,W/2),(-L/2,W*.31)]
  if double: outline=[(-L/2,-W*.31),(-L*.38,-W/2),(L*.38,-W/2),(L/2,-W*.31),(L/2,W*.31),(L*.38,W/2),(-L*.38,W/2),(-L/2,W*.31)]
  p=[(x*.92,y*.72,-.84) for x,y in outline]+[(x,y,.65) for x,y in outline]
  self.solid('sealed-chined-hull',p,[list(range(7,-1,-1)),list(range(8,16))]+[[i,(i+1)%8,(i+1)%8+8,i+8] for i in range(8)],'red' if double else 'white')
  # Raised bulwark is made of closed beams, with inner/outer/top/end faces.
  for i,(x,y) in enumerate(outline):
   xx,yy=outline[(i+1)%8];self.beam('bulwark',(x,y,.78),(xx,yy,.78),.26,'white');self.beam('rubbing-strake',(x,y,.37),(xx,yy,.37),.10,'dark')
 def cabin(self,x,y,z,l,w,h,lod):
  self.box('wheelhouse',x,y,z,l,w,h,'white')
  for sy in (-1,1):
   for i in range(2 if lod else 4):
    n=2 if lod else 4
    self.box('wheelhouse-window',x-l/2+(i+.5)*l/n,y+sy*(w/2+.012),z+.62,l/n-.10,.024,h-.78,'glass',1)
  for sx in (-1,1):self.box('wheelhouse-end-window',x+sx*(l/2+.012),y,z+.62,.024,w-.25,h-.78,'glass',1)
  self.box('wheelhouse-roof',x,y,z+h,l+.35,w+.35,.14,'white')
 def lamps(self,x,z,w):
  for y,c in [(w/2,'red'),(-w/2,'green')]:
   self.box('nav-mount',x,y,z,.22,.22,.12,'dark');self.box('port-red' if y>0 else 'starboard-green',x,y,z+.12,.17,.17,.16,c,1)
  self.box('mast',x,0,z,.075,.075,1.6,'steel');self.box('masthead-white',x,0,z+1.6,.17,.17,.18,'white',1)
 def ferry(self,kind,lod):
  if kind=='tamsui':
   L,W=18.,4.43;self.hull(L,W)
   self.box('passenger-deck',-.25,0,.65,15.1,3.9,.12,'deck')
   # Open passenger saloon, supported upper promenade, forward wheelhouse.
   for y in (-1.98,1.98):
    for x in [-6.9,-4.6,-2.3,0,2.3,4.6,6.1]:self.box('saloon-pillar',x,y,.77,.16,.16,2.,'white')
    self.box('saloon-sill',-.4,y,.77,14.0,.13,.48,'white')
    self.beam('saloon-handhold',(-7.1,y,1.66),(6.2,y,1.66),.055,'steel')
   self.box('upper-deck',-.4,0,2.77,14.7,4.16,.18,'white');self.box('blue-belt',-.4,0,2.77,14.74,4.18,.08,'blue')
   self.cabin(4.8,0,2.95,2.6,3.4,1.55,lod)
   for y in (-1.94,1.94):self.rail('upper',(-7.3,y,2.95),(3.3,y,2.95),lod)
   self.rail('stern',(-7.3,-1.94,2.95),(-7.3,1.94,2.95),lod)
   for x in ([-5,-1,2] if lod else [-5.8,-3.7,-1.6,.5,2.6]):
    for y in (-1.15,1.15):self.bench(x,y,.77,lod)
   self.box('funnel',-1,0,2.95,.62,.58,.95,'white');self.box('funnel-cap',-1,0,3.90,.68,.64,.15,'dark')
   self.lamps(4.8,4.64,3.4)
   for y in (-2.10,2.10):
    for x in (-5,1):self.box('ring-bracket',x,y,1.10,.18,.12,.7,'steel');self.ring('life-ring',x,y+math.copysign(.145,y),1.47,.30,'red',8 if lod else 16)
  elif kind=='cijin':
   L,W=25.3,8.2;self.hull(L,W,True)
   self.box('vehicle-deck',0,0,.65,22,7.6,.12,'deck')
   # Open through vehicle lane, low end bulwarks, two opposite loading ends.
   for y in (-3.7,3.7):
    if y<0: self.box('lower-bulwark',0,y,.77,20.6,.18,.95,'white')
    else:
     for x,l in [(-9.4,1.8),(0,10),(9.4,1.8)]:self.box('lower-bulwark',x,y,.77,l,.18,.95,'white')
    for x in [-9,-6,-3,0,3,6,9]:self.box('lower-pillar',x,y,1.72,.20,.20,1.5,'white')
    if y<0:self.beam('lower-rail',(-10,y,2.18),(10,y,2.18),.06,'steel')
    else:self.beam('lower-rail',(-5,y,2.18),(5,y,2.18),.06,'steel')
   for x in (-11.2,11.2):
    self.box('end-threshold',x,0,.77,1.0,4.,.10,'steel')
    for y in (-2.85,2.85):self.rail('end-gate-side',(x,y,.88),(x,-math.copysign(2.1,y),.88),lod)
   # Port-side boarding openings; steps meet the upper deck edge.
   for i in range(10):self.box('stair',-5.5+i*.24,2.4,.77,.24,1.,(i+1)*.245,'steel')
   self.box('upper-deck',0,0,3.22,22.2,7.8,.18,'white')
   self.box('red-saloon',0,0,3.40,12.8,6.5,2.15,'red')
   for y in (-3.27,3.27):
    for i in range(5 if lod else 9):
     n=5 if lod else 9;x=-6.4+(i+.5)*12.8/n
     self.box('saloon-window',x,y,4.05,12.8/n-.18,.04,1.25,'glass')
   for y in (-3.75,3.75):
    for x in [-6.5,-4.3,-2.1,.1,2.3,4.5,6.5]:self.box('upper-pillar',x,y,3.40,.16,.16,2.15,'white')
    self.rail('promenade',(-10.8,y,3.40),(10.8,y,3.40),lod)
    # Swept shoulders distinguish this vessel's three deck silhouette.
    for sign in (-1,1):self.beam('sloping-shoulder',(sign*10.7,y,3.40),(sign*6.5,y,5.55),.22,'white')
   self.box('bridge-deck',0,0,5.55,13.8,7.9,.18,'white')
   self.cabin(0,0,5.73,11.8,6.6,1.9,lod)
   for y in (-3.65,3.65):self.rail('bridge-walk',(-6.4,y,5.73),(6.4,y,5.73),lod)
   for x in (-8.6,8.6):
    for y in (-2.4,2.4):self.bench(x,y,3.40,lod)
   for y in (-4.02,4.02):
    for x in (-8,8):
     self.box('ring-mount',x,y,3.60,.16,.12,.7,'steel');self.ring('life-ring',x,y+math.copysign(.145,y),3.97,.35,'red',8 if lod else 16)
    if not lod:
     for x in [-9,-6,-3,0,3,6,9]:
      self.box('fender-mount',x,y,.32,.15,.18,.60,'steel');self.ring('tyre-fender',x,y+math.copysign(.145,y),.53,.39,'dark')
   self.lamps(0,7.77,6.6)
   self.box('mast-crossbar',0,0,8.4,.08,2.2,.08,'steel')
  else: raise ValueError(kind)
  return {'waterline':[0,0,0],'boarding':[L*.40,0,.77],'length_m':L,'beam_m':W}

 def dockpart(self,kind,lod):
  if kind=='pontoon':
   for y in (-2.1,2.1):self.box('float',0,y,-.50,8.,1.30,.95,'dark')
   self.box('deck',0,0,.45,8.,6.,.20,'wood')
   if not lod:
    for x in range(-3,4):self.box('deck-join',x,0,.65,.025,5.9,.012,'deck')
   for y in (-2.75,2.75):
    for x in (-3.6,3.6):self.box('bollard',x,y,.65,.18,.18,.30,'steel');self.box('bollard-cap',x,y,.95,.38,.18,.07,'steel')
   return {'waterline':[0,0,0],'deck':[0,0,.65],'gangwayRoller':[-4,0,.65]}
  if kind=='gangway':
   self.box('shore-base',-.20,0,-.40,.40,2.8,.28,'steel')
   for y in (-1.25,1.25):self.box('hinge-cheek',0,y,-.12,.34,.20,.24,'steel')
   self.beam('hinge-pin',(0,-1.35,0),(0,1.35,0),.12,'steel')
   start=len(self.t);self.box('ramp-deck',3.05,0,-.12,6.1,2.2,.12,'deck')
   for y in (-1.05,1.05):
    self.rail('ramp-rail',(0,y,0),(6.1,y,0),lod)
    self.beam('ramp-edge',(0,y,-.06),(6.1,y,-.06),.13,'steel')
   if not lod:
    for i in range(1,24):self.box('anti-slip',i*.25,0,0,.035,1.92,.012,'steel')
   theta=-math.asin(1/6.1)
   self.transform(start,lambda p:(math.cos(theta)*p[0]-math.sin(theta)*p[2],p[1],math.sin(theta)*p[0]+math.cos(theta)*p[2]))
   return {'hinge':[0,0,0],'roller':[math.sqrt(6.1**2-1),0,-1], 'joint':{'type':'rotation','units':'radians','pivot':[0,0,0],'axis':[0,-1,0],'limit':[-.25,.25],'rest':theta,'movingTriangleStart':start,'movingTriangleCount':len(self.t)-start},'waterLevelFormula':'end z = pivot z + 6.1*sin(theta); roller slides on pontoon deck; illustrative range only'}
  if kind=='shelter':
   self.box('floor',0,0,0,5.8,4.2,.12,'deck')
   for x in (-2.5,2.5):
    for y in (-1.7,1.7):self.box('column',x,y,.12,.14,.14,2.5,'steel')
   self.box('canopy',0,0,2.62,5.9,4.3,.16,'blue')
   self.box('canopy-ridge',0,0,2.78,5.9,.20,.14,'blue')
   for x in (-1.3,1.3):self.bench(x,1.15,.12,lod)
   return {'ground':[0,0,0]}
  if kind=='railing':
   for x in ([-1.45,1.45] if lod else [-1.45,-1.45+2.9/3,-1.45+5.8/3,1.45]):self.box('foot',x,0,0,.20,.20,.06,'steel')
   self.rail('rail',(-1.45,0,.06),(1.45,0,.06),lod)
   return {'mount':[0,0,0],'endA':[-1.45,0,1.06],'endB':[1.45,0,1.06]}
  if kind=='ticket':
   self.box('plinth',0,0,0,2.4,2.2,.12,'deck');self.box('kiosk',0,0,.12,2.1,1.9,2.3,'white')
   self.box('front-window',1.06,0,1.02,.02,1.45,.90,'glass',1)
   self.box('counter',1.2,0,.92,.5,1.65,.10,'wood');self.box('roof',0,0,2.42,2.6,2.4,.18,'blue')
   if not lod:self.box('door',-.4,-.96,.12,.85,.02,1.95,'steel');self.box('door-window',-.4,-.98,1.02,.65,.02,.80,'glass')
   return {'ground':[0,0,0],'counter':[1.2,0,1.02]}
  raise ValueError(kind)
 def dock(self,lod):
  placements=[('pontoon',(0,0,0)),('gangway',(-10,0,1.65)),('shelter',(-13,0,1.65)),('ticket',(-13,4,1.65)),('railing',(0,2.75,.65)),('railing',(0,-2.75,.65))]
  joints=[]
  for part,offset in placements:
   start=len(self.t);meta=self.dockpart(part,lod);self.transform(start,lambda p:add(p,offset))
   if 'joint' in meta:
    j=meta['joint'];j['pivot']=list(offset);joints.append(j)
  # Shore landings under shelter and kiosk, with vertical closed edges.
  self.box('shore-landing',-13,1.8,.90,6.4,9.0,.75,'deck')
  return {'placements':[{'part':p,'translation':o} for p,o in placements],'joints':joints,'waterline':[0,0,0]}

def write_model(root,id,name,mesh,meta):
 mesh.validate(); folder=root/id/'revision-1';folder.mkdir(parents=True,exist_ok=True)
 provenance=json.dumps({'asset':{'generator':'ferry-studies/produce.py','version':'1'},'extras':{'id':id,'studiesOnly':True,'coordinates':'metres +x bow +y port +z up','solids':mesh.solids}},separators=(',',':')).encode()
 out=bytearray(struct.pack('<4sHHII',b'M3DM',1,0,len(mesh.t),len(provenance))+provenance);out+=bytes((-len(provenance))%4)
 for v,c,g in mesh.t:
  out+=struct.pack('<I',g)
  rgba=(c>>16&255)|((c>>8&255)<<8)|((c&255)<<16)|0xff000000
  for p in v:out+=struct.pack('<fffI',*p,rgba)
 path=folder/(id+'.m3dmodel');path.write_bytes(out)
 return dict(id=id,name=name,native=str(path.relative_to(root)),triangles=len(mesh.t),connectors=meta,solids=len(mesh.solids))

def main():
 ap=argparse.ArgumentParser();ap.add_argument('output',type=Path);ap.add_argument('group',choices=['tamsui','cijin','dock']);args=ap.parse_args();root=args.output.resolve()
 assert Path(__file__).resolve().parents[2] not in root.parents,'Output must be outside game checkout'
 root.mkdir(parents=True,exist_ok=True);mf=root/'manifest.json';manifest=json.loads(mf.read_text()) if mf.exists() else {'schema_version':1,'directions':['top','bottom','left','right','front','back','isometric'],'models':[]}
 records=[]
 for lod in (False,True):
  kinds=['pontoon','gangway','shelter','railing','ticket','assembly'] if args.group=='dock' else [args.group]
  names={'pontoon':'浮台','gangway':'水位跳板','shelter':'候船亭','railing':'欄杆','ticket':'售票小亭','assembly':'浮動碼頭組','tamsui':'淡水渡輪','cijin':'旗津渡輪'}
  for kind in kinds:
   m=Mesh();meta=(m.dock(lod) if kind=='assembly' else m.dockpart(kind,lod)) if args.group=='dock' else m.ferry(kind,lod)
   id=(('dock-'+kind) if args.group=='dock' else kind)+('-lod' if lod else '-near')
   records.append(write_model(root,id,names[kind]+('・遠景' if lod else '・近景'),m,meta))
 manifest['models']=[r for r in manifest['models'] if r['id'] not in [x['id'] for x in records]]+records
 mf.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');print([(r['id'],r['triangles']) for r in records])
if __name__=='__main__':main()
