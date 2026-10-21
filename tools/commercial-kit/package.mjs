import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {readNative, glbFromNative} from '../station-kit/package.mjs';

const root = resolve(process.argv[2]);
const manifest = JSON.parse(readFileSync(resolve(root, 'manifest.json')));

for (const record of manifest.models) {
  const native = readFileSync(resolve(root, record.native));
  const model = readNative(native);
  const glb = glbFromNative(model);
  const file = 'models/' + record.id + '.glb';
  writeFileSync(resolve(root, file), glb);
  record.glb = file;
  record.native_sha256 = createHash('sha256').update(native).digest('hex');
  record.glb_sha256 = createHash('sha256').update(glb).digest('hex');
  record.views = Object.fromEntries(manifest.directions.map(d => [d, 'views/' + record.id + '/' + d + '.png']));
}

writeFileSync(resolve(root, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log('Packaged ' + manifest.models.length + ' commercial models as embedded-buffer GLB.');
