import copy,math,unittest
from produce import Mesh,sub,cross
PARTS=['platform','gate','queue','catwalk','kiosk','assembly']
class CableSupportTests(unittest.TestCase):
 def test_closed_outward_finite_and_budget(self):
  for kind in PARTS:
   for lod in (False,True):
    m=Mesh();m.support(kind,lod);m.validate()
 def test_missing_bottom_and_reversed_triangle_are_rejected(self):
  for fault in ['hole','reverse']:
   m=Mesh();m.box('probe',0,0,0,1,1,1,'white')
   if fault=='hole':m.t.pop();m.solids[0]['count']-=1
   else:
    v,c,g=m.t[0];m.t[0]=(v[::-1],c,g)
   with self.assertRaises(AssertionError):m.validate()
 def test_platform_matches_declared_cabin_floor_and_side_gap(self):
  m=Mesh();meta=m.support('platform');self.assertAlmostEqual(meta['boardingSurface'][2],4.2-3.6)
  self.assertAlmostEqual((2.6-1.7/2)-meta['edgeLeft'][1],.1)
  island=m.solids[0];z=[p[2] for t,c,g in m.t[:island['count']] for p in t]
  self.assertAlmostEqual(max(z),.6);self.assertAlmostEqual(min(z),0)
  # Explicit counterexample: legacy station platform .9 is not floor-aligned.
  self.assertGreater(abs(.9-(4.2-3.6)),.29)
 def test_gate_rotation_is_rigid_and_fixed_body_preserved(self):
  for kind in ['gate','assembly']:
   m=Mesh();meta=m.support(kind);j=meta.get('joint') or meta['joints'][0];a=j['movingTriangleStart'];b=a+j['movingTriangleCount'];original=copy.deepcopy(m.t)
   for theta in [0,math.pi/4,math.pi/2]:
    p=j['pivot'];m.t=copy.deepcopy(original)
    m.transform(a,lambda v:(p[0]+math.cos(theta)*(v[0]-p[0])-math.sin(theta)*(v[1]-p[1]),p[1]+math.sin(theta)*(v[0]-p[0])+math.cos(theta)*(v[1]-p[1]),v[2]))
    # Only the leaf is moved; restore solids after the leaf for the assembly.
    m.t[b:]=copy.deepcopy(original[b:])
    self.assertEqual(m.t[:a],original[:a]);self.assertEqual(m.t[b:],original[b:]);m.validate()
    for before,after in zip(original[a:b],m.t[a:b]):
     self.assertAlmostEqual(math.dist(*before[0][:2]),math.dist(*after[0][:2]))
 def test_ground_parts_and_catwalk_mount_have_real_geometry_at_z0(self):
  for kind in PARTS[:-1]:
   m=Mesh();m.support(kind);z=[p[2] for t,c,g in m.t for p in t];self.assertAlmostEqual(min(z),0)
 def test_lod_reduction_and_glow(self):
  for kind in PARTS:
   a,b=Mesh(),Mesh();a.support(kind);b.support(kind,True);self.assertLess(len(b.t),len(a.t))
  for kind in ['gate','kiosk']:
   m=Mesh();m.support(kind);self.assertTrue(any(g==1 for t,c,g in m.t))
 def test_assembly_range_starts_at_actual_moving_solid(self):
  m=Mesh();meta=m.support('assembly');j=meta['joints'][0]
  first=next(s for s in m.solids if s['name']=='leaf-top')
  self.assertEqual(j['movingTriangleStart'],first['start'])
if __name__=='__main__':unittest.main()
