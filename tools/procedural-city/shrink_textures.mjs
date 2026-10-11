// Re-encodes the city view's CC0 textures (Web/CityView/public/textures, fetched at 1K by
// tools/assets/fetch_textures.mjs) at 512 pixels, to keep the app small (decision 152): the page
// scales every layer to 1024 when it builds its texture arrays (src/world/textures.js), so only the
// detail of the surface finish is softer. Files already shrunk are left alone.
//   node tools/procedural-city/shrink_textures.mjs Web/CityView
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const web = path.resolve(process.argv[2] ?? 'Web/CityView');
const sharp = createRequire(path.join(web, 'package.json'))('sharp');
const SIZE = 512, QUALITY = 80;
const dir = path.join(web, 'public/textures');
let before = 0, after = 0;
for (const set of fs.readdirSync(dir)) {
  const folder = path.join(dir, set);
  if (!fs.statSync(folder).isDirectory()) continue;
  for (const file of fs.readdirSync(folder).filter((f) => f.endsWith('.jpg'))) {
    const p = path.join(folder, file), input = fs.readFileSync(p), meta = await sharp(input).metadata();
    before += input.length;
    if (meta.width <= SIZE) { after += input.length; continue; }
    const output = await sharp(input).resize(SIZE, SIZE).jpeg({ quality: QUALITY, mozjpeg: true }).toBuffer();
    fs.writeFileSync(p, output);
    after += output.length;
  }
}
console.log(`textures: ${(before / 1e6).toFixed(1)} MB -> ${(after / 1e6).toFixed(1)} MB`);
