// Seven views of each model in a run directory (export.swift's OUT), lit as
// the game lights a model: node render.mjs OUT [--time day|night|both]
// [--ids a,b] [--views top,left,...] [--line #2F6DB5] [--features N]
// Writes OUT/png/<time>/<id>-<view>.png. Needs playwright (global
// node_modules, or NODE_GLOBAL) and Chromium (CHROMIUM_PATH, default the
// pre-installed one); the WebGL is software, so it runs on Linux.
import {createServer} from 'node:http';
import {readFileSync, writeFileSync, mkdirSync, copyFileSync} from 'node:fs';
import {resolve, extname} from 'node:path';
import {createRequire} from 'node:module';
const argv = process.argv.slice(2);
const flag = (name, fallback) => { const at = argv.indexOf(name); return at >= 0 ? argv[at + 1] : fallback; };
const root = resolve(argv[0]);
const times = flag('--time', 'day') === 'both' ? ['day', 'night'] : [flag('--time', 'day')];
const views = flag('--views', 'top,bottom,left,right,front,back,isometric').split(',');
const features = Number(flag('--features', 0));
const hex = flag('--line', '#2F6DB5'), line = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255);
const {chromium} = createRequire(process.env.NODE_GLOBAL || '/opt/node22/lib/node_modules/')('playwright');
const manifest = JSON.parse(readFileSync(resolve(root, 'manifest.json')));
const only = flag('--ids', '') ? new Set(flag('--ids').split(',')) : null;
copyFileSync(new URL('./renderer.js', import.meta.url).pathname, resolve(root, 'renderer.js'));
writeFileSync(resolve(root, '_r.html'), `<canvas id="c"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.make=l=>{window.r=new NativeRenderer(document.getElementById("c"),l);};window.ready=true;</script>`);
const server = createServer((q, s) => { try { const p = resolve(root, '.' + decodeURIComponent(new URL(q.url, 'http://x').pathname)); s.setHeader('Content-Type', ({'.html': 'text/html', '.js': 'text/javascript'})[extname(p)] || 'application/octet-stream'); s.end(readFileSync(p)); } catch { s.writeHead(404); s.end(); } });
await new Promise(r => server.listen(0, '127.0.0.1', r));
const base = 'http://127.0.0.1:' + server.address().port;
const browser = await chromium.launch({executablePath: process.env.CHROMIUM_PATH || '/opt/pw-browsers/chromium-1243/chrome-linux64/chrome', args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']});
const page = await browser.newPage({viewport: {width: 1400, height: 900}});
await page.goto(base + '/_r.html'); await page.waitForFunction(() => window.ready);
await page.evaluate(l => window.make(l), manifest.lighting);
let count = 0;
for (const time of times) {
  mkdirSync(resolve(root, 'png', time), {recursive: true});
  for (const m of manifest.models.filter(m => !only || only.has(m.id))) {
    const shots = await page.evaluate(async ({native, views, time, line, features}) => {
      r.load(await (await fetch(native)).arrayBuffer()); const out = {};
      for (const v of views) { r.render(v, {width: v === 'front' || v === 'back' ? 600 : 1200, height: v === 'top' || v === 'bottom' ? 300 : 420, time, lineColour: line, features}); out[v] = r.png(); }
      return out;
    }, {native: m.native, views, time, line, features});
    for (const [v, data] of Object.entries(shots)) writeFileSync(resolve(root, 'png', time, `${m.id}-${v}.png`), Buffer.from(data.split(',')[1], 'base64'));
    count++;
  }
}
await browser.close(); server.close();
console.log(`rendered ${count} models x ${views.length} views x ${times.length} light(s)`);
