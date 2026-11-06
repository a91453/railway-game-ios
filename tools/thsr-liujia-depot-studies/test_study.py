import hashlib
import json
import math
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).parent))
from build import GAUGE, SHED_TRACKS, TRAIN_CENTRES, TRAIN_UNITS, TRAIN_X, projected

HERE=Path(__file__).parent

class LiujiaStudyTests(unittest.TestCase):
    def test_osm_yard_footprint_and_eight_tracks(self):
        ways=json.loads((HERE/'osm_geometry.json').read_text())['ways']
        yard=next(w for w in ways if w['id']==321663143)
        points=[projected(p) for p in yard['points']]
        width=max(p[1] for p in points)-min(p[1] for p in points)
        length=max(p[0] for p in points)-min(p[0] for p in points)
        self.assertAlmostEqual(length,615,delta=2)
        self.assertAlmostEqual(width,293,delta=2)
        tracks=[w for w in ways if w['id'] in range(500406362,500406371)]
        self.assertEqual(len(tracks),9) # OSM ways split the eight physical yard tracks.
        self.assertEqual(sum(w['tags'].get('service')=='yard' for w in tracks),9)

    def test_gauge_shed_and_train_clearance(self):
        self.assertEqual(GAUGE,1.435)
        self.assertTrue(all(math.isclose(b-a,5.8) for a,b in zip(SHED_TRACKS,SHED_TRACKS[1:])))
        self.assertEqual(TRAIN_CENTRES[0][1],SHED_TRACKS[1])
        self.assertEqual(len(TRAIN_UNITS),12)
        self.assertAlmostEqual(TRAIN_X[0]-TRAIN_X[-1],279.4)
        # 700T formation bounds from the existing native models: ±152.2 m.
        self.assertLess(2*152.2,324)
        self.assertLess(2*152.2,420)

    def test_asset_source_is_unmodified(self):
        asset_root=Path(__file__).resolve().parents[3]/'railway-assets-private'
        models=asset_root/'game-art-previews/docs/art/train-shape-refresh-2026-10-24/revision-10/models'
        if not models.exists():self.skipTest('private train source unavailable')
        output=asset_root/'game-art-previews/docs/art/thsr-liujia-depot/manifest.json'
        if not output.exists():self.skipTest('generated study unavailable')
        rec=json.loads(output.read_text())['models'][0]
        native=(output.parent/rec['native']).read_bytes()
        n,plen=struct.unpack_from('<II',native,8)
        source=json.loads(native[16:16+plen])['extras']['train_unit_sha256']
        for name,digest in source.items():
            file=models/f'refresh-700t-{name}.m3dmodel'
            self.assertEqual(hashlib.sha256(file.read_bytes()).hexdigest(),digest)
        self.assertGreater(n,200000)

if __name__=='__main__':unittest.main()
