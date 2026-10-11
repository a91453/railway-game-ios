// Renders the 3D city view's rolling stock headlessly, so a train can be looked at and checked
// without a device. It boots Web/CityView's own dev server, builds a Trains set on a straight
// synthetic line, measures the result, and lays several viewpoints out in one PNG.
//
//   (cd Web/CityView && npm ci)   # once
//   NODE_PATH="$(npm root -g)" node .claude/skills/rolling-stock/preview.cjs \
//     --stock hsr --out /path/in/scratchpad/sheet.png [--check-only] [--port 5321]
//
// --stock      which stock to put on the line: hsr (台灣高鐵), tra (台鐵, the rotation's first
//              entry), or a line name to match, e.g. --stock '山手線'.
// --check-only run the gates and print them; draw nothing.
// --atlas      also write the stock's livery picture, as the painter made it, to this file.
// --reference  a reference model (.glb) to draw beside ours from the same cameras, scaled to
//              --reference-metres along its longest axis. A reference model is ground truth for
//              shape and colour in a way a photograph is not — no perspective, no specular streak
//              read as paint, no hidden far side. It is never shipped: the owner's EMU3000 is
//              199,588 triangles against about 3,300 for a whole set here. Measure one first with
//              measure.cjs; this is for looking.
//
// The gates run before the picture, because every one of them catches a defect that a render can
// hide: a car sunk below the rail reads fine from the side, and a nose that barely tapers reads
// fine until it is next to the real thing. They are measured on the built geometry, not on what
// the spec claims. A failing gate exits 1.
//
// Uses the Chromium the cloud environment already has (Playwright); nothing is downloaded.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { chromium } = require('playwright');

const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : fallback;
};
const stock = flag('stock', 'hsr');
const atlas = flag('atlas', null);
const reference = flag('reference', null);
const referenceMetres = Number(flag('reference-metres', '0'));
const out = flag('out', null);
const port = Number(flag('port', '5321'));
const checkOnly = args.includes('--check-only');
if (!out && !checkOnly) {
  console.error('give --out <file.png>, or --check-only');
  process.exit(2);
}

const ROOT = path.resolve(__dirname, '../../..');
const WEB = path.join(ROOT, 'Web/CityView');
const PAGE = path.join(WEB, '.rolling-stock-preview.html');   // transient; removed in the finally below
const VITE = path.join(WEB, 'node_modules/.bin/vite');

// The line's name decides the stock (see STOCK/TRA_STOCK/HSR_STOCK in src/world/trains.js), so the
// preview picks a train by naming its line, exactly as an area's data does.
// The TRA's lines take turns between the commuter stock and the express, so reaching the second
// one means laying two lines and looking at the second train.
const PICK = { hsr: ['台灣高鐵', 1], emu900: ['臺鐵縱貫線', 1], emu3000: ['臺鐵縱貫線', 2], tra: ['臺鐵縱貫線', 1] };
const [LINE, LINES] = PICK[stock] ?? [stock, 1];
const SET = LINES - 1;
const TAIWAN = !/[山埼小井銀]/.test(LINE);

const REF_NAME = '.rolling-stock-reference.glb';
const REF_COPY = path.join(WEB, REF_NAME);

const page = `<!doctype html>
<html><head><meta charset="utf-8"><title>rolling stock</title>
<style>html,body{margin:0;background:#9fb4c8}canvas{display:block}</style></head><body>
<script type="module">
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { Trains } from './src/world/trains.js';

const W = 1500, H = 900;
const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setSize(W, H);
renderer.outputColorSpace = THREE.SRGBColorSpace;
// The city view renders ACESFilmic at exposure 1 (src/main.js); judging a white train under a
// linear transfer makes it look like flat paper, so the preview matches the real one.
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x9fb4c8);
// The city view's environment map is switched off for reflections (environment.js installSkyLight),
// so the stand-in is a sky probe plus ground bounce plus one sun, as Environment supplies them.
scene.add(new THREE.HemisphereLight(0xcfe0f2, 0x6a6560, 1.5));
scene.add(new THREE.HemisphereLight(0x000000, 0xb8b2a6, 0.8));
const sun = new THREE.DirectionalLight(0xfff1dc, 3.2);
sun.position.set(-50, 60, 55);
scene.add(sun);

const lines = [];
for (let n = 0; n < ${LINES}; n++) {
  const pts = [];
  for (let i = 0; i <= 40; i++) pts.push(-400 + i * 20, 0, n * 60);   // parallel lines, far enough not to overlap
  lines.push({ name: ${JSON.stringify(LINE)}, railway: 'rail', pts });
}
const trains = new Trains(lines, { taiwan: ${TAIWAN} });
scene.add(trains.group);
await trains.ready;            // the Meshy models, when an area has them, arrive asynchronously
trains.update(20.0, 0);
// car 0's nose sits at x = -400 + SPEED * 20 = -100; the cars run back from there
const set = trains.sets[${SET}] ?? trains.sets[0];
// Reaching the second stock of a rotation means laying a second line, and the first line's train
// would otherwise stand in the background of every shot. Only the stock being looked at is shown.
for (const other of trains.sets) {
  if (other === set) continue;
  for (const m of [other.mesh, other.model?.cabs, other.model?.cars]) if (m) m.visible = false;
}
const LEN = set.stock.length, CARS = set.stock.cars;
const noseX = -100, trackZ = ${SET} * 60, cabCentre = noseX - LEN * 0.5, midCentre = noseX - LEN * 4.5;

function measure() {
  const per = [];
  let total = 0;
  const box = new THREE.Box3();
  const mine = new Set([set.mesh, set.model?.cabs, set.model?.cars].filter(Boolean));
  scene.traverse((o) => {
    if (!o.isInstancedMesh || !mine.has(o)) return;
    const g = o.geometry;
    const tri = (g.index ? g.index.count : g.attributes.position.count) / 3;
    total += tri * o.count;
    g.computeBoundingBox();
    const b = g.boundingBox;
    per.push({ name: o.name || 'cars', count: o.count, trianglesEach: tri,
               size: [b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z].map((v) => +v.toFixed(3)),
               minY: +b.min.y.toFixed(3) });
    box.union(b);
  });
  // The cab car's taper, measured as CROSS-SECTION AREA along its own length, not as width. A bill
  // is deliberately wide right to its tip (the reference photographs show the N700S bill nearly as
  // wide as the body) while being shallow, so a width-only test would push the shape away from the
  // real one. Area catches what the test is for: a swept form whose section barely changes reads as
  // a tube however long it is.
  let taper = null, frontIsNose = null;
  const meshes = [];
  scene.traverse((o) => { if (o.isInstancedMesh && mine.has(o)) meshes.push(o); });
  const cab = meshes[0];
  if (cab) {
    const pos = cab.geometry.attributes.position;
    const zMin = cab.geometry.boundingBox.min.z, zMax = cab.geometry.boundingBox.max.z;
    const slices = 24;
    const halfW = new Array(slices).fill(0), top = new Array(slices).fill(-1e9), bot = new Array(slices).fill(1e9);
    for (let i = 0; i < pos.count; i++) {
      const z = pos.getZ(i), x = Math.abs(pos.getX(i)), y = pos.getY(i);
      const s = Math.min(slices - 1, Math.max(0, Math.floor(((z - zMin) / (zMax - zMin || 1)) * slices)));
      if (x > halfW[s]) halfW[s] = x;
      if (y > top[s]) top[s] = y;
      if (y < bot[s]) bot[s] = y;
    }
    const area = halfW.map((w, s) => (top[s] > bot[s] ? w * (top[s] - bot[s]) : 0)).filter((v) => v > 0);
    taper = +(Math.min(...area) / Math.max(...area)).toFixed(3);
    // +Z is the running direction, so a cab car's small end must be at +Z
    const first = halfW[0] * (top[0] - bot[0]), last = halfW[slices - 1] * (top[slices - 1] - bot[slices - 1]);
    frontIsNose = last < first;
  }
  // What is actually on screen: a Meshy GLB only when one loaded, otherwise the lofted shell of a
  // stock with a nose, otherwise the boxes.
  const drawn = set.model && set.stock.models ? 'Meshy models'
    : set.stock.nose ? 'a shell lofted in code' : 'boxes';
  return { stockLength: LEN, cars: CARS, trianglesPerTrain: total, meshes: per, taper, frontIsNose,
           hasNose: !!set.stock.nose, drawn };
}

// The reference, when there is one: loaded, turned to run along the track, scaled to its real
// length, and set on the same rail so the two can be judged in the same frame.
const REFERENCE = ${JSON.stringify(reference ? REF_NAME : null)}, REF_M = ${referenceMetres};
let refGroup = null;
if (REFERENCE) {
  const gltf = await new GLTFLoader().loadAsync('./' + REFERENCE);
  refGroup = gltf.scene;
  refGroup.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(refGroup);
  const size = box.getSize(new THREE.Vector3()), centre = box.getCenter(new THREE.Vector3());
  const longest = Math.max(size.x, size.y, size.z);
  // turn the model's longest axis onto the track, which runs along x here
  if (size.z === longest) refGroup.rotateY(Math.PI / 2);
  else if (size.y === longest) refGroup.rotateZ(Math.PI / 2);
  refGroup.updateMatrixWorld(true);
  const after = new THREE.Box3().setFromObject(refGroup);
  const k = REF_M > 0 ? REF_M / longest : 1;
  refGroup.scale.multiplyScalar(k);
  refGroup.updateMatrixWorld(true);
  const placed = new THREE.Box3().setFromObject(refGroup);
  refGroup.position.set(noseX - (placed.max.x - placed.getCenter(new THREE.Vector3()).x) - (placed.getCenter(new THREE.Vector3()).x - placed.getCenter(new THREE.Vector3()).x), -placed.min.y, -placed.getCenter(new THREE.Vector3()).z);
  refGroup.position.x = noseX - placed.max.x;
  refGroup.visible = false;
  scene.add(refGroup);
}
window.showReference = (on) => { if (refGroup) { refGroup.visible = on; trains.group.visible = !on; } };

const camera = new THREE.PerspectiveCamera(34, W / H, 0.5, 3000);
const VIEWS = {
  'three-quarter': { pos: [cabCentre + 18, 4.2, trackZ + 15], look: [cabCentre - 8, 2.3, trackZ] },
  'side (cab)': { pos: [cabCentre, 3.0, trackZ + 40], look: [cabCentre, 2.6, trackZ] },
  'head-on': { pos: [noseX + 11, 2.6, trackZ + 1.6], look: [noseX - 2, 2.0, trackZ] },
  'side (intermediate)': { pos: [midCentre, 3.2, trackZ + 26], look: [midCentre, 2.6, trackZ] },
  'whole set': { pos: [cabCentre + 60, 36, trackZ + 100], look: [midCentre - 60, 0, trackZ] },
};
function shoot(name) {
  const v = VIEWS[name];
  camera.position.set(...v.pos);
  camera.lookAt(...v.look);
  renderer.render(scene, camera);
  return renderer.domElement.toDataURL('image/png');
}

// One sheet: every viewpoint, then the same train at night (the saloon lights and the lamps come
// on), then the three-quarter view blurred. The blur is the silhouette check: at the distance the
// city view actually shows a train, that is most of what a player sees.
window.sheet = async () => {
  const shots = [];
  if (refGroup) {
    // one row per view: ours on the left, the reference on the right
    for (const name of Object.keys(VIEWS)) {
      window.showReference(false); shots.push([name, shoot(name)]);
      window.showReference(true); shots.push([name + ' — reference', shoot(name)]);
    }
    window.showReference(false);
  } else {
    for (const name of Object.keys(VIEWS)) shots.push([name, shoot(name)]);
  }
  trains.update(0, 1);
  shots.push(['night', shoot('three-quarter')]);
  shots.push(['silhouette (blurred)', shots[0][1]]);
  const cw = 760, ch = Math.round((760 * H) / W), pad = 26;
  const cols = 2, rows = Math.ceil(shots.length / cols);
  const c = document.createElement('canvas');
  c.width = cols * cw; c.height = rows * (ch + pad);
  const g = c.getContext('2d');
  g.fillStyle = '#f2f3f5'; g.fillRect(0, 0, c.width, c.height);
  for (let i = 0; i < shots.length; i++) {
    const [label, url] = shots[i];
    const img = new Image();
    await new Promise((r) => { img.onload = r; img.src = url; });
    const x = (i % cols) * cw, y = Math.floor(i / cols) * (ch + pad);
    g.save();
    if (label.startsWith('silhouette')) g.filter = 'blur(7px)';
    g.drawImage(img, x, y + pad, cw, ch);
    g.restore();
    g.fillStyle = '#14161c'; g.font = '16px sans-serif';
    g.fillText(label, x + 10, y + 18);
  }
  return c.toDataURL('image/png');
};
// The livery's own picture, as the painter made it. When a train comes out the wrong colour this
// says which half of the problem it is: paint that is wrong in the picture, or paint that is right
// in the picture and sampled from the wrong place by the geometry.
window.atlas = () => {
  const map = set.materials[0].map, c = document.createElement('canvas');
  c.width = map.image.width; c.height = map.image.height;
  c.getContext('2d').drawImage(map.image, 0, 0);
  return c.toDataURL('image/png');
};
window.measure = measure;
window.ready = true;
</script></body></html>`;

function budgetFor(cars) {
  // Measured against the owner's own practice rather than guessed: his near-LOD car shed meshes are
  // about 7,200 triangles a car and his EMU3000 GLB about 16,000, for a map view on the same phones.
  // 3,500 leaves room for the kit that makes a train read as one — roof units, bogies with wheels,
  // door recesses — while staying half his lightest and well under what a city block costs.
  return cars * 3500;
}

(async () => {
  if (!fs.existsSync(VITE)) {
    console.error(`no vite in ${WEB}/node_modules — run: (cd Web/CityView && npm ci)`);
    process.exit(2);
  }
  fs.writeFileSync(PAGE, page);
  if (reference) {
    if (!fs.existsSync(reference)) { console.error(`no reference model at ${reference}`); process.exit(2); }
    fs.copyFileSync(reference, REF_COPY);   // vite only serves what is under its root
  }
  const server = spawn(VITE, ['--port', String(port), '--strictPort'], { cwd: WEB, stdio: 'ignore' });
  let browser = null;
  try {
    const url = `http://localhost:${port}/${path.basename(PAGE)}`;
    browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader', '--use-gl=swiftshader'] });
    const tab = await browser.newPage({ viewport: { width: 1500, height: 900 } });
    const problems = [];
    tab.on('pageerror', (e) => problems.push(String(e)));
    tab.on('console', (m) => { if (m.type() === 'error') problems.push(m.text()); });
    for (let i = 0; i < 40; i++) {
      try { await tab.goto(url, { waitUntil: 'load', timeout: 3000 }); break; } catch { await new Promise((r) => setTimeout(r, 500)); }
    }
    await tab.waitForFunction('window.ready === true', { timeout: 90000 });

    const m = await tab.evaluate(() => window.measure());
    const budget = budgetFor(m.cars);
    const gates = [
      ['the page built the train without errors', problems.length === 0, problems.join(' | ')],
      [`a whole set fits its budget (${m.trianglesPerTrain} triangles, budget ${budget})`,
       m.trianglesPerTrain <= budget, `${m.trianglesPerTrain} > ${budget}`],
      ['nothing hangs below the rail', m.meshes.every((x) => x.minY >= -0.01),
       m.meshes.filter((x) => x.minY < -0.01).map((x) => `${x.name} minY ${x.minY}`).join(', ')],
      ['every car is about as long as its stock says', m.meshes.every((x) => Math.abs(x.size[2] - m.stockLength) < m.stockLength * 0.2),
       m.meshes.map((x) => `${x.name} ${x.size[2]}m vs ${m.stockLength}m`).join(', ')],
      ['no car is wider than the loading gauge', m.meshes.every((x) => x.size[0] <= 3.2),
       m.meshes.filter((x) => x.size[0] > 3.2).map((x) => `${x.name} ${x.size[0]}m`).join(', ')],
    ];
    if (m.taper !== null && m.hasNose) {   // only a stock whose cab cars have a nose
      // img2threejs's lesson, worth keeping: a swept nose whose narrowest section is more than
      // about half its widest reads as a constant-width tube, not as a nose.
      gates.push([`the cab car tapers (smallest/largest section ${m.taper})`, m.taper <= 0.6, `${m.taper} > 0.6`]);
      gates.push(['the small end faces the running direction (+Z)', m.frontIsNose === true, 'the large end is at +Z']);
    }
    let failed = 0;
    for (const [name, ok, detail] of gates) {
      console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok ? '' : ` — ${detail}`}`);
      if (!ok) failed++;
    }
    console.log(`\n${m.cars} cars of ${m.stockLength} m; ${m.drawn}`);
    for (const x of m.meshes) console.log(`  ${x.name}: ${x.count} x ${x.trianglesEach} triangles, ${x.size.join(' x ')} m`);

    if (atlas) {
      const data = await tab.evaluate(() => window.atlas());
      fs.mkdirSync(path.dirname(path.resolve(atlas)), { recursive: true });
      fs.writeFileSync(path.resolve(atlas), Buffer.from(data.split(',')[1], 'base64'));
      console.log(`livery: ${path.resolve(atlas)}`);
    }
    if (!checkOnly) {
      const data = await tab.evaluate(() => window.sheet());
      fs.mkdirSync(path.dirname(path.resolve(out)), { recursive: true });
      fs.writeFileSync(path.resolve(out), Buffer.from(data.split(',')[1], 'base64'));
      console.log(`\nsheet: ${path.resolve(out)}`);
    }
    process.exitCode = failed ? 1 : 0;
  } finally {
    if (browser) await browser.close();
    server.kill();
    fs.rmSync(PAGE, { force: true });
    fs.rmSync(REF_COPY, { force: true });
  }
})();
