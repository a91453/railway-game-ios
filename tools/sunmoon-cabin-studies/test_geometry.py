"""Contacts are checked against actual triangles, including failure mutations."""
import unittest,math
from produce import Mesh,sub,cross,P

def named(m,name):
 return [v for s in m.solids if s['name']==name for v,c,g in m.t[s['start']:s['start']+s['count']]]
def bounds(points):return [min(p[k] for t in points for p in t) for k in range(3)],[max(p[k] for t in points for p in t) for k in range(3)]
def component(m,name):
 result=Mesh();result.t=[t for s in m.solids if s['name']==name for t in m.t[s['start']:s['start']+s['count']]];return result
def ray(m,origin,d):
 hits=[]
 for v,c,g in m.t:
  e1=sub(v[1],v[0]);e2=sub(v[2],v[0]);h=cross(d,e2);a=sum(x*y for x,y in zip(e1,h))
  if abs(a)<1e-9:continue
  f=1/a;s=sub(origin,v[0]);u=f*sum(x*y for x,y in zip(s,h))
  if u<0 or u>1:continue
  q=cross(s,e1);w=f*sum(x*y for x,y in zip(d,q))
  if w<0 or u+w>1:continue
  t=f*sum(x*y for x,y in zip(e2,q))
  if t>=0:hits.append((t,g))
 return sorted(hits)
def review(m,kind):
 m.validate();crystal=kind=='crystal';glass=component(m,'glazing');roof=component(m,'closed-roof');panel=component(m,'solar-panel-frame')
 low,high=bounds(named(m,'closed-roof')+named(m,'lower-perimeter'));assert abs(high[2]-low[2]-2.20)<1e-6
 low,high=bounds(named(m,'glazing'));assert abs(high[0]-low[0]-2.20)<1e-6 and abs(high[1]-low[1]-1.90)<1e-6
 for z in [-3.72,-3.40,-2.65,-1.82]:assert ray(glass,(3,0,z),(-1,0,0))
 wide=3-ray(glass,(3,0,-2.65),(-1,0,0))[0][0];narrow=3-ray(glass,(3,0,-1.82),(-1,0,0))[0][0];assert wide-narrow>.15,'not a bowed cabin'
 floorhits=ray(m,(0,0,-5),(0,0,1));assert floorhits and floorhits[0][0]<1.3 and floorhits[0][1]==(2 if crystal else 0),'wrong or masked floor'
 if crystal:
  a,b=bounds(named(m,'glass-floor-estimated-40mm'));assert abs(b[2]-a[2]-.04)<1e-6 and abs(b[2]+3.78)<1e-6;assert not named(m,'solid-floor')
 else:assert named(m,'solid-floor') and not named(m,'glass-floor-estimated-40mm')
 for s in m.solids:
  lo,hi=bounds([v for v,c,g in m.t[s['start']:s['start']+s['count']]])
  if s['name']=='seat-support':
   assert abs(lo[2]+3.78)<1e-6,'floating seat foot'
   x=(lo[0]+hi[0])/2;y=(lo[1]+hi[1])/2
   floor=component(m,'floor-frame' if crystal else 'solid-floor');surface=ray(floor,(x,y,-3),(0,0,-1));assert surface and abs(-3-surface[0][0]-lo[2])<1e-6,'seat misses actual floor/frame'
  if s['name']=='solar-mount':
   x=(lo[0]+hi[0])/2;y=(lo[1]+hi[1])/2;top=ray(roof,(x,y,0),(0,0,-1));under=ray(panel,(x,y,-2),(0,0,1))
   assert top and under and abs(-top[0][0]-lo[2])<1e-6 and abs(-2+under[0][0]-hi[2])<1e-6,'solar panel/foot gap'
  if s['name']=='latch-mount':
   x=(lo[0]+hi[0])/2;z=(lo[2]+hi[2])/2;surfaces=sorted(set(round(-2+d,6) for d,g in ray(glass,(x,-2,z),(0,1,0))))
   assert surfaces[0]<hi[1]<surfaces[1],'latch misses glazing'
 # Large end pane must be visible. No solid stand-in behind inspection images.
 assert ray(m,(3,0,-2.7),(-1,0,0))[0][1]==2,'window buried'
 for s in m.solids:
  if s['name']=='door-frame':
   lo,hi=bounds([v for v,c,g in m.t[s['start']:s['start']+s['count']]])
   assert abs(min(abs(lo[0]),abs(hi[0]))-.4)<1e-6,'opening width not .8'
 assert sum(s['count'] for s in m.solids)==len(m.t)
 assert set(g for v,c,g in m.t)=={0,1,2}
 assert all(g==1 for v,c,g in component(m,'roof-light').t)
class Geometry(unittest.TestCase):
 def test_all_variants_and_lods(self):
  for kind in ['red','yellow','blue','crystal']:
   for lod in [False,True]:
    m=Mesh();meta=m.cabin(kind,lod);review(m,kind);self.assertEqual(meta['passengerLimit'],6 if kind=='crystal' else 8);self.assertIsNone(meta['massLimitKg']);self.assertEqual(meta['boardingFloor'],[0,0,-3.78])
 def test_lod_keeps_major_bounds_and_surface(self):
  for kind in ['red','crystal']:
   a,b=Mesh(),Mesh();self.assertEqual(a.cabin(kind),b.cabin(kind,True));self.assertLess(len(b.t),len(a.t)*.55)
   for n in ['glazing','closed-roof','lower-perimeter','seat-pan','solar-panel-frame','bumper-hoop']:
    self.assertEqual(bounds(named(a,n)),bounds(named(b,n)))
 def test_regular_colours_share_geometry_not_different_type_claims(self):
  a,b,c=Mesh(),Mesh(),Mesh();a.cabin('red');b.cabin('yellow');c.cabin('blue')
  self.assertEqual(len(a.t),len(b.t));self.assertEqual(len(a.t),len(c.t))
  for (v,col,g),(w,cy,h),(p,cb,k) in zip(a.t,b.t,c.t):
   self.assertEqual((v,g),(w,h));self.assertEqual((v,g),(p,k));self.assertEqual(cy,P['yellow'] if col==P['red'] else col);self.assertEqual(cb,P['blue'] if col==P['red'] else col)
 def shift(self,m,name,delta):
  for s in m.solids:
   if s['name']==name:
    a=s['start'];b=a+s['count'];m.t[a:b]=[([tuple(x+y for x,y in zip(p,delta)) for p in v],c,g) for v,c,g in m.t[a:b]]
 def test_floating_seat_counterexample(self):
  m=Mesh();m.cabin('crystal');self.shift(m,'seat-support',(0,0,.1))
  with self.assertRaises(AssertionError):review(m,'crystal')
 def test_solar_panel_separation_counterexample(self):
  m=Mesh();m.cabin('red');self.shift(m,'solar-panel-frame',(0,0,.1))
  with self.assertRaises(AssertionError):review(m,'red')
 def test_latch_gap_counterexample(self):
  m=Mesh();m.cabin('red');self.shift(m,'latch-mount',(0,-.03,0))
  with self.assertRaises(AssertionError):review(m,'red')
 def test_masked_glass_counterexample(self):
  m=Mesh();m.cabin('crystal');m.box('bad-floor',0,0,-3.86,1,1,.01,'white')
  with self.assertRaises(AssertionError):review(m,'crystal')
 def test_window_occlusion_counterexample(self):
  m=Mesh();m.cabin('red');m.box('bad-window-mask',1.12,0,-3,.02,.7,.6,'white')
  with self.assertRaises(AssertionError):review(m,'red')
 def test_flat_body_counterexample(self):
  m=Mesh();m.cabin('red');m.transform(0,lambda p:(p[0],p[1],p[2]*.8))
  with self.assertRaises(AssertionError):review(m,'red')
 def test_open_surface_counterexample(self):
  m=Mesh();m.cabin('red');m.t[0]=m.t[1]
  with self.assertRaises(AssertionError):m.validate()
if __name__=='__main__':unittest.main()
