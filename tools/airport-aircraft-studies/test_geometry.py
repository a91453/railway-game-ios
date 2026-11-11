import importlib.util
import math
import unittest
from pathlib import Path

spec=importlib.util.spec_from_file_location('airport_studies',Path(__file__).with_name('produce.py'))
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
P=mod.P

def points(mesh,*names):
    return [p for s in mesh.solids if not names or s['name'] in names
            for tri,_,_ in mesh.t[s['start']:s['start']+s['count']] for p in tri]

class GeometryTests(unittest.TestCase):
    def test_aircraft_closed_grounded_and_lods(self):
        for kind, dimensions in mod.SPECS.items():
            counts=[]
            for far in (False,True):
                mesh=mod.mod.Mesh();meta=mod.aircraft(mesh,kind,far)
                mesh.validate()
                counts.append(len(mesh.t))
                self.assertEqual((meta['length_m'],meta['wingspan_m'],meta['height_m']),dimensions[:3])
                pts=points(mesh)
                self.assertAlmostEqual(min(p[2] for p in pts),0,delta=.08 if far else 1e-9)
                self.assertAlmostEqual(max(p[0] for p in pts)-min(p[0] for p in pts),dimensions[0],delta=.05)
                self.assertAlmostEqual(max(p[1] for p in pts)-min(p[1] for p in pts),dimensions[1],delta=.05)
                self.assertAlmostEqual(max(p[2] for p in pts),dimensions[2],delta=.05)
                self.assertLessEqual(len(mesh.t),15000)
                names={s['name'] for s in mesh.solids}
                self.assertTrue({'nav-red','nav-green','tail-white','anti-collision','wingtip-strobe','cabin-window'}<=names)
                if not far:self.assertIn('door',names)
                self.assertTrue(all(math.isfinite(v) for j in meta['joints'] for v in j['axis']))
                self.assertTrue(all('pivot' in j for j in meta['joints']))
            self.assertLess(counts[1],counts[0]*.7)

    # Decision 698: what the first pass got wrong, so it cannot come back.
    def test_aircraft_look(self):
        for kind,(L,W,H,_,_,_,engine) in mod.SPECS.items():
            mesh=mod.mod.Mesh();mod.aircraft(mesh,kind,False);S=mod.SHAPES[kind]
            hull=points(mesh,'fuselage')
            # A nose and a tail that close: the fuselage is not a tube with flat ends.
            front,back=max(p[0] for p in hull),min(p[0] for p in hull)
            for tip in ([p for p in hull if p[0]>front-.3],[p for p in hull if p[0]<back+.3]):
                self.assertLess(max(abs(p[1]) for p in tip),S['hw']*.45,kind)
            # The tail sweeps up: the last station's underside is above the cabin's centre.
            self.assertGreater(min(p[2] for p in hull if p[0]<back+.3),S['zc'])
            if engine=='prop':
                blades=points(mesh,'prop-blade');e=S['engine']
                self.assertEqual(sum(s['name']=='prop-blade' for s in mesh.solids),2*e['blades'])
                reach=max(math.hypot(abs(p[1])-e['y'],p[2]-e['z']) for p in blades)
                self.assertGreater(reach,e['prop']*.95);self.assertGreater(min(p[2] for p in blades),.3)
            else:
                # The intake stands ahead of the wing's leading edge.
                self.assertGreater(max(p[0] for p in points(mesh,'underwing-engine')),L/2-S['wing'][2][1]+2)
            # Wheels are round: a tyre has at least twelve sides.
            tyre=next(s for s in mesh.solids if s['name']=='tyre')
            self.assertGreaterEqual(len({(round(p[0],4),round(p[2],4)) for tri,_,_ in mesh.t[tyre['start']:tyre['start']+tyre['count']] for p in tri}),12)
            # Every painted colour is flat paint: no operator's mark is drawn.
            self.assertFalse(any('logo' in s['name'] or 'title' in s['name'] for s in mesh.solids))

    def test_airports_parts_and_scenes(self):
        for far in (False,True):
            for kind in ('city','island'):
                m=mod.mod.Mesh();meta=mod.airport(m,kind,far);m.validate()
                self.assertEqual(len(meta['jetbridges']),4 if kind=='city' else 0)
                # One ground plate under everything: nothing floats apart.
                plate=points(m,'ground-plate');rest=points(m)
                for axis in (0,1):
                    self.assertLessEqual(min(p[axis] for p in plate),min(p[axis] for p in rest)+4.5,kind)
                    self.assertGreaterEqual(max(p[axis] for p in plate),max(p[axis] for p in rest)-25,kind)
                self.assertEqual(min(p[2] for p in rest),0)
            for kind in mod.PARTS:
                m=mod.mod.Mesh();meta=mod.part(m,kind,far);m.validate()
                if kind=='runway':self.assertEqual(len(meta['thresholds']),2)
                if kind=='apron':self.assertEqual(len(meta['stands']),3)
                if kind=='stairs':self.assertEqual(sum(s['name']=='stair-side' for s in m.solids),2)
                if kind in ('runway','runway-end','taxiway','apron'):
                    paint=[s for s in m.solids if s['name'] not in ('sealed-pavement','sealed-apron','slab-joint') and 'light' not in s['name'] and 'mast' not in s['name']]
                    for s in paint:
                        bottom=min(p[2] for tri,_,_ in m.t[s['start']:s['start']+s['count']] for p in tri)
                        self.assertGreaterEqual(bottom,.085)
                if kind in ('tug','baggage','stairs','fuel'):
                    tyre=next(s for s in m.solids if s['name']=='tyre')
                    sides=len({(round(p[0],4),round(p[2],4)) for tri,_,_ in m.t[tyre['start']:tyre['start']+tyre['count']] for p in tri})
                    self.assertGreaterEqual(sides,6 if far else 12)
            for kind in ('city-scene','island-scene'):
                m=mod.mod.Mesh();meta=mod.assembly(m,kind,far);m.validate()
                self.assertEqual(len(meta['stands']),3 if kind=='city-scene' else 1)

    def test_pavement_is_grey_and_lit_at_night(self):
        for kind in ('runway','runway-end','taxiway'):
            m=mod.mod.Mesh();mod.part(m,kind,False)
            s=next(s for s in m.solids if s['name']=='sealed-pavement');c=m.t[s['start']][1]
            r,g,b=c>>16&255,c>>8&255,c&255
            self.assertLess(max(r,g,b)-min(r,g,b),16,kind)      # asphalt, not the navy of the first pass
            self.assertLess(r,120)
            glow={s['name'] for s in m.solids if m.t[s['start']][2]}
            self.assertTrue({'light-pool'}<=glow,kind)
            self.assertTrue(glow&{'edge-light','blue-edge-light'},kind)
            # A pool is the pavement's own colour, so by day it does not show.
            pool=next(s for s in m.solids if s['name']=='light-pool')
            self.assertEqual(m.t[pool['start']][1],mod.lit('asphalt' if kind!='taxiway' else 'taxi'))
        m=mod.mod.Mesh();mod.part(m,'apron',False)
        self.assertTrue({'floodlight','light-pool'}<={s['name'] for s in m.solids if m.t[s['start']][2]})

    def test_city_bridges_meet_doors_before_wings(self):
        m=mod.mod.Mesh();meta=mod.assembly(m,'city-scene',False)
        bridged=[s for s in meta['stands'] if s['jetbridge_end']]
        self.assertEqual(len(bridged),2)
        for stand in bridged:
            door,end=stand['door'],stand['jetbridge_end']
            self.assertLess(abs(door[0]-end[0]),.6);self.assertLess(abs(door[2]-end[2]),.01)
            self.assertLess(abs(abs(door[1]-end[1])-1.9),.01)     # the cab stands off the door
            wing_front=stand['nose_stop'][0]+mod.SHAPES['narrowjet']['wing'][1][1]
            self.assertGreater(wing_front,end[0]+4)

if __name__=='__main__':unittest.main()
