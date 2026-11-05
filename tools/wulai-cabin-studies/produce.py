#!/usr/bin/env python3
"""Original studies recipes, native x forward / y port / z up, metres.
No runtime imports or registration. Closed solids; touching mounting faces.
"""
import argparse, collections, json, math, struct
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
 # Wulai's large reversible car: metres, not an enlargement of a gondola.
 def cabin(self,lod=False):
  floor=-5.20; roof=-2.76; n=8 if lod else 16
  self.loft('closed-floor',[(-5.32,4.42,2.32,.24),(-5.20,4.62,2.52,.28)],'deck',lod)
  self.loft('glazing',[(-4.50,4.80,2.68,.30),(-3.05,4.64,2.58,.30)],'glass',lod,True,2,.012)
  self.loft('upper-header',[(-3.05,4.64,2.58,.30),(-2.89,4.62,2.56,.30)],'white',lod,True,thickness=.055)
  # Real roof aperture: no opaque plate behind its sealed skylight.
  seg=2 if lod else 6
  rings=[self.rounded(4.62,2.56,.30,-2.89,seg),self.rounded(4.60,2.54,.30,-2.76,seg),self.rounded(1.08,.65,.10,-2.89,seg),self.rounded(1.08,.65,.10,-2.76,seg)]
  N=len(rings[0]);v=[p for r in rings for p in r];f=[]
  for i in range(N):
   j=(i+1)%N
   f += [[i,j,N+j,N+i],[2*N+j,2*N+i,3*N+i,3*N+j],[j,i,2*N+i,2*N+j],[N+i,N+j,3*N+j,3*N+i]]
  self.solid('closed-roof',v,f,'white')
  self.loft('skylight-frame',[(-2.89,1.08,.65,.10),(-2.75,1.08,.65,.10)],'steel',lod,True,thickness=.04)
  self.loft('skylight-glass',[(-2.81,1.00,.57,.06),(-2.77,1.00,.57,.06)],'glass',lod,False,2)
  # Curved white corner posts follow the real body's taper at both ends.
  for sx in (-1,1):
   for sy in (-1,1):
    path=[(sx*(l/2-r+r/math.sqrt(2)),sy*(w/2-r+r/math.sqrt(2)),z) for z,l,w,r in [(-5.18,4.62,2.52,.28),(-4.50,4.80,2.68,.30),(-3.05,4.64,2.58,.30),(-2.89,4.62,2.56,.30)]]
    self.tube('corner-post',path,.075,'white',lod)
  # Broad white door piers leave the centre doors and end windows legible.
  for sy in (-1,1):
   for x in (-.91,.91):
    self.box('door-pier',x,sy*1.293,-5.20,.18,.08,2.15,'white')
   for x in (-.77,0,.77):
    self.tube('door-frame',[(x,sy*1.26,-5.20),(x,sy*1.34,-4.50),(x,sy*1.29,-3.05)],.020,'steel',lod)
   for x in (-.805,.805):self.tube('door-jamb-seal',[(x,sy*1.26,-5.20),(x,sy*1.34,-4.50),(x,sy*1.29,-3.05)],.015,'dark',lod)
   # Sealed door glazing extends to the sill; solid door framing follows.
   for x in (-.385,.385):
    a=x-.365;b=x+.365;v=[(q,sy*(y-d),z) for z,y in [(-5.20,1.26),(-4.50,1.34)] for q,d in [(a,0),(b,0),(b,.012),(a,.012)]]
    f=[[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]]
    if sy>0:f=[list(reversed(face)) for face in f]
    self.solid('door-glass',v,f,'glass',2)
   self.box('door-sill',0,sy*1.26,-5.20,1.60,.10,.03,'steel')
   # Remove the lower body across each door opening, by explicit panel cuts
   # below rather than an opaque plate behind transparent door glass.
   for x in (-.46,.46):
    self.beam('door-handle',(x,sy*1.34,-4.40),(x,sy*1.34,-4.04),.025,'dark')
    for z in (-4.40,-4.04):self.beam('handle-mount',(x,sy*1.31,z),(x,sy*1.34,z),.025,'steel')
   self.beam('window-rail',(-2.06,sy*1.342,-4.50),(2.06,sy*1.342,-4.50),.045,'steel')
  # Closed annular wall sectors leave the central door cavities open.
  rings=[self.rounded(l,w,r,z,2 if lod else 6) for z,l,w,r in [(-5.20,4.62,2.52,.28),(-4.50,4.80,2.68,.30)]]
  inner=[self.rounded(l-.11,w-.11,r-.055,z,2 if lod else 6) for z,l,w,r in [(-5.20,4.62,2.52,.28),(-4.50,4.80,2.68,.30)]]
  for i in range(len(rings[0])):
   j=(i+1)%len(rings[0]);a,b=rings[1][i],rings[1][j];cuts=[0.,1.]
   if abs(a[1])>1.339 and abs(b[1]-a[1])<1e-6:
    cuts+= [(x-a[0])/(b[0]-a[0]) for x in (-.82,.82) if 0<(x-a[0])/(b[0]-a[0])<1]
   cuts=sorted(cuts)
   for lo,hi in zip(cuts,cuts[1:]):
    middle=tuple(a[k]+(b[k]-a[k])*(lo+hi)/2 for k in range(3))
    if abs(middle[1])>1.339 and abs(middle[0])<.82:continue
    def lerp(r,t):return tuple(r[i][k]+(r[j][k]-r[i][k])*t for k in range(3))
    v=[lerp(rings[0],lo),lerp(rings[0],hi),lerp(rings[1],hi),lerp(rings[1],lo),lerp(inner[0],lo),lerp(inner[0],hi),lerp(inner[1],hi),lerp(inner[1],lo)]
    self.solid('lower-wall-sector',v,[[0,1,2,3],[5,4,7,6],[1,0,4,5],[3,2,6,7],[0,3,7,4],[1,5,6,2]],'white')
  for sx in (-1,1):
   # Large end window's slim divider, set on the actual sloped end glass.
   self.beam('end-divider',(sx*2.395,0,-4.50),(sx*2.315,0,-3.05),.035,'steel')
   self.box('end-vent',sx*2.306,0,-4.92,.018,.36,.10,'steel')
  # An opaque, closed underside with identifiable load-carrying beams.
  for y in (-.92,.92):self.box('underframe-longitudinal',0,y,-5.40,4.16,.10,.08,'steel')
  for x in (-1.7,0,1.7):self.box('underframe-crossmember',x,0,-5.40,.09,2.05,.08,'steel')
  for sx in (-1,1):
   for sy in (-1,1):self.box('bumper-mount',sx*1.92,sy*1.18,-5.19,.12,.24,.12,'steel')
  for sy in (-1,1):self.beam('bumper-rail',(-1.98,sy*1.30,-5.11),(1.98,sy*1.30,-5.11),.055,'steel')
  # Interior rails and short perimeter seats are photo-based interpretation;
  # passenger capacity includes standing room, not seventy-one chairs.
  for sx in (-1,1):
   for sy in (-1,1):
    for x in (sx*1.18,sx*1.94):self.box('seat-foot',x,sy*1.02,floor,.08,.08,.40,'steel')
    self.box('seat-pan',sx*1.56,sy*1.02,floor+.40,1.16,.43,.07,'dark')
    self.box('seat-back',sx*1.56,sy*1.21,floor+.47,1.16,.05,.43,'dark')
   for z in (-4.02,-3.58):
    x=sx*(2.40-(z+4.50)*.08/1.45-.07)
    self.cylinder('end-guardrail',(x,-1.02,z),(x,1.02,z),.018,'steel',n)
    for y in (-1.02,1.02):self.beam('guardrail-mount',(x,y,z),(x+sx*.06,y,z),.025,'steel')
  for x in (-1.52,1.52):
   for y in (-.88,.88):
    self.cylinder('grab-pole',(x,y,floor),(x,y,-2.89),.024,'steel',n)
    self.cylinder('pole-floor-pad',(x,y,floor),(x,y,floor+.024),.055,'steel',n)
  for y in (-.88,.88):
   self.cylinder('overhead-grab-rail',(-1.52,y,-3.17),(1.52,y,-3.17),.026,'red',n)
   for x in ((-.8,.8) if lod else (-1.0,-.5,.5,1.0)):
    self.tube('hanging-grip',[(x-.07,y,-3.17),(x-.07,y,-3.42),(x+.07,y,-3.42),(x+.07,y,-3.17)],.013,'red',lod)
  for x in (-1.2,1.2):
   self.box('ceiling-lamp-mount',x,0,-2.92,.55,.22,.03,'steel')
   self.box('ceiling-lamp',x,0,-2.932,.49,.16,.012,'warm',1)
  # Two A-frame planes. All feet are seated on the real flat roof shoulder.
  pitch=math.asin(164.59/382);co=math.cos(pitch);si=math.sin(pitch)
  pivot=(.40*si,0,-.40*co)
  for sy in (-1,1):
   peak=(pivot[0],sy*.55,pivot[2])
   for sx in (-1,1):
    foot=(sx*1.77,sy*.55,roof)
    self.box('roof-hanger-pad',foot[0],foot[1],roof,.27,.24,.08,'steel')
    self.beam('hanger-leg',add(foot,(0,0,.08)),peak,.09,'steel')
   z=-1.58;t=(z-pivot[2])/(roof+.08-pivot[2]);left=(pivot[0]+(-1.77-pivot[0])*t,sy*.55,z);right=(pivot[0]+(1.77-pivot[0])*t,sy*.55,z)
   self.beam('hanger-crossbar',left,right,.065,'steel')
   self.beam('hanger-diagonal',(-1.77,sy*.55,roof+.08),right,.034,'dark')
   self.beam('hanger-diagonal',(1.77,sy*.55,roof+.08),left,.034,'dark')
  for x in (-1.77,1.77):self.beam('roof-hanger-crosslink',(x,-.55,roof+.08),(x,.55,roof+.08),.07,'steel')
  self.cylinder('hanger-pivot',(pivot[0],-.76,pivot[2]),(pivot[0],.76,pivot[2]),.13,'steel',n)
  # Trolley: two rows of eight wheels, each tangent to its own support rope.
  def T(p):return (co*p[0]-si*p[2],p[1],si*p[0]+co*p[2])
  start=len(self.t)
  for y in (-.55,.55):
   for i in range(8):
    x=(i-3.5)*.36
    self.cylinder('trolley-wheel',(x,y-.055,.17),(x,y+.055,.17),.17,'steel',8 if lod else 16)
    if not lod:
     for a,b in [(y-.055,y-.038),(y+.038,y+.055)]:self.cylinder('wheel-flange',(x,a,.17),(x,b,.17),.185,'steel',16)
     self.cylinder('wheel-hub',(x,y-.062,.17),(x,y+.062,.17),.065,'dark',12)
    self.cylinder('wheel-axle',(x,y-.15,.17),(x,y+.15,.17),.038,'dark',8)
   self.box('carriage-longitudinal',0,y-.14*(1 if y>0 else -1),.17,2.94,.10,.12,'white')
  for x in (-1.08,0,1.08):self.box('carriage-crossmember',x,0,.20,.09,1.00,.10,'steel')
  for x in (-.80,.80):
   for y in (-.40,.40):self.beam('carriage-suspension-link',(x,y,.20),(0,y,-.40),.075,'white')
  self.box('carriage-pivot-saddle',0,0,-.45,.28,1.04,.10,'white')
  self.transform(start,T)
  return dict(ropeAnchor=[0,0,0],ropeAxis=[co,0,si],supportRopes=[[0,-.55,0],[0,.55,0]],ropeSpacingEstimate=1.10,hangerPivot=list(pivot),boardingFloor=[0,0,floor],doorSides=[[0,-1,0],[0,1,0]],doorClearWidthEstimate=1.50,bodyDimensionsEstimate=[4.80,2.68,2.56],dimensionStatus='外廓、門寬、輪徑、索距與機構尺寸全為比例推估；無原廠圖',passengerLimit=71,passengerSource='新北市觀光旅遊網 2026-09-22 第六代',historicalCapacity=91,wheelCount=16,wheelCountStatus='雙列各8輪的外觀研究；現代精確輪系未取得原廠圖',displayRopePitchDegrees=math.degrees(pitch),pitchStatus='由公開斜距與高差計算的平均線坡度，只供展示',massLimitKg=None,notes='static closed doors; solid floor; no runtime registration; native glass requires explicit Map3DTransparentGlass opt-in')


def write_model(root,id,mesh,meta):
 mesh.validate();folder=root/id/'revision-1';folder.mkdir(parents=True,exist_ok=True)
 provenance=json.dumps({'asset':{'generator':'wulai-cabin-studies/produce.py','version':'1'},'extras':{'id':id,'studiesOnly':True,'coordinates':'metres +x along projected rope +y left +z up','solids':mesh.solids}},separators=(',',':')).encode()
 out=bytearray(struct.pack('<4sHHII',b'M3DM',1,0,len(mesh.t),len(provenance))+provenance);out+=bytes((-len(provenance))%4)
 for v,c,g in mesh.t:
  out+=struct.pack('<I',g);rgba=(c>>16&255)|((c>>8&255)<<8)|((c&255)<<16)|0xff000000
  for p in v:out+=struct.pack('<fffI',*p,rgba)
 path=folder/(id+'.m3dmodel');path.write_bytes(out)
 return dict(id=id,name='烏來第六代大型吊廂'+('・近景' if id.endswith('near') else '・遠景'),native=str(path.relative_to(root)),triangles=len(mesh.t),connectors=meta,solids=len(mesh.solids))

def main():
 ap=argparse.ArgumentParser();ap.add_argument('output',type=Path);args=ap.parse_args();root=args.output.resolve();repo=Path(__file__).resolve().parents[2]
 assert root!=repo and repo not in root.parents,'private output required'
 root.mkdir(parents=True,exist_ok=True);records=[]
 for lod in (False,True):
  mesh=Mesh();meta=mesh.cabin(lod);records.append(write_model(root,'wulai-'+('lod' if lod else 'near'),mesh,meta))
 (root/'manifest.json').write_text(json.dumps(dict(schema_version=1,directions=['top','bottom','left','right','front','back','isometric'],models=records,nativeCoordinates='metres +x forward +y left +z up; support rope midpoint origin'),ensure_ascii=False,indent=2)+'\n')
 print([(r['id'],r['triangles']) for r in records])
if __name__=='__main__':main()
