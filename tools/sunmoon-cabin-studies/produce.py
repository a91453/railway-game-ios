#!/usr/bin/env python3
"""Original studies recipes, native x forward / y port / z up, metres.
No runtime imports or registration. Closed solids; touching mounting faces.
"""
import argparse, collections, hashlib, json, math, struct
from pathlib import Path
P=dict(white=0xEDEFF0,blue=0x5F8BC0,red=0xC65A4E,green=0x5E8F86,yellow=0xFFC86B,steel=0x6E747B,dark=0x26385C,deck=0xDCD6C8,glass=0x26385C,warm=0xFFE2A6,wood=0x8E6E52)
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
 def rounded(self,l,w,r,z,segments):
  p=[]
  for cx,cy,quarter in [(l/2-r,w/2-r,0),(-l/2+r,w/2-r,1),(-l/2+r,-w/2+r,2),(l/2-r,-w/2+r,3)]:
   for j in range(segments+1):
    a=(quarter+j/segments)*math.pi/2;p.append((cx+r*math.cos(a),cy+r*math.sin(a),z))
  return p
 def loft(self,name,levels,color,lod=False,hollow=False,flag=0,thickness=.035):
  seg=2 if lod else 6;rings=[self.rounded(l,w,r,z,seg) for z,l,w,r in levels];n=len(rings[0]);p=[v for ring in rings for v in ring];count=len(rings)
  faces=[[i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j] for i in range(count-1) for j in range(n)]
  if hollow:
   inner=[self.rounded(l-2*thickness,w-2*thickness,max(.025,r-thickness),z,seg) for z,l,w,r in levels];start=len(p);p += [v for ring in inner for v in ring]
   faces += [[start+i*n+(j+1)%n,start+i*n+j,start+(i+1)*n+j,start+(i+1)*n+(j+1)%n] for i in range(count-1) for j in range(n)]
   faces += [[(j+1)%n,j,start+j,start+(j+1)%n] for j in range(n)]
   outer=(count-1)*n;inside=start+outer
   faces += [[outer+j,outer+(j+1)%n,inside+(j+1)%n,inside+j] for j in range(n)]
  else:faces += [list(range(n-1,-1,-1)),list(range((count-1)*n,count*n))]
  self.solid(name,p,faces,color,flag)
 def ellipsoid(self,name,centre,radii,c,lod):
  n=8 if lod else 12;nr=4 if lod else 7;v=[add(centre,(0,0,-radii[2]))]
  for i in range(1,nr):
   a=-math.pi/2+i*math.pi/nr
   for j in range(n):
    b=2*math.pi*j/n;v.append(add(centre,(radii[0]*math.cos(a)*math.cos(b),radii[1]*math.cos(a)*math.sin(b),radii[2]*math.sin(a))))
  v.append(add(centre,(0,0,radii[2])));top=len(v)-1;last=1+(nr-2)*n
  f=[[0,1+(j+1)%n,1+j] for j in range(n)]+[[top,last+j,last+(j+1)%n] for j in range(n)]
  f += [[1+i*n+j,1+i*n+(j+1)%n,1+(i+1)*n+(j+1)%n,1+(i+1)*n+j] for i in range(nr-2) for j in range(n)]
  self.solid(name,v,f,c)
 def patch(self,name,x0,x1,levels,color):
  # A closed door insert follows the actual piecewise glazing surface.
  p=[]
  for z in levels:
   y=-dimensions_at(z)[1]/2-.005;p += [(x0,y-.011,z),(x1,y-.011,z),(x1,y+.011,z),(x0,y+.011,z)]
  self.solid(name,p,[[0,3,2,1],list(range(len(p)-4,len(p)))]+[[4*i+j,4*i+(j+1)%4,4*(i+1)+(j+1)%4,4*(i+1)+j] for i in range(len(levels)-1) for j in range(4)],color)
 def cabin(self,kind,lod=False):
  # ALL external dimensions are photo-ratio estimates, not Maokong dimensions.
  crystal=kind=='crystal';accent='green' if crystal else kind;floor=-3.78;n=8 if lod else 12
  self.loft('lower-perimeter',[(-3.86,1.78,1.44,.28),(-3.72,1.94,1.60,.32)],accent,lod,True,thickness=.045)
  self.loft('glazing',PROFILE,'glass',lod,True,2,.012)
  self.loft('closed-roof',[(-1.78,1.78,1.50,.19),(-1.72,1.86,1.56,.20),(-1.66,1.78,1.50,.23)],accent,lod)
  if crystal:
   self.loft('floor-frame',[(-3.86,1.78,1.44,.28),(-3.78,1.90,1.56,.30)],'steel',lod,True,thickness=.13)
   self.box('glass-floor-estimated-40mm',0,0,floor-.040,1.64,1.30,.040,'glass',2)
  else:self.loft('solid-floor',[(-3.86,1.78,1.44,.28),(-3.78,1.90,1.56,.30)],'deck',lod)
  # Four curved coloured corner mullions, not a Maokong white-shell recolour.
  for sx in (-1,1):
   for sy in (-1,1):
    path=[]
    for z,l,w,r in [(-3.82,1.84,1.50,.30),*PROFILE,(-1.72,1.86,1.56,.20)]:
     path.append((sx*(l/2-r+r/math.sqrt(2)),sy*(w/2-r+r/math.sqrt(2)),z))
    self.tube('corner-gasket',path,.065,'dark',lod)
    self.tube('curved-colour-mullion',[(x+sx*.018,y+sy*.018,z) for x,y,z in path],.053,accent,lod)
    l,w,r=dimensions_at(-2.98);self.ellipsoid('oval-buffer',(sx*(l/2-r+r/math.sqrt(2)+.02),sy*(w/2-r+r/math.sqrt(2)+.02),-2.98),(.080,.080,.23),'dark',lod)
  # Two opposed benches; down only. Folding motion is not implemented.
  for sign in (-1,1):
   for y in (-.45,.45):self.box('seat-support',sign*.86,y,floor,.08,.10,.44,'steel')
   self.box('seat-pan',sign*.70,0,floor+.44,.40,1.24,.08,'blue')
   self.box('seat-back',sign*.87,0,floor+.52,.06,1.24,.42,'blue')
   self.cylinder('seat-hinge',(sign*.86,-.61,floor+.46),(sign*.86,.61,floor+.46),.025,'steel',n)
   if not lod:
    for y in (-.31,0,.31):self.box('seat-seam',sign*.70,y,floor+.52,.36,.009,.005,'steel')
  # 0.80 m unobstructed opening between outside frame inner faces.
  door_levels=[(floor,.77)]+[(z,w/2) for z,l,w,r in PROFILE]
  for x in (-.43,0,.43):self.tube('door-frame' if x else 'door-centre-gasket',[(x,-y-.007,z) for z,y in door_levels],.03 if x else .02,accent if x else 'dark',lod)
  self.beam('door-header',(-.43,-.757,-1.78),(.43,-.757,-1.78),.05,accent)
  self.box('boarding-threshold',0,-.755,floor-.025,.86,.08,.025,'steel')
  for a,b in [(-.40,-.012),(.012,.40)]:self.patch('lower-door-insert',a,b,[-3.72,-3.40,-3.34],accent)
  if not lod:
   for z in (-3.05,-2.75,-2.45):
    y=-dimensions_at(z)[1]/2
    for a,b in [(-.35,-.07),(.07,.35)]:
     self.beam('window-latch',(a,y-.025,z),(b,y-.025,z),.018,'steel')
     for x in (a,b):self.beam('latch-mount',(x,y+.006,z),(x,y-.025,z),.018,'steel')
  # Narrow ventilation/louvre strips on the broad end windows.
  for sx in (-1,1):
   for z in ([-1.98] if lod else [-2.07,-2.00,-1.93]):
    x=sx*(dimensions_at(z)[0]/2-.003);self.beam('vent-strip',(x,-.48,z),(x,.48,z),.018,'steel')
   for y in (-.47,.47):
    path=[(sx*(dimensions_at(z)[0]/2-.003),y,z) for z in [-2.10,-1.90]];self.tube('vent-frame',path,.014,'dark',lod)
  self.loft('bumper-hoop',[(-3.84,2.00,1.65,.32),(-3.815,2.00,1.65,.32)],'steel',lod,True,thickness=.025)
  for x in (-.60,.60):
   for sy in (-1,1):self.beam('bumper-mount',(x,sy*.65,-3.827),(x,sy*.81,-3.827),.025,'steel')
  # Interior lamp position is an estimate; the documented equipment type is real.
  self.box('roof-light-mount',0,-.32,-1.796,.46,.12,.016,'steel')
  self.box('roof-light',0,-.32,-1.802,.42,.10,.006,'warm',1)
  # Four roof pads and a real spider frame seated on the closed roof.
  for x in (-.62,.62):
   for y in (-.50,.50):
    self.cylinder('roof-pad',(x,y,-1.66),(x,y,-1.58),.06,'dark',n)
    self.beam('roof-spider',(x,y,-1.58),(0,0,-1.38),.065,'steel')
  for y in (-.50,.50):self.beam('roof-crossbar',(-.62,y,-1.57),(.62,y,-1.57),.055,'steel')
  self.box('roof-saddle',0,0,-1.46,.40,.32,.12,'steel')
  self.cylinder('yoke-pivot',(0,-.20,-1.40),(0,.20,-1.40),.065,'steel',n)
  self.tube('lower-bent-hanger',[(0,0,-1.40),(0,.22,-1.32),(0,.41,-1.05),(0,.39,-.65),(0,.20,-.14)],.065,'steel',lod)
  # Solar panel normal points upward/outward, four feet meet its tilted underside.
  angle=math.pi/6;ca=math.cos(angle);sa=math.sin(angle)
  for u in (-.25,.25):
   for v in (-.28,.28):
    q=(.52+ca*u,v,-1.40-sa*u);self.beam('solar-mount',(q[0],q[1],-1.66),q,.027,'steel')
  start=len(self.t);self.box('solar-panel-frame',0,0,0,.64,.72,.035,'steel');self.box('solar-panel',0,0,.035,.58,.66,.005,'dark')
  if not lod:
   for u in (-.145,0,.145):self.box('solar-grid',u,0,.040,.004,.65,.002,'steel')
   for v in (-.22,0,.22):self.box('solar-grid',0,v,.040,.57,.004,.002,'steel')
  self.transform(start,lambda p:(.52+ca*p[0]+sa*p[2],p[1],-1.40-sa*p[0]+ca*p[2]))
  # Doppelmayr-style grip exterior only, hollow channel along +x at origin.
  self.box('grip-body',0,0,-.18,.68,.32,.10,'steel')
  self.box('grip-lower-jaw',0,0,-.08,.65,.18,.025,'dark')
  for y in (-.075,.075):self.box('grip-jaw',0,y,-.055,.65,.04,.11,'steel')
  self.box('grip-top-link',0,0,.055,.65,.19,.035,'steel')
  if not lod:
   for x in (-.25,.25):self.beam('opener-bracket',(x,-.12,-.16),(x,-.22,.12),.035,'steel')
   self.cylinder('opener-spring-core',(-.25,-.22,.12),(.25,-.22,.12),.035,'dark',12)
   for i in range(7):self.cylinder('spring-collar',(-.24+i*.07,-.22,.12),(-.215+i*.07,-.22,.12),.055,'steel',8)
   self.beam('opener-lever',(.25,-.22,.12),(.43,-.22,.20),.04,'steel')
  return dict(ropeAnchor=[0,0,0],ropeAxis=[1,0,0],boardingFloor=[0,0,floor],doorSide=[0,-1,0],doorClearWidth=.80,officialInteriorDepth=1.40,estimatedBodyDimensions=[2.20,1.90,2.20],dimensionsStatus='比例推估；未取得原廠工程圖',glassThicknessEstimate=.040 if crystal else 0,passengerLimit=6 if crystal else 8,massLimitKg=None,notes='static closed doors; native glass opaque, GLB transparency inspection-only; all external dimensions estimated')

PROFILE=[(-3.72,1.94,1.60,.32),(-3.40,2.12,1.82,.36),(-2.85,2.20,1.90,.38),(-2.45,2.20,1.90,.38),(-2.05,2.05,1.74,.32),(-1.82,1.84,1.58,.23),(-1.78,1.78,1.50,.19)]
def dimensions_at(z):
 for a,b in zip(PROFILE,PROFILE[1:]):
  if z<=b[0]:
   t=(z-a[0])/(b[0]-a[0]);return tuple(a[k]+t*(b[k]-a[k]) for k in (1,2,3))
 return tuple(PROFILE[-1][1:])

def write_model(root,id,name,mesh,meta):
 mesh.validate(); folder=root/id/'revision-1';folder.mkdir(parents=True,exist_ok=True)
 provenance=json.dumps({'asset':{'generator':'sunmoon-cabin-studies/produce.py','version':'1'},'extras':{'id':id,'studiesOnly':True,'coordinates':'metres +x forward +y left +z up','solids':mesh.solids}},separators=(',',':')).encode()
 out=bytearray(struct.pack('<4sHHII',b'M3DM',1,0,len(mesh.t),len(provenance))+provenance);out+=bytes((-len(provenance))%4)
 for v,c,g in mesh.t:
  out+=struct.pack('<I',g)
  rgba=(c>>16&255)|((c>>8&255)<<8)|((c&255)<<16)|0xff000000
  for p in v:out+=struct.pack('<fffI',*p,rgba)
 path=folder/(id+'.m3dmodel');path.write_bytes(out)
 return dict(id=id,name=name,native=str(path.relative_to(root)),triangles=len(mesh.t),connectors=meta,connectorNormals={k:(meta.get('mountNormal',[0,0,-1]) if k.startswith('mount') else [0,0,1]) for k,v in meta.items() if (k.startswith('mount') or k in ['surface','boardingSurface']) and not k.endswith('Normal') and isinstance(v,list) and len(v)==3},solids=len(mesh.solids))

def main():
 ap=argparse.ArgumentParser();ap.add_argument('output',type=Path);ap.add_argument('--kind',choices=['red','yellow','blue','crystal']);args=ap.parse_args();root=args.output.resolve();repo=Path(__file__).resolve().parents[2]
 assert root!=repo and repo not in root.parents,'private output required'
 root.mkdir(parents=True,exist_ok=True);mf=root/'manifest.json';manifest=json.loads(mf.read_text()) if mf.exists() else dict(schema_version=1,directions=['top','bottom','left','right','front','back','isometric'],models=[],nativeCoordinates='metres +x along rope +y left +z up; anchor0; boardingFloor -3.78; dimensions estimated')
 records=[]
 for kind in ([args.kind] if args.kind else ['red','yellow','blue','crystal']):
  for lod in (False,True):
   m=Mesh();meta=m.cabin(kind,lod);id=kind+('-lod' if lod else '-near');name={'red':'日月潭一般紅色','yellow':'日月潭一般黃色','blue':'日月潭一般藍色','crystal':'日月潭水晶基本綠色'}[kind]+('・遠景' if lod else '・近景');records.append(write_model(root,id,name,m,meta))
 ids={m['id'] for m in records};manifest['models']=[m for m in manifest['models'] if m['id'] not in ids]+records;mf.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');print([(r['id'],r['triangles']) for r in records])
if __name__=='__main__':main()
