import importlib.util
import math
import unittest
from pathlib import Path

spec=importlib.util.spec_from_file_location('airport_studies',Path(__file__).with_name('produce.py'))
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class GeometryTests(unittest.TestCase):
    def test_aircraft_closed_grounded_and_lods(self):
        for kind, dimensions in mod.SPECS.items():
            counts=[]
            for far in (False,True):
                mesh=mod.mod.Mesh();meta=mod.aircraft(mesh,kind,far)
                mesh.validate()
                counts.append(len(mesh.t))
                self.assertEqual(meta['length_m'],dimensions[0])
                self.assertEqual(meta['wingspan_m'],dimensions[1])
                self.assertEqual(meta['height_m'],dimensions[2])
                self.assertAlmostEqual(min(p[2] for tri,_,_ in mesh.t for p in tri),0)
                self.assertLessEqual(len(mesh.t),15000)
                if not far:
                    names={s['name'] for s in mesh.solids}
                    self.assertTrue({'door','nav-red','nav-green','tail-white','anti-collision','wingtip-strobe','cabin-window'}<=names)
                    self.assertTrue(all(math.isfinite(v) for j in meta['joints'] for v in j['axis']))
            self.assertLess(counts[1],counts[0]*.7)

    def test_airports_parts_and_scenes(self):
        for far in (False,True):
            for kind in ('city','island'):
                m=mod.mod.Mesh();meta=mod.airport(m,kind,far);m.validate()
                self.assertEqual(len(meta['jetbridges']),4 if kind=='city' else 0)
            for kind in mod.PARTS:
                m=mod.mod.Mesh();meta=mod.part(m,kind,far);m.validate()
                if kind=='runway':self.assertEqual(len(meta['thresholds']),2)
                if kind=='apron':self.assertEqual(len(meta['stands']),3)
            for kind in ('city-scene','island-scene'):
                m=mod.mod.Mesh();meta=mod.assembly(m,kind,far);m.validate()
                self.assertEqual(len(meta['stands']),2 if kind=='city-scene' else 1)

    def test_city_bridge_meets_doors_before_wings(self):
        for i,kind in enumerate(('regional70','narrowjet')):
            origin=(72.5 if i==0 else 78.6,-14.2 if i==0 else 24)
            a=mod.mod.Mesh();meta=mod.aircraft(a,kind,False)
            door=(origin[0]-meta['door']['position'][0],origin[1]-meta['door']['position'][1],meta['door']['position'][2])
            bridge=(63,-17 if i==0 else 20,3.25 if i==0 else 4.35)
            self.assertLess(math.dist(door,bridge),.15)
            wings=[s for s in a.solids if s['name'] in ('left-wing','right-wing')]
            for wing in wings:
                xs=[origin[0]-p[0] for tri,_,_ in a.t[wing['start']:wing['start']+wing['count']] for p in tri]
                self.assertGreater(min(xs),63.5)

if __name__=='__main__':unittest.main()
