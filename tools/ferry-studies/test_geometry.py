import copy, math, unittest
from produce import Mesh
class FerryGeometryTests(unittest.TestCase):
 def test_every_solid_closed_outward_and_under_budget(self):
  for lod in (False,True):
   for kind in ('tamsui','cijin'):
    m=Mesh();meta=m.ferry(kind,lod);m.validate()
    hull=m.t[:m.solids[0]['count']];xs=[p[0] for t,c,g in hull for p in t];ys=[p[1] for t,c,g in hull for p in t]
    self.assertAlmostEqual(max(xs)-min(xs),meta['length_m']);self.assertAlmostEqual(max(ys)-min(ys),meta['beam_m'])
    named={s['name']:s for s in m.solids}
    for label in ('port-red','starboard-green','masthead-white','wheelhouse-window'):
     s=named[label];ts=m.t[s['start']:s['start']+s['count']];self.assertTrue(all(g==1 for _,_,g in ts))
     if label=='port-red':self.assertTrue(all(p[1]>0 for t,_,_ in ts for p in t))
     if label=='starboard-green':self.assertTrue(all(p[1]<0 for t,_,_ in ts for p in t))
   for part in ('pontoon','gangway','shelter','railing','ticket'):
    m=Mesh();m.dockpart(part,lod);m.validate()
   m=Mesh();m.dock(lod);m.validate()
 def test_topology_detects_missing_bottom_and_reversed_faces(self):
  for fault in ('missing','reverse'):
   m=Mesh();m.box('probe',0,0,0,2,2,2,'white')
   if fault=='missing':m.t.pop();m.solids[0]['count']-=1
   else:
    v,c,g=m.t[0];m.t[0]=(list(reversed(v)),c,g)
   with self.assertRaises(AssertionError):m.validate()
 def test_gangway_pivot_endpoint_and_fixed_body(self):
  m=Mesh();meta=m.dockpart('gangway',False);j=meta['joint'];start=j['movingTriangleStart'];original=copy.deepcopy(m.t)
  for theta in (-.25,0,.25):
   delta=theta-j['rest'];m.t=copy.deepcopy(original)
   m.transform(start,lambda p:(math.cos(delta)*p[0]-math.sin(delta)*p[2],p[1],math.sin(delta)*p[0]+math.cos(delta)*p[2]))
   self.assertEqual(m.t[:start],original[:start]);m.validate()
   a=m.t[start][0][0];b=m.t[start][0][1];oa=original[start][0][0];ob=original[start][0][1]
   self.assertAlmostEqual(math.dist(a,b),math.dist(oa,ob))
  self.assertAlmostEqual(meta['roller'][2],-1)
 def test_lod_reduces_geometry(self):
  for kind in ('tamsui','cijin'):
   a,b=Mesh(),Mesh();a.ferry(kind,False);b.ferry(kind,True);self.assertLess(len(b.t),len(a.t)*.7)
 def test_assembly_range_starts_at_actual_moving_solid(self):
  m=Mesh();meta=m.dock(False);j=meta['joints'][0]
  first=next(s for s in m.solids if s['name']=='ramp-deck')
  self.assertEqual(j['movingTriangleStart'],first['start'])
if __name__=='__main__':unittest.main()
