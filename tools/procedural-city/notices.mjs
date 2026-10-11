// Writes the notices of the 3D city view (decision 152): the licence of jeantimex/tokyo and of every
// library its built page bundles, from the installed packages, and the textures' CC0.
//   node tools/procedural-city/notices.mjs Web/CityView RailwayGameApp/Resources/Licenses/CityView-NOTICES.md
import fs from 'node:fs';
import path from 'node:path';

const [webArg, outArg] = process.argv.slice(2);
const web = path.resolve(webArg ?? 'Web/CityView');
const out = path.resolve(outArg ?? 'RailwayGameApp/Resources/Licenses/CityView-NOTICES.md');
// The packages in the page's bundle (src/ imports them; the compiler's own packages are not shipped).
const PACKAGES = ['three', 'postprocessing', 'n8ao', '@takram/three-atmosphere', '@takram/three-clouds', '@takram/three-geospatial',
  '@takram/three-geospatial-effects', '@dgreenheck/ez-tree', 'lil-gui', 'earcut'];
// The takram packages ship without their licence file: their repository's (MIT).
const TAKRAM = `The MIT License (MIT)

Copyright (c) 2024 Shota Matsuda

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.`;

const licenceOf = (dir) => {
  const file = fs.readdirSync(dir).find((f) => /^licen[cs]e/i.test(f));
  return file ? fs.readFileSync(path.join(dir, file), 'utf8').trim() : null;
};
const parts = [
  '# 3D city view: notices',
  '',
  'The 3D city view (ARCHITECTURE decision 152) is the web page of Procedural Tokyo',
  '(https://github.com/jeantimex/tokyo), adapted to Taiwan, with the libraries below bundled into it.',
  'Its textures are from Poly Haven (https://polyhaven.com) under CC0 1.0. The data it shows is credited',
  'on the data sources screen (Overture Maps Foundation, OpenStreetMap contributors).',
  '',
  '## Procedural Tokyo',
  '',
  '```',
  licenceOf(web),
  '```',
];
for (const name of PACKAGES) {
  const dir = path.join(web, 'node_modules', name), pkg = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8'));
  parts.push('', `## ${name} ${pkg.version} (${pkg.license})`, '', '```', licenceOf(dir) ?? (name.startsWith('@takram/') ? TAKRAM : `${pkg.license}: see ${pkg.homepage ?? pkg.repository?.url ?? name}`), '```');
}
fs.writeFileSync(out, parts.join('\n') + '\n');
console.log(`wrote ${path.relative(process.cwd(), out)}`);
