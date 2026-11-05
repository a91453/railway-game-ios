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

PARTS=('canopy8','sawtooth-island','seat-group','ticket-counter','ticket-machine','departure-board','luggage-cart','stop-sign','shelter','footbridge','lift-tower')
def part(m,k,far):
 c=[]
 if k=='canopy8':
  m.box('roof',0,0,3.35,8,4.2,.22,'blue')
  for x in (-3.55,3.55):
   for y in (-1.75,1.75):m.box('column',x,y,0,.16,.16,3.35,'steel')
  if not far:m.box('underside-light',0,0,3.29,6,.12,.035,'warm',1)
  c=[dict(name='left',position=[-4,0,0],normal=[-1,0,0]),dict(name='right',position=[4,0,0],normal=[1,0,0])]
 elif k=='sawtooth-island':
  m.box('platform',0,0,0,16,.8,.24,'deck');m.box('kerb',0,-.38,0,16,.12,.37,'white')
  m.box('angled-nose',7.2,-1.75,0,1.1,.7,.3,'warm')
  c=[dict(name='canopy',position=[0,0,.24],normal=[0,0,1])]
 elif k=='seat-group':
  for y in (-.7,.7):
   for x in (-.55,.55):m.box('seat-leg',x,y,0,.10,.10,.46,'steel')
   m.box('seat',0,y,.46,1.6,.48,.10,'blue')
   if not far:m.box('back',0,y+.23,.55,1.6,.10,.48,'blue')
 elif k=='ticket-counter':
  m.box('desk',0,0,0,3.2,.85,1.05,'white');m.box('counter-top',0,0,1.05,3.25,.95,.08,'dark')
  if not far:m.box('service-screen',0,.46,1.13,2.8,.06,.45,'glass')
 elif k=='ticket-machine':
  m.box('machine',0,0,0,.75,.56,1.76,'white');m.box('screen',0,-.292,1.12,.48,.025,.40,'dark',1)
 elif k=='departure-board':
  m.box('board',0,0,0,4,.16,1.45,'dark')
  for x in ([-1.3,0,1.3] if not far else [0]):m.box('abstract-row',x,-.087,.65,.75,.015,.08,'warm',1)
  c=[dict(name='wall',position=[0,.08,.7],normal=[0,1,0])]
 elif k=='luggage-cart':
  m.box('tray',0,0,.3,1.5,.75,.16,'steel')
  for x in (-.55,.55):
   for y in (-.3,.3):m.box('wheel',x,y,0,.18,.10,.30,'dark')
  m.box('handle',-.8,0,.4,.08,.78,.75,'steel')
 elif k=='stop-sign':
  m.box('post',0,0,0,.12,.12,3,'steel');m.box('face',0,0,2.45,.9,.15,.55,'blue')
 elif k=='shelter':
  m.box('roof',0,0,2.65,5,2.4,.18,'blue')
  for x in (-2.25,2.25):m.box('post',x,.95,0,.13,.13,2.65,'steel')
  m.box('rear-wall',0,1.1,0,4.7,.10,2.35,'glass')
  if not far:m.box('seat',0,.55,.45,3.3,.48,.1,'white')
 elif k=='footbridge':
  m.box('deck',0,0,5.5,8,2.5,.25,'deck')
  for y in (-1.2,1.2):m.box('rail',0,y,5.75,8,.09,1.1,'steel')
  c=[dict(name='left',position=[-4,0,5.5],normal=[-1,0,0]),dict(name='right',position=[4,0,5.5],normal=[1,0,0])]
 elif k=='lift-tower':
  m.box('shaft',0,0,0,3,3,5.75,'white');m.box('glazing',0,-1.51,.6,1.7,.025,4.5,'glass')
  m.box('roof',0,0,5.75,3.4,3.4,.15,'blue')
 return c

def translated(m,other,dx,dy,dz,angle=0):
 start=len(m.t);cs=math.cos(angle);sn=math.sin(angle)
 for v,col,g in other.t:
  m.t.append(([(dx+cs*x-sn*y,dy+sn*x+cs*y,dz+z) for x,y,z in v],col,g))
 for s in other.solids:m.solids.append(dict(name=s['name'],start=start+s['start'],count=s['count']))

def put(m,k,x,y,z,far,angle=0):
 p=Mesh();part(p,k,far);translated(m,p,x,y,z,angle)

def bus(m,x,y,angle=0):
 p=Mesh();p.box('coach-body',0,0,.52,13.19,2.5,3.04,'white');p.box('coach-window',0,-1.26,2.12,11.7,.035,1.0,'glass');p.box('coach-window',0,1.26,2.12,11.7,.035,1.0,'glass')
 for ax in (-3.9,-2.6,3.8):
  for side in (-1.12,1.12):p.box('wheel',ax,side,0,.75,.22,1.0,'dark')
 for side in (-1.58,1.58):p.box('mirror',5.25,side,2.65,.28,.17,.48,'dark')
 translated(m,p,x,y,0,angle)

def terminal(m,kind,far):
 n=8 if kind=='large' else 5
 spacing=4.8; first=-(n-1)*spacing/2; a=math.radians(22)
 m.box('paved-site',0,0,0,82 if n==8 else 64,64 if n==8 else 48,.08,'deck')
 m.box('bus-lane',-16,0,.08,20,n*spacing+10,.03,'steel')
 bays=[]
 for i in range(n):
  y=first+i*spacing
  put(m,'sawtooth-island',5,y+2.25,.08,far,a)
  bays.append(dict(id=f'bay-{i+1:02}',front=[11.12,y+2.23,.08],heading=[math.cos(a),math.sin(a),0],usable_length=15.0,clear_width=3.6,mirror_clearance=3.16))
  if i%2==0:
   m.box('canopy-roof',3,y+2.25,3.67,8,4.2,.22,'blue')
   for x in (-.55,6.55):m.box('canopy-column',x,y+2.25,.32,.16,.16,3.35,'steel')
   if not far:m.box('canopy-light',3,y+2.25,3.62,6,.12,.035,'warm',1)
  if not far:put(m,'seat-group',1,y+2.25,.32,far)
 m.box('canopy-continuous',3,0,3.89,8,n*spacing+4,.16,'blue')
 m.box('hall',22,0,.08,15,n*spacing+9,4.4,'white')
 m.box('glazed-front',14.48,0,.45,.05,n*spacing+7,3.5,'glass')
 m.box('hall-roof',22,0,4.48,16,n*spacing+10,.32,'blue')
 m.box('sign-band',14.42,0,3.75,.08,12,.45,'dark')
 for i in range(3):
  put(m,'ticket-counter',26,first+i*4,.08,far)
  put(m,'ticket-machine',18,first+i*2.5,.08,far)
 m.box('hall-departure-board',14.40,0,2.3,.16,4,1.45,'dark')
 if not far:
  for y in (-1.3,0,1.3):m.box('hall-board-row',14.31,y,2.95,.015,.75,.08,'warm',1)
 if not far:
  for i in range(4):put(m,'seat-group',20,first+i*4,.08,far)
  put(m,'luggage-cart',18,first+10,.08,far)
 # Separate approach and departure lane; both connectors meet road elevation 0.
 m.box('entry-lane',-31,-n*spacing/2-5,.08,14,4,.03,'dark')
 m.box('exit-lane',-31,n*spacing/2+5,.08,14,4,.03,'dark')
 m.box('zebra',-8,n*spacing/2+4,.11,5,3,.025,'white')
 m.box('taxi-zone',31,n*spacing/2+5,.08,12,4,.03,'warm')
 m.box('pickup-zone',31,-n*spacing/2-5,.08,12,4,.03,'blue')
 return dict(turning_envelope=dict(length=20,width=n*spacing+10),parking=bays,entry=dict(position=[-38,-n*spacing/2-5,0],heading=[1,0,0]),exit=dict(position=[-38,n*spacing/2+5,0],heading=[-1,0,0]),floor=0)

def express(m,far):
 m.box('shoulder',0,0,0,38,15,.08,'steel')
 m.box('waiting-pad',7,3,.08,13,5,.17,'deck')
 put(m,'shelter',6,4,.25,far);put(m,'stop-sign',12,3,.25,far)
 for x in (range(-16,17,4) if not far else (-16,0,16)):m.box('guardrail',x,-2,.5,3.8,.12,.16,'white')
 put(m,'footbridge',-3.3,3,0,far)
 put(m,'lift-tower',-7,3,.08,far)
 for i in range(14 if not far else 4):
  count=14 if not far else 4;m.box('stair',-15+(i+.5)*7.7/count,3,.08,7.7/count,2.4,(i+1)*5.46/count,'deck')
 for x in (-3.3,.7):m.box('bridge-support',x,3,.08,.18,.18,5.5,'steel')
 return dict(parking=[dict(id='shoulder-01',front=[10,0,.08],heading=[1,0,0],usable_length=15,clear_width=3.6,mirror_clearance=3.16)],entry=dict(position=[-19,0,0],heading=[1,0,0]),exit=dict(position=[19,0,0],heading=[1,0,0]),floor=0)

def output_model(root,key,far):
 m=Mesh();meta={}
 if key in PARTS:meta={'connectors':part(m,key,far),'mount':'wall' if key=='departure-board' else 'ground'}
 elif key=='large':meta=terminal(m,'large',far)
 elif key=='medium':meta=terminal(m,'medium',far)
 elif key=='express-stop':meta=express(m,far)
 elif key=='large-three-coaches':
  meta=terminal(m,'large',far)
  for bay in (meta['parking'][0],meta['parking'][3],meta['parking'][6]):
   a=math.atan2(bay['heading'][1],bay['heading'][0]);f=bay['front'];bus(m,f[0]-6.6*math.cos(a),f[1]-6.6*math.sin(a),a)
 m.validate();ident=key+('-far' if far else '-near');folder=root/ident;folder.mkdir(parents=True,exist_ok=True)
 info=json.dumps({'asset':{'generator':'bus-terminal-studies/produce.py','version':'1'},'extras':{'id':ident,'studiesOnly':True,'coordinates':'metres +x forward +y left +z up','solids':m.solids}},separators=(',',':')).encode()
 b=bytearray(struct.pack('<4sHHII',b'M3DM',1,0,len(m.t),len(info))+info);b+=bytes((-len(info))%4)
 for v,c,g in m.t:
  b+=struct.pack('<I',g);rgba=(c>>16&255)|((c>>8&255)<<8)|((c&255)<<16)|0xff000000
  for p in v:b+=struct.pack('<fffI',*p,rgba)
 filename=folder/(ident+'.m3dmodel');filename.write_bytes(b)
 return dict(id=ident,native=str(filename.relative_to(root)),triangles=len(m.t),metadata=meta)

def main():
 ap=argparse.ArgumentParser();ap.add_argument('output',type=Path);args=ap.parse_args();root=args.output.resolve();root.mkdir(parents=True,exist_ok=True)
 assert Path(__file__).resolve().parents[2] not in root.parents
 keys=('large','medium','express-stop')+PARTS+('large-three-coaches',)
 records=[output_model(root,k,far) for k in keys for far in (False,True)]
 (root/'manifest.json').write_text(json.dumps(dict(schema_version=1,directions=['top','bottom','left','right','front','back','isometric'],models=records),indent=2,ensure_ascii=False)+'\n')
 print('models',len(records),'maximum triangles',max(x['triangles'] for x in records))
if __name__=='__main__':main()
