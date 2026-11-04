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
 def rounded(self,l,w,r,z,segments):
  p=[]
  for cx,cy,quarter in [(l/2-r,w/2-r,0),(-l/2+r,w/2-r,1),(-l/2+r,-w/2+r,2),(l/2-r,-w/2+r,3)]:
   for j in range(segments+1):
    a=(quarter+j/segments)*math.pi/2;p.append((cx+r*math.cos(a),cy+r*math.sin(a),z))
  return p
 def loft(self,name,levels,color,lod=False,hollow=False,flag=0,thickness=.035):
  seg=2 if lod else 5;rings=[self.rounded(l,w,r,z,seg) for z,l,w,r in levels];n=len(rings[0]);p=[v for ring in rings for v in ring];count=len(rings)
  faces=[[i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j] for i in range(count-1) for j in range(n)]
  if hollow:
   inner=[self.rounded(l-2*thickness,w-2*thickness,max(.025,r-thickness),z,seg) for z,l,w,r in levels];start=len(p);p += [v for ring in inner for v in ring]
   faces += [[start+i*n+(j+1)%n,start+i*n+j,start+(i+1)*n+j,start+(i+1)*n+(j+1)%n] for i in range(count-1) for j in range(n)]
   faces += [[(j+1)%n,j,start+j,start+(j+1)%n] for j in range(n)]
   outer=(count-1)*n;inside=start+outer
   faces += [[outer+j,outer+(j+1)%n,inside+(j+1)%n,inside+j] for j in range(n)]
  else:faces += [list(range(n-1,-1,-1)),list(range((count-1)*n,count*n))]
  self.solid(name,p,faces,color,flag)
 def cabin(self,kind,lod=False):
  # Secondary-source dimensions (2015 table): 1.98 × 1.873 × 2.41 m.
  floor=-3.6;accent='green' if kind=='standard' else 'red';n=8 if lod else 16
  lower=[(-3.68,1.72,1.57,.14),(-3.44,1.80,1.68,.16),(-3.08,1.89,1.78,.20)]
  glazing=[(-3.08,1.89,1.78,.20),(-2.65,1.90,1.79,.21),(-2.05,1.86,1.74,.16),(-1.50,1.72,1.60,.10)]
  self.loft('lower-shell-inner-outer',lower,'white',lod,True)
  self.loft('glazing',glazing,'glass',lod,True,2,.012)
  self.loft('roof-rim',[(-1.50,1.72,1.60,.10),(-1.40,1.82,1.68,.12)],'white',lod,True)
  self.loft('closed-roof',[(-1.40,1.82,1.68,.12),(-1.32,1.84,1.70,.14),(-1.27,1.72,1.58,.18)],'white',lod)
  # Floor is a true slab or a supported 48 mm glass panel, not a filled skirt.
  if kind=='standard':self.box('solid-floor',0,0,-3.68,1.66,1.52,.08,'deck')
  else:
   for x in (-.76,.76):self.box('floor-frame',x,0,-3.68,.14,1.52,.08,'steel')
   for y in (-.69,.69):self.box('floor-frame',0,y,-3.68,1.38,.14,.08,'steel')
   self.box('glass-floor-48mm',0,0,floor-.048,1.38,1.24,.048,'green',2)
  # End benches: four seating positions per bench in regular cabins;
  # crystal load limit does not imply three physical seats are removed.
  for sign in (-1,1):
   x=sign*.63
   for y in (-.50,.50):self.box('seat-support',sign*.75,y,floor,.10,.12,.43,'steel')
   self.box('seat',x,0,floor+.43,.34,1.36,.10,'white')
   self.box('seat-back',sign*.78,0,floor+.53,.06,1.36,.42,'white')
   if not lod:
    for y in (-.34,0,.34):self.box('seat-division',x,y,floor+.53,.30,.012,.012,'steel')
  # Four swept corner posts, sharing a measured-style body silhouette.
  post_levels=[(-3.61,.80,.72),(-3.08,.86,.80),(-2.65,.86,.81),(-2.05,.84,.79),(-1.44,.78,.72)]
  for sx in (-1,1):
   for sy in (-1,1):
    path=[(sx*x,sy*y,z) for z,x,y in post_levels]
    self.tube('curved-corner-post',path,.048,'white',lod)
    # Subdued solid colour; no operator advertising, logos or characters.
    self.tube('corner-colour-panel',[(p[0]+sx*.043,p[1]+sy*.043,p[2]) for p in path[1:]],.044,accent,lod)
    self.box('corner-rubber-pad',sx*.925,sy*.855,-2.91,.13,.163,.27,'dark')
  # Two closed leaves on the right (-y) side; opposite side is a broad pane.
  door_levels=[(-3.60,.76),(-3.10,.89),(-2.65,.895),(-2.05,.87),(-1.50,.80)]
  for x in (-.65,0,.65):
   self.tube('door-frame' if x else 'door-centre-gasket',[(x,-y-.008,z) for z,y in door_levels],.029 if x else .018,'white' if x else 'dark',lod)
  for z,y in [(-3.60,.76),(-1.50,.80)]:self.beam('door-header',(-.65,-y-.008,z),(.65,-y-.008,z),.055,'white')
  if not lod:
   for x in (-.15,.15):
    self.beam('door-handle',(x,-.921,-2.70),(x,-.921,-2.46),.026,'dark')
    for z,y in [(-2.70,-.888),(-2.46,-.881)]:self.beam('handle-mount',(x,y,z),(x,-.921,z),.026,'dark')
  self.box('boarding-threshold',0,-.795,-3.63,1.34,.10,.03,'steel')
  # Fine horizontal lower-shell ribs on ends, seated on each real sloping face.
  if not lod:
   for i in range(4):
    z=-3.52+i*.09;t=(z+3.68)/.60;lx=.86+.085*t;wy=.785+.105*t
    for sx in (-1,1):self.box('lower-rib',sx*(lx+.005),0,z,.018,1.18,.018,'steel')
    self.box('rear-lower-rib',0,wy+.005,z,1.25,.018,.018,'steel')
  # Broad end windows have a top ventilation strip and visible internal handrail.
  for sx in (-1,1):
   self.box('end-vent-frame',sx*.866,0,-1.76,.025,1.15,.15,'dark')
   if not lod:
    for i in range(3):self.box('vent-slat',sx*.883,0,-1.74+i*.04,.012,1.10,.012,'steel')
   self.beam('interior-handhold',(sx*.80,-.62,-2.57),(sx*.80,.62,-2.57),.026,'steel')
   for y in (-.62,.62):self.beam('handhold-wall-mount',(sx*.80,y,-2.57),(sx*.94,y,-2.57),.026,'steel')
  # A thin roof saddle and yoke support the curved hanger, no freestanding post.
  self.box('roof-saddle',0,0,-1.27,.80,.75,.09,'steel')
  self.cylinder('yoke-pivot',(0,-.47,-1.12),(0,.47,-1.12),.075,'steel',n)
  for y in (-.38,.38):
   self.beam('yoke-leg',(-.28,y,-1.24),(0,y,-1.10),.075,'steel')
   self.beam('yoke-leg',(.28,y,-1.24),(0,y,-1.10),.075,'steel')
  # Photo ratio: hanger ≈0.85 of body height. Shift body, not body dimensions.
  self.transform(0,lambda p:(p[0],p[1],p[2]-.78));floor-=.78
  hanger=[(0,0,-1.90),(0,.02,-1.60),(0,.34,-1.54),(0,.50,-1.34),(0,.48,-.72),(0,.38,-.37),(0,.12,-.09)]
  self.tube('curved-hanger',hanger,.066,'steel',lod)
  self.box('grip-body',0,0,-.17,.62,.26,.10,'steel')
  self.box('grip-lower-jaw',0,0,-.07,.58,.18,.02,'dark')
  for y in (-.07,.07):self.box('grip-jaw',0,y,-.05,.58,.04,.12,'steel')
  self.box('grip-top-link',0,0,.07,.58,.18,.035,'steel')
  if not lod:
   for x in (-.28,.20):self.beam('spring-bracket',(x,-.10,-.12),(x,-.18,.16),.04,'steel')
   self.cylinder('opener-spring-core',(-.28,-.18,.16),(.20,-.18,.16),.04,'dark',12)
   for i in range(7):self.cylinder('spring-coil',(-.27+i*.065,-.18,.16),(-.25+i*.065,-.18,.16),.058,'steel',8)
   self.beam('opener-lever',(.20,-.18,.16),(.43,-.18,.24),.045,'steel')
  return {'ropeAnchor':[0,0,0],'ropeAxis':[1,0,0],'boardingFloor':[0,0,floor],'doorSide':[0,-1,0],'bodyReferenceDimensions':[1.98,1.873,2.41],'floorGlassThickness':.048 if kind=='crystal' else 0,'passengerLimit':5 if kind=='crystal' else 8,'massLimitKg':400 if kind=='crystal' else 640,'notes':'closed doors; physical glass via flag2, preview/GLB blending only; no motion or load validation'}

def write_model(root,id,name,mesh,meta):
 mesh.validate(); folder=root/id/'revision-1';folder.mkdir(parents=True,exist_ok=True)
 provenance=json.dumps({'asset':{'generator':'maokong-cabin-refine/produce.py','version':'1'},'extras':{'id':id,'studiesOnly':True,'coordinates':'metres +x forward +y left +z up','solids':mesh.solids}},separators=(',',':')).encode()
 out=bytearray(struct.pack('<4sHHII',b'M3DM',1,0,len(mesh.t),len(provenance))+provenance);out+=bytes((-len(provenance))%4)
 for v,c,g in mesh.t:
  out+=struct.pack('<I',g)
  rgba=(c>>16&255)|((c>>8&255)<<8)|((c&255)<<16)|0xff000000
  for p in v:out+=struct.pack('<fffI',*p,rgba)
 path=folder/(id+'.m3dmodel');path.write_bytes(out)
 return dict(id=id,name=name,native=str(path.relative_to(root)),triangles=len(mesh.t),connectors=meta,connectorNormals={k:(meta.get('mountNormal',[0,0,-1]) if k.startswith('mount') else [0,0,1]) for k,v in meta.items() if (k.startswith('mount') or k in ['surface','boardingSurface']) and not k.endswith('Normal') and isinstance(v,list) and len(v)==3},solids=len(mesh.solids))

def main():
 ap=argparse.ArgumentParser();ap.add_argument('output',type=Path);ap.add_argument('--kind',choices=['standard','crystal']);args=ap.parse_args();root=args.output.resolve();repo=Path(__file__).resolve().parents[2]
 assert root!=repo and repo not in root.parents,'private output required'
 root.mkdir(parents=True,exist_ok=True);mf=root/'manifest.json';manifest=json.loads(mf.read_text()) if mf.exists() else {'schema_version':1,'directions':['top','bottom','left','right','front','back','isometric'],'models':[],'nativeCoordinates':'metres +x along rope +y left +z up; anchor0 floor-4.38'}
 records=[]
 for kind in ([args.kind] if args.kind else ['standard','crystal']):
  for lod in (False,True):
   m=Mesh();meta=m.cabin(kind,lod);id=kind+('-lod' if lod else '-near');records.append(write_model(root,id,('貓空一般吊廂' if kind=='standard' else '貓空水晶吊廂')+('・遠景' if lod else '・近景'),m,meta))
 ids={m['id'] for m in records};manifest['models']=[m for m in manifest['models'] if m['id'] not in ids]+records;mf.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');print([(r['id'],r['triangles']) for r in records])
if __name__=='__main__':main()
