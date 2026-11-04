"""Geometry checks include support gaps and material occlusion counterexamples."""
import unittest,math
from produce import Mesh,sub,cross

def named(m,name):
 return [v for s in m.solids if s['name']==name for v,c,g in m.t[s['start']:s['start']+s['count']]]
def bounds(points):return [min(p[k] for t in points for p in t) for k in range(3)],[max(p[k] for t in points for p in t) for k in range(3)]
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
 m.validate();low,high=bounds(named(m,'closed-roof')+named(m,'lower-shell-inner-outer'))
 assert abs(high[2]-low[2]-2.41)<1e-6
 b0,b1=bounds(named(m,'corner-rubber-pad'));assert abs(b1[0]-b0[0]-1.98)<1e-6 and abs(b1[1]-b0[1]-1.873)<1e-6
 for s in m.solids:
  if s['name']=='seat-support':
   lo,hi=bounds([v for v,c,g in m.t[s['start']:s['start']+s['count']]])
   assert abs(lo[2]+4.38)<1e-6,'floating feet'
   assert abs(lo[0])>=.69 or abs(hi[0])>=.69,'feet miss floor frame'
 h=ray(m,(0,0,-5),(0,0,1));assert h and h[0][0]<.8
 assert h[0][1]==(2 if kind=='crystal' else 0),'opaque plate masks crystal floor'
 glass=named(m,'glass-floor-48mm')
 if kind=='crystal':
  a,b=bounds(glass);assert abs(b[2]-a[2]-.048)<1e-6 and abs(b[2]+4.38)<1e-6
  assert not named(m,'solid-floor')
 else:assert not glass and named(m,'solid-floor')
 glazing=Mesh();glazing.t=[t for item in m.solids if item['name']=='glazing' for t in m.t[item['start']:item['start']+item['count']]]
 for item in m.solids:
  if item['name']=='handle-mount':
   lo,hi=bounds([v for v,c,g in m.t[item['start']:item['start']+item['count']]])
   hits=ray(glazing,((lo[0]+hi[0])/2,-2,(lo[2]+hi[2])/2),(0,1,0));surfaces=sorted(set(round(-2+d,6) for d,g in hits))
   assert surfaces[0]<hi[1]<surfaces[1],'handle bracket misses glazing'
 h0,h1=bounds(named(m,'curved-hanger'));assert h1[1]-h0[1]>.4,'straight mast substituted'
 # Centre of large end pane: glazing must be first hit, not a solid dummy wall.
 h=ray(m,(3,0,-3),( -1,0,0));assert h[0][1]==2,'end window buried'
class Geometry(unittest.TestCase):
 def test_all_closed_outward_and_materials(self):
  for k in ['standard','crystal']:
   for lod in [False,True]:
    m=Mesh();meta=m.cabin(k,lod);review(m,k);self.assertEqual(meta['boardingFloor'],[0,0,-4.38]);self.assertEqual(meta['passengerLimit'],5 if k=='crystal' else 8)
 def test_lod_keeps_bounds_floor_and_benches(self):
  for k in ['standard','crystal']:
   a,b=Mesh(),Mesh();ma=a.cabin(k);mb=b.cabin(k,True)
   self.assertEqual(ma,mb);self.assertLess(len(b.t),len(a.t)*.55)
   for name in ['closed-roof','lower-shell-inner-outer','seat','glass-floor-48mm','corner-rubber-pad']:
    if named(a,name):self.assertEqual(bounds(named(a,name)),bounds(named(b,name)))
 def test_floating_seat_counterexample(self):
  m=Mesh();m.cabin('crystal');s=next(s for s in m.solids if s['name']=='seat-support');a=s['start'];b=a+s['count'];m.t[a:b]=[([(x,y,z+.1) for x,y,z in v],c,g) for v,c,g in m.t[a:b]]
  with self.assertRaises(AssertionError):review(m,'crystal')
 def test_masked_glass_counterexample(self):
  m=Mesh();m.cabin('crystal');m.box('hidden-opaque-plate',0,0,-4.46,1.38,1.24,.01,'white')
  with self.assertRaises(AssertionError):review(m,'crystal')
 def test_flat_body_counterexample(self):
  m=Mesh();m.cabin('standard');m.transform(0,lambda p:(p[0],p[1],p[2]*.8))
  with self.assertRaises(AssertionError):review(m,'standard')
 def test_straight_hanger_counterexample(self):
  m=Mesh();m.cabin('standard');s=next(s for s in m.solids if s['name']=='curved-hanger');a=s['start'];b=a+s['count'];m.t[a:b]=[([(x,y*.15,z) for x,y,z in v],c,g) for v,c,g in m.t[a:b]]
  with self.assertRaises(AssertionError):review(m,'standard')
 def test_handle_mount_gap_counterexample(self):
  m=Mesh();m.cabin('standard');s=next(s for s in m.solids if s['name']=='handle-mount');a=s['start'];b=a+s['count'];m.t[a:b]=[([(x,y-.01,z) for x,y,z in v],c,g) for v,c,g in m.t[a:b]]
  with self.assertRaises(AssertionError):review(m,'standard')
 def test_open_surface_counterexample(self):
  m=Mesh();m.cabin('standard');m.t[0]=m.t[1]
  with self.assertRaises(AssertionError):m.validate()
if __name__=='__main__':unittest.main()
