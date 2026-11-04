import copy,math,unittest
from produce import Mesh,posed,rotate,water_angle,ramp_end,plate_angle
PARTS=['fender','bollard','ring','rope','pile','roller','plate','gangway','mooring-demo','assembly']
class BerthingTests(unittest.TestCase):
 def test_closed_outward_finite_budget_and_lod(self):
  for kind in PARTS:
   a,b=Mesh(),Mesh();a.part(kind);b.part(kind,True);a.validate();b.validate();self.assertLess(len(b.t),len(a.t))
 def test_missing_face_and_reverse_are_rejected(self):
  for fault in ['hole','reverse']:
   m=Mesh();m.box('probe',0,0,0,1,1,1,'white')
   if fault=='hole':m.t.pop();m.solids[0]['count']-=1
   else:
    v,c,g=m.t[0];m.t[0]=(v[::-1],c,g)
   with self.assertRaises(AssertionError):m.validate()
 def test_wall_mounts_are_actual_x0_faces(self):
  for kind in ['fender','ring']:
   m=Mesh();meta=m.part(kind);self.assertEqual(meta['mountNormal'],[-1,0,0]);self.assertAlmostEqual(min(p[0] for t,c,g in m.t for p in t),0)
 def test_rig_fixed_vertices_and_rigid_components(self):
  for kind in ['pile','plate','gangway','assembly']:
   m=Mesh();meta=m.part(kind);original=copy.deepcopy(m.t);j=meta['joint'];moving={i for a,n in j['ranges'] for i in range(a,a+n)}
   for value in [j['limit'][0],j['rest'],j['limit'][1]]:
    m.t=copy.deepcopy(original);result=posed(m,meta,value)
    for i,(before,after) in enumerate(zip(original,result)):
     if i not in moving:self.assertEqual(before,after)
     self.assertAlmostEqual(math.dist(*before[0][:2]),math.dist(*after[0][:2]))
    m.t=result;m.validate()
 def test_clamp_and_nan(self):
  m=Mesh();meta=m.part('pile');self.assertEqual(posed(m,meta,999),posed(m,meta,.3));self.assertEqual(posed(m,meta,float('nan')),posed(m,meta,0))
 def test_wheel_bottom_and_plate_feet_touch_deck_through_range(self):
  m=Mesh();meta=m.part('assembly');original=copy.deepcopy(m.t)
  wheels=[s for s in m.solids if s['name']=='wheel'];self.assertEqual(len(wheels),2)
  for h in [-.3,-.15,0,.15,.3]:
   result=posed(m,meta,h)
   # Actual polygon wheels approximate analytic circles: error stays <2 mm.
   for wheel in wheels:
    z=min(p[2] for t,c,g in result[wheel['start']:wheel['start']+wheel['count']] for p in t)
    self.assertLess(abs(z-(.65+h)),.002)
   a=water_angle(h);c=rotate((6.1,0,-.18),(0,0,0),a)
   self.assertAlmostEqual(1.65+c[2]-.06,.65+h)
   end=ramp_end(h);foot=tuple(x+y for x,y in zip(end,rotate((.8,0,0),(0,0,0),plate_angle(h))))
   self.assertAlmostEqual(foot[2],.65+h);self.assertGreater(foot[0],-4);self.assertLess(foot[0],4)
 def test_old_slope_would_sink_rollers(self):
  old=-math.asin(1/6.1);wheel=rotate((6.1,0,-.18),(0,0,0),old)
  self.assertLess(1.65+wheel[2]-.06,.65-.20)
 def test_rope_ends_match_dedicated_bitt_points(self):
  m=Mesh();meta=m.part('mooring-demo');self.assertAlmostEqual(meta['lineEndA'][0],-1.2+.23);self.assertAlmostEqual(meta['lineEndB'][0],1.2-.23)
if __name__=='__main__':unittest.main()
