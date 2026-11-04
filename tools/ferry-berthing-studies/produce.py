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
def rotate(p,pivot,a):
 x,y,z=sub(p,pivot);return add(pivot,(math.cos(a)*x-math.sin(a)*z,y,math.sin(a)*x+math.cos(a)*z))
def water_angle(level):
 return math.atan2(.18,6.1)+math.asin((.65+level+.06-1.65)/math.hypot(6.1,.18))
def ramp_end(level): return add((-10,0,1.65),rotate((6.1,0,0),(0,0,0),water_angle(level)))
def plate_angle(level): return math.asin((.65+level-ramp_end(level)[2])/.8)
def posed(mesh,meta,value):
 j=meta.get('joint');result=[(list(v),c,g) for v,c,g in mesh.t]
 if not j:return result
 if not math.isfinite(value):value=j['rest']
 value=max(j['limit'][0],min(j['limit'][1],value))
 for start,count in j['ranges']:
  for i in range(start,start+count):
   v,c,g=result[i]
   if j['type']=='translation':fn=lambda p:add(p,(0,0,value))
   elif j['type']=='rotation':fn=lambda p:rotate(p,j['pivot'],value-j['rest'])
   else:
    binding=next(b for b in j['bindings'] if b['range'][0]==start)
    if binding['kind']=='float':fn=lambda p:add(p,(0,0,value))
    elif binding['kind']=='ramp':fn=lambda p:rotate(p,(-10,0,1.65),water_angle(value)-water_angle(0))
    else:fn=lambda p:add(rotate(sub(p,ramp_end(0)),(0,0,0),plate_angle(value)-plate_angle(0)),ramp_end(value))
   result[i]=([fn(p) for p in v],c,g)
 return result
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
    b=j*2*math.pi/m; rr=r+.035*math.cos(b)
    p.append((x+rr*math.cos(a),y+.035*math.sin(b),z+rr*math.sin(a)))
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

 def cylinder(self,name,a,b,r,c,n=12):
  d=unit(sub(b,a));u=unit(cross(d,(0,0,1) if abs(d[2])<.9 else (0,1,0)));v=cross(d,u)
  p=[add(q,add(mul(u,r*math.cos(i*2*math.pi/n)),mul(v,r*math.sin(i*2*math.pi/n)))) for q in (a,b) for i in range(n)]
  self.solid(name,p,[list(range(n-1,-1,-1)),list(range(n,2*n))]+[[i,(i+1)%n,(i+1)%n+n,i+n] for i in range(n)],c)
 def tube(self,name,points,r,c,lod):
  # Continuous rings with shared joins, capped ends, no open segment seams.
  n=6 if lod else 10;p=[]
  for i,q in enumerate(points):
   d=unit(sub(points[min(i+1,len(points)-1)],points[max(0,i-1)]));u=unit(cross(d,(0,0,1) if abs(d[2])<.9 else (0,1,0)));v=cross(d,u)
   p += [add(q,add(mul(u,r*math.cos(j*2*math.pi/n)),mul(v,r*math.sin(j*2*math.pi/n)))) for j in range(n)]
  self.solid(name,p,[list(range(n-1,-1,-1)),list(range((len(points)-1)*n,len(points)*n))]+[[i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j] for i in range(len(points)-1) for j in range(n)],c)
 def part(self,kind,lod=False):
  n=8 if lod else 16
  if kind=='fender':
   self.box('wall-plate',.035,0,-.6,.07,.55,1.2,'steel')
   for z in (-.45,.45):self.box('stand-off',.105,0,z-.07,.14,.4,.14,'steel')
   self.box('rubber-pad',.24,0,-.68,.20,.64,1.36,'dark')
   if not lod:
    for z in (-.45,0,.45):self.box('rubber-rib',.355,0,z-.08,.03,.6,.16,'dark')
   return {'mount':[0,0,0],'contact':[.37,0,0],'mountNormal':[-1,0,0]}
  if kind=='bollard':
   self.box('base',0,0,0,.82,.54,.08,'steel')
   for x in (-.23,.23):self.cylinder('bitt',(x,0,.08),(x,0,.56),.10,'steel',n)
   self.cylinder('crossbar',(-.43,0,.51),(.43,0,.51),.075,'steel',n)
   if not lod:
    for x in (-.32,.32):
     for y in (-.18,.18):self.cylinder('anchor-bolt',(x,y,.08),(x,y,.12),.025,'dark',8)
   return {'mount':[0,0,0],'tieA':[-.23,0,.5],'tieB':[.23,0,.5]}
  if kind=='ring':
   self.box('wall-plate',.03,0,-.20,.06,.36,.40,'steel');self.box('eye-bracket',.11,0,.10,.16,.10,.10,'steel')
   start=len(self.t);self.ring('mooring-ring',0,0,0,.20,'steel',n)
   self.transform(start,lambda p:(.185-p[1],p[0],p[2]))
   return {'mount':[0,0,0],'tie':[.185,0,-.20],'mountNormal':[-1,0,0]}
  if kind=='rope':
   steps=8 if lod else 20
   points=[(-1+2*i/steps,0,-.20*(1-(-1+2*i/steps)**2)) for i in range(steps+1)]
   self.tube('mooring-line',points,.028,'wood',lod)
   return {'endA':[-1,0,0],'endB':[1,0,0],'restLengthChord':2.,'sag':.20,'note':'ends are attachment points, no tension or knot simulation'}
  if kind=='pile':
   self.cylinder('fixed-pile',(0,0,-3),(0,0,4),.22,'steel',n)
   self.cylinder('pile-cap',(0,0,4),(0,0,4.10),.25,'warm',n)
   start=len(self.t)
   for x in (-.41,.41):self.box('collar-x',x,0,.12,.14,.96,.65,'steel')
   for y in (-.41,.41):self.box('collar-y',0,y,.12,.68,.14,.65,'steel')
   for sign in (-1,1):
    self.cylinder('guide-axle',(sign*.30,-.35,.44),(sign*.30,.35,.44),.025,'steel',n)
    self.cylinder('guide-roller',(sign*.30,-.18,.44),(sign*.30,.18,.44),.08,'dark',n)
    self.cylinder('guide-axle',(-.35,sign*.30,.44),(.35,sign*.30,.44),.025,'steel',n)
    self.cylinder('guide-roller',(-.18,sign*.30,.44),(.18,sign*.30,.44),.08,'dark',n)
   self.box('pontoon-arm',.69,0,.39,.56,.28,.16,'steel')
   self.box('deck-plate',1.02,0,.49,.28,.48,.08,'steel')
   return {'pileWaterline':[0,0,0],'deckMount':[1.02,0,.57],'joint':{'type':'translation','axis':[0,0,1],'pivot':[0,0,0],'limit':[-.3,.3],'rest':0,'ranges':[[start,len(self.t)-start]]}}
  if kind=='roller':
   # Floor contact z0; axle z.06, deck underside pickup .12.
   for y in (-.72,.72):
    self.cylinder('wheel', (0,y-.07,.06),(0,y+.07,.06),.06,'dark',n)
    self.box('bearing',0,y,.06,.14,.20,.06,'steel')
   self.cylinder('axle',(0,-.9,.06),(0,.9,.06),.024,'steel',n)
   return {'floorContact':[0,0,0],'axle':[0,0,.06],'rampPickup':[0,0,.12]}
  if kind=='plate':
   # Separate hinge and plate. Standalone default tilt demonstrates connection.
   for y in (-.95,.95):self.box('fixed-hinge',0,y,-.05,.18,.16,.10,'steel')
   self.cylinder('hinge-pin',(0,-1.03,0),(0,1.03,0),.035,'steel',n)
   start=len(self.t);self.box('transition-leaf',.4,0,0,.8,1.82,.04,'deck')
   if not lod:
    for x in (.15,.3,.45,.6):self.box('plate-grip',x,0,.04,.025,1.75,.01,'steel')
   a=-.30;self.transform(start,lambda p:rotate(p,[0,0,0],a))
   return {'hinge':[0,0,0],'joint':{'type':'rotation','axis':[0,-1,0],'pivot':[0,0,0],'limit':[-.5,.15],'rest':a,'ranges':[[start,len(self.t)-start]]}}
  if kind=='gangway':
   self.box('shore-base',-.22,0,-.40,.44,2.7,.28,'steel')
   for y in (-1.22,1.22):self.box('hinge-cheek',0,y,-.12,.3,.18,.24,'steel')
   self.cylinder('shore-pin',(0,-1.35,0),(0,1.35,0),.06,'steel',n)
   start=len(self.t);self.box('ramp',3.05,0,-.12,6.1,2.2,.12,'deck')
   for y in (-1.04,1.04):self.rail('ramp-rail',(0,y,0),(6.1,y,0),lod)
   # Wheel centres .18m below ramp top; axial supports meet underside.
   for y in (-.72,.72):
    self.cylinder('wheel',(6.1,y-.07,-.18),(6.1,y+.07,-.18),.06,'dark',n)
    self.box('bearing',6.1,y,-.18,.14,.20,.06,'steel')
   self.cylinder('axle',(6.1,-.9,-.18),(6.1,.9,-.18),.024,'steel',n)
   for y in (-.95,.95):self.box('end-plate-hinge',6.1,y,-.05,.18,.16,.10,'steel')
   self.cylinder('end-hinge-pin',(6.1,-1.03,0),(6.1,1.03,0),.035,'steel',n)
   a=water_angle(0);self.transform(start,lambda p:rotate(p,[0,0,0],a))
   return {'hinge':[0,0,0],'rampEnd':rotate((6.1,0,0),[0,0,0],a),'joint':{'type':'rotation','axis':[0,-1,0],'pivot':[0,0,0],'limit':[water_angle(-.3),water_angle(.3)],'rest':a,'ranges':[[start,len(self.t)-start]]},'wheelRadius':.06,'rollerContactPlane':-1.0}
  if kind=='mooring-demo':
   self.box('demo-ground',0,0,0,3.4,1.2,.2,'deck')
   for x in (-1.2,1.2):
    start=len(self.t);self.part('bollard',lod);self.transform(start,lambda p:add(p,(x,0,.2)))
   points=[(-.97+1.94*i/(8 if lod else 20),0,.70-.20*(1-(-1+2*i/(8 if lod else 20))**2)) for i in range((8 if lod else 20)+1)]
   self.tube('attached-line',points,.028,'wood',lod)
   return {'mount':[0,0,0],'lineEndA':[-.97,0,.7],'lineEndB':[.97,0,.7],'note':'static slack-line attachment demo, endpoints enter bitt solids; no knots/load/boat'}
  if kind=='assembly':return self.assembly(lod)
  raise ValueError(kind)
 def assembly(self,lod):
  # Fixed shoreline and pile shafts first, before all moving ranges.
  self.box('shore',-11,0,.90,2.,4.,.75,'deck')
  self.box('shore-hinge-support',-10.15,0,1.25,.30,2.8,.28,'steel')
  for y in (-3.5,3.5):self.cylinder('fixed-pile',(-2,y,-3),(-2,y,4),.22,'steel',8 if lod else 16)
  floatingStart=len(self.t)
  for y in (-2.1,2.1):self.box('float',0,y,-.5,8,1.3,.95,'dark')
  self.box('pontoon-deck',0,0,.45,8,6,.20,'wood')
  for y in (-3.5,3.5):
   # Collar around each pile, bracket reaches the deck edge at y±3.
   for x in (-2.41,-1.59):self.box('collar-side',x,y,.12,.14,.96,.65,'steel')
   for dy in (-.41,.41):self.box('collar-end',-2,y+dy,.12,.68,.14,.65,'steel')
   for sign in (-1,1):
    self.cylinder('guide-axle',(-2+sign*.30,y-.35,.44),(-2+sign*.30,y+.35,.44),.025,'steel',8 if lod else 16)
    self.cylinder('guide-roller',(-2+sign*.30,y-.18,.44),(-2+sign*.30,y+.18,.44),.08,'dark',8 if lod else 16)
    self.cylinder('guide-axle',(-2-.35,y+sign*.30,.44),(-2+.35,y+sign*.30,.44),.025,'steel',8 if lod else 16)
    self.cylinder('guide-roller',(-2-.18,y+sign*.30,.44),(-2+.18,y+sign*.30,.44),.08,'dark',8 if lod else 16)
   self.box('deck-arm',-2,y-math.copysign(.45,y),.39,.28,.30,.16,'steel')
   self.box('deck-mount',-2,math.copysign(2.9,y),.55,.48,.3,.10,'steel')
  for x in (-2.8,2.8):
   start=len(self.t);self.part('bollard',lod);self.transform(start,lambda p:add(p,(x,2.65,.65)))
   start=len(self.t);self.part('fender',lod);self.transform(start,lambda p:(x+p[1],-3-p[0],p[2]-.05))
  floatingEnd=len(self.t)
  # Full ramp fixed+moving unit, pivot at shore; only leaf/rollers follow tide.
  start=len(self.t);g=self.part('gangway',lod);self.transform(start,lambda p:add(p,(-10,0,1.65)))
  rstart=g['joint']['ranges'][0][0];rend=len(self.t)
  end=ramp_end(0)
  # Transition leaf rests on the pontoon; hinge is carried at the ramp end.
  plateStart=len(self.t);a=plate_angle(0)
  self.box('transition-leaf',.4,0,0,.8,1.82,.04,'deck')
  self.transform(plateStart,lambda p:add(rotate(p,[0,0,0],a),end))
  # A rigid line at a separate attachment demonstration (no vessel/load claim).

  # Line endpoint on the floating bitt and another dedicated shore ring are
  # intentionally omitted from the tide rig: slack geometry needs remeshing.
  return {'waterline':[0,0,0],'deck':[0,0,.65],'joint':{'type':'water','units':'metres','limit':[-.3,.3],'rest':0,'ranges':[[floatingStart,floatingEnd-floatingStart],[rstart,rend-rstart],[plateStart,12]],'bindings':[{'kind':'float','range':[floatingStart,floatingEnd-floatingStart]},{'kind':'ramp','range':[rstart,rend-rstart]},{'kind':'plate','range':[plateStart,12]}]},'profile':{'pontoon':[8,6,.65],'hinge':[-10,0,1.65],'rampLength':6.1,'rollerRadius':.06,'rollerDrop':.18},'note':'mooring lines are separate static modules; no boat, physics, tide feed or safe operating envelope'}

def write_model(root,id,name,mesh,meta):
 mesh.validate(); folder=root/id/'revision-1';folder.mkdir(parents=True,exist_ok=True)
 provenance=json.dumps({'asset':{'generator':'ferry-berthing-studies/produce.py','version':'1'},'extras':{'id':id,'studiesOnly':True,'coordinates':'metres +x forward +y left +z up','solids':mesh.solids}},separators=(',',':')).encode()
 out=bytearray(struct.pack('<4sHHII',b'M3DM',1,0,len(mesh.t),len(provenance))+provenance);out+=bytes((-len(provenance))%4)
 for v,c,g in mesh.t:
  out+=struct.pack('<I',g)
  rgba=(c>>16&255)|((c>>8&255)<<8)|((c&255)<<16)|0xff000000
  for p in v:out+=struct.pack('<fffI',*p,rgba)
 path=folder/(id+'.m3dmodel');path.write_bytes(out)
 return dict(id=id,name=name,native=str(path.relative_to(root)),triangles=len(mesh.t),connectors=meta,connectorNormals={k:(meta.get('mountNormal',[0,0,-1]) if k.startswith('mount') else [0,0,1]) for k,v in meta.items() if (k.startswith('mount') or k in ['surface','boardingSurface']) and not k.endswith('Normal') and isinstance(v,list) and len(v)==3},solids=len(mesh.solids))

def main():
 ap=argparse.ArgumentParser();ap.add_argument('output',type=Path);ap.add_argument('--part');args=ap.parse_args();root=args.output.resolve();repo=Path(__file__).resolve().parents[2]
 assert root!=repo and repo not in root.parents,'Private output required'
 names={'fender':'壁掛橡膠防舷','bollard':'雙柱繫纜樁','ring':'壁掛繫纜環','rope':'靜態繫纜繩','pile':'導樁與升降滑套','roller':'跳板滾輪軸承','plate':'鉸接端部過渡板','gangway':'含滾輪跳板組','mooring-demo':'靜態雙樁繫纜示例','assembly':'浮台靠泊接合示例'}
 root.mkdir(parents=True,exist_ok=True);mf=root/'manifest.json';manifest=json.loads(mf.read_text()) if mf.exists() else {'schema_version':1,'directions':['top','bottom','left','right','front','back','isometric'],'models':[]}
 records=[]
 for kind in ([args.part] if args.part else names):
  for lod in (False,True):
   m=Mesh();meta=m.part(kind,lod);id=kind+('-lod' if lod else '-near');records.append(write_model(root,id,names[kind]+('・遠景' if lod else '・近景'),m,meta))
 ids={m['id'] for m in records};manifest['models']=[m for m in manifest['models'] if m['id'] not in ids]+records
 mf.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');print([(m['id'],m['triangles']) for m in records])
if __name__=='__main__':main()
