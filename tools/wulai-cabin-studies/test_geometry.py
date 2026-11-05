"""Actual-mesh checks and failure mutations for the large reversible cabin."""
import copy,math,unittest
from produce import Mesh,sub,cross

def pieces(m,name):return [s for s in m.solids if s['name']==name]
def triangles(m,s):return [v for v,c,g in m.t[s['start']:s['start']+s['count']]]
def bounds(ts):return ([min(p[k] for t in ts for p in t) for k in range(3)],[max(p[k] for t in ts for p in t) for k in range(3)])
def ray(m,origin,d):
 hits=[]
 for v,c,g in m.t:
  a,b=sub(v[1],v[0]),sub(v[2],v[0]);h=cross(d,b);det=sum(x*y for x,y in zip(a,h))
  if abs(det)<1e-9:continue
  f=1/det;s=sub(origin,v[0]);u=f*sum(x*y for x,y in zip(s,h))
  if not 0<=u<=1:continue
  q=cross(s,a);w=f*sum(x*y for x,y in zip(d,q))
  if w<0 or u+w>1:continue
  t=f*sum(x*y for x,y in zip(b,q))
  if t>1e-7:hits.append((t,g))
 return sorted(hits)
def subset(m,name):
 out=Mesh();out.t=[t for s in pieces(m,name) for t in m.t[s['start']:s['start']+s['count']]];return out
def review(m,meta):
 m.validate();assert meta['passengerLimit']==71 and meta['massLimitKg'] is None
 assert len(pieces(m,'trolley-wheel'))==16
 floor=subset(m,'closed-floor');roof=subset(m,'closed-roof')
 # Ordinary opaque floor, with no opaque plate masking the real roof aperture.
 assert ray(m,(0,0,-7),(0,0,1))[0][1]==0
 assert ray(m,(0,0,1),(0,0,-1))[0][1]==2,'skylight buried'
 for s in pieces(m,'seat-foot'):
  low,high=bounds(triangles(m,s));x=(low[0]+high[0])/2;y=(low[1]+high[1])/2
  hit=ray(floor,(x,y,-4),(0,0,-1));assert hit and abs(-4-hit[0][0]-low[2])<1e-6,'floating seat foot'
 for s in pieces(m,'roof-hanger-pad'):
  low,high=bounds(triangles(m,s));x=(low[0]+high[0])/2;y=(low[1]+high[1])/2
  hit=ray(roof,(x,y,0),(0,0,-1));assert hit and abs(-hit[0][0]-low[2])<1e-6,'hanger foot misses actual roof'
 walls=subset(m,'lower-wall-sector')
 for sy in (-1,1):
  for x in (-1.5,1.5):
   g=ray(subset(m,'glazing'),(x,sy*4,-4.4999),(0,-sy,0));w=ray(walls,(x,sy*4,-4.5001),(0,-sy,0))
   assert g and w and abs(g[0][0]-w[0][0])<5e-5,'glass detached from lower shell'
 pitch=math.radians(meta['displayRopePitchDegrees']);co,si=math.cos(pitch),math.sin(pitch)
 for s in pieces(m,'trolley-wheel'):
  # De-rotate the actual transformed solid, then sample the running groove.
  points=[(co*p[0]+si*p[2],p[1],-si*p[0]+co*p[2]) for t in triangles(m,s) for p in t]
  assert abs(min(p[2] for p in points))<1e-6,'wheel lifted from support rope'
  y=(min(p[1] for p in points)+max(p[1] for p in points))/2
  assert abs(abs(y)-.55)<1e-6,'wheel misses its support rope'
 # Main side/end glass stays visible, including the lower door glass.
 for sx in (-1,1):assert ray(m,(sx*4,.4,-3.9),(-sx,0,0))[0][1]==2,'end glass buried'
 for sy in (-1,1):
  for x in (-1.5,1.5):assert ray(m,(x,sy*4,-3.7),(0,-sy,0))[0][1]==2,'side glass buried'
  assert ray(m,(.30,sy*4,-4.9),(0,-sy,0))[0][1]==2,'lower door masked'
  jamb=ray(m,(.805,sy*4,-4.85),(0,-sy,0))
  assert jamb and jamb[0][0]<3 and jamb[0][1]==0,'open door jamb gap'
 # Near and LOD each carry their own connected mechanism and emissive lamps.
 assert len(pieces(m,'hanger-leg'))==4 and len(pieces(m,'ceiling-lamp'))==2
 assert set(g for v,c,g in m.t)=={0,1,2}
 assert all(g==1 for v,c,g in subset(m,'ceiling-lamp').t)
 return True

def shift(m,name,delta):
 for s in pieces(m,name):
  a=s['start'];b=a+s['count'];m.t[a:b]=[([tuple(x+y for x,y in zip(p,delta)) for p in v],c,g) for v,c,g in m.t[a:b]]
class Geometry(unittest.TestCase):
 def make(self,lod=False):
  m=Mesh();meta=m.cabin(lod);return m,meta
 def test_near_and_lod(self):
  for lod in [False,True]:m,meta=self.make(lod);self.assertTrue(review(m,meta))
 def test_lod_retains_hull_bounds_capacity_and_contacts(self):
  a,ma=self.make();b,mb=self.make(True);self.assertEqual(ma,mb);self.assertLess(len(b.t),len(a.t)*.55)
  for name in ['glazing','closed-floor','closed-roof','door-glass','seat-pan']:
   self.assertEqual(bounds([v for s in pieces(a,name) for v in triangles(a,s)]),bounds([v for s in pieces(b,name) for v in triangles(b,s)]))
 def test_seat_gap_rejected(self):
  m,meta=self.make();shift(m,'seat-foot',(0,0,.1))
  with self.assertRaises(AssertionError):review(m,meta)
 def test_hanger_gap_rejected(self):
  m,meta=self.make();shift(m,'roof-hanger-pad',(0,0,.1))
  with self.assertRaises(AssertionError):review(m,meta)
 def test_wheel_lift_rejected(self):
  m,meta=self.make();shift(m,'trolley-wheel',(0,0,.1))
  with self.assertRaises(AssertionError):review(m,meta)
 def test_window_occluder_rejected(self):
  m,meta=self.make();m.box('bad-mask',1.5,1.5,-4.1,.5,.02,.8,'white')
  with self.assertRaises(AssertionError):review(m,meta)
 def test_detached_glazing_rejected(self):
  m,meta=self.make();shift(m,'glazing',(0,.08,0))
  with self.assertRaises(AssertionError):review(m,meta)
 def test_missing_jamb_seal_rejected(self):
  m,meta=self.make();shift(m,'door-jamb-seal',(10,0,0))
  with self.assertRaises(AssertionError):review(m,meta)
 def test_roof_glass_mask_rejected(self):
  m,meta=self.make();m.box('bad-roof',0,0,-2.73,.8,.5,.02,'white')
  with self.assertRaises(AssertionError):review(m,meta)
 def test_open_surface_rejected(self):
  m,meta=self.make();m.t[0]=m.t[1]
  with self.assertRaises(AssertionError):m.validate()
if __name__=='__main__':unittest.main()
