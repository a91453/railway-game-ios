import hashlib
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from PIL import Image, ImageDraw

module_spec = importlib.util.spec_from_file_location('delivery', Path(__file__).with_name('deliver.py'))
delivery = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(delivery)


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root/'repo'
        self.repo.mkdir()
        for command in [['init', '-q'], ['config', 'user.name', 'Fixture'], ['config', 'user.email', 'fixture@example.invalid']]:
            subprocess.run(['git', '-C', str(self.repo), *command], check=True, capture_output=True)
        (self.repo/'Sources').mkdir()
        (self.repo/'Sources/fixture.txt').write_text('unchanged')
        subprocess.run(['git', '-C', str(self.repo), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.repo), 'commit', '-qm', 'fixture'], check=True)
        self.sha = subprocess.check_output(['git', '-C', str(self.repo), 'rev-parse', 'HEAD'], text=True).strip()
        self.run = self.root/'run'
        (self.run/'models').mkdir(parents=True)
        (self.run/'models/a.m3dmodel').write_bytes(b'M3DM'+struct.pack('<HHII', 1, 0, 1, 2)+b'{}\0\0'+bytes(52))
        (self.run/'models/a.glb').write_bytes(b'fixture; structural GLB validation belongs to audit/importer')
        self.manifest = {'models': [{'id': 'a', 'native': 'models/a.m3dmodel', 'glb': 'models/a.glb', 'triangles': 1, 'views': {'front':'front.png', 'back':'unselected.png'}}], 'lighting': {}}
        (self.run/'manifest.json').write_text(json.dumps(self.manifest))
        image = Image.new('RGBA', (32, 32))
        ImageDraw.Draw(image).rectangle((5, 5, 26, 26), fill=(1, 2, 3, 255))
        image.save(self.run/'front.png')
        (self.run/'source-record.json').write_text(json.dumps({'origin':'fixture', 'date':'2026-10-28', 'license':'own work', 'public_use':'yes'}))
        self.status = json.loads(Path(__file__).with_name('status-template.json').read_text())
        self.write_status()
        self.spec = {'repo': str(self.repo), 'producer': self.sha, 'rebuild': 'example rebuild', 'sources':'source-record.json', 'status':'status.json', 'pngs':['front.png']}
        self.dest = self.root/'assets/model/revision-1'

    def write_status(self):
        (self.run/'status.json').write_text(json.dumps(self.status))

    def test_curates_only_selected_files_and_validates_all_hashes(self):
        delivery.deliver(self.run, self.spec, self.dest)
        manifest = json.loads((self.dest/'manifest.json').read_text())
        self.assertEqual(manifest['models'][0]['views'], {'front':'front.png'})
        self.assertEqual(manifest['producer_commit'], self.sha)
        self.assertEqual(len(list(self.dest.rglob('*.png'))), 1)
        for line in (self.dest/'SHA256SUMS.txt').read_text().splitlines():
            digest, name = line.split('  ', 1)
            self.assertEqual(hashlib.sha256((self.dest/name).read_bytes()).hexdigest(), digest)
        with self.assertRaises(ValueError):
            delivery.deliver(self.run, self.spec, self.dest)

    def test_rejects_22_previews_and_duplicates(self):
        for pngs in [['front.png']*22, ['front.png']*2]:
            self.spec['pngs'] = pngs
            with self.assertRaises(ValueError): delivery.deliver(self.run, self.spec, self.dest)

    def test_rejects_clipped_or_truncated_png(self):
        Image.new('RGBA', (32, 32), (1, 2, 3, 255)).save(self.run/'front.png')
        with self.assertRaises(ValueError): delivery.deliver(self.run, self.spec, self.dest)
        (self.run/'front.png').write_bytes(b'\x89PNG\r\n\x1a\n')
        with self.assertRaises(Exception): delivery.deliver(self.run, self.spec, self.dest)

    def test_rejects_path_escape_archives_and_oversize(self):
        for path in ['../front.png', str(self.run/'front.png')]:
            self.spec['pngs'] = [path]
            with self.assertRaises(ValueError): delivery.deliver(self.run, self.spec, self.dest)
        self.spec['pngs'] = ['front.png']
        (self.run/'archive.zip').write_bytes(b'fixture')
        self.spec['license_files'] = ['archive.zip']
        with self.assertRaises(ValueError): delivery.deliver(self.run, self.spec, self.dest)
        self.spec['license_files'] = []
        with (self.run/'models/a.glb').open('wb') as f: f.truncate(50*1024*1024+1)
        with self.assertRaises(ValueError): delivery.deliver(self.run, self.spec, self.dest)

    def test_rejects_mismatched_producer_and_inferred_acceptance(self):
        (self.repo/'Sources/fixture.txt').write_text('changed')
        with self.assertRaises(subprocess.CalledProcessError): delivery.deliver(self.run, self.spec, self.dest)
        (self.repo/'Sources/fixture.txt').write_text('unchanged')
        self.status['appearance'] = {'status':'VERIFIED', 'evidence':'only CI passed', 'accepted_producer':None}
        self.write_status()
        with self.assertRaises(ValueError): delivery.deliver(self.run, self.spec, self.dest)
        self.assertFalse(self.dest.exists())

    def test_rejects_untracked_source_and_oversized_png(self):
        (self.repo/'Sources/new.txt').write_text('not in producer')
        with self.assertRaises(ValueError): delivery.deliver(self.run, self.spec, self.dest)
        (self.repo/'Sources/new.txt').unlink()
        image = Image.new('RGBA', (1100, 1100))
        image.paste(Image.frombytes('RGBA', (1090, 1090), os.urandom(1090*1090*4)), (5, 5))
        image.save(self.run/'front.png')
        self.assertGreater((self.run/'front.png').stat().st_size, 2*1024*1024)
        with self.assertRaisesRegex(ValueError, '2 MiB'): delivery.deliver(self.run, self.spec, self.dest)


if __name__ == '__main__': unittest.main()
