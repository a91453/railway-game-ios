#!/usr/bin/env node
// Fixed Web/CityView captures and synchronous frame timings. Uses the preinstalled Playwright.
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { chromium } = require('playwright');

const WEB = path.resolve(__dirname, '../../Web/CityView');
const VITE = path.join(WEB, 'node_modules/.bin/vite');
const VIEWS = [
  { id: 'station-day', area: 'kaohsiung', camera: [0, 0, 420, 200, 32], hour: 12, radius: 400 },
  { id: 'station-night', area: 'kaohsiung', camera: [0, 0, 420, 200, 32], hour: 22, radius: 400 },
  { id: 'district-day', area: 'kaohsiung', camera: [320, -180, 540, 245, 35], hour: 12, radius: 400 },
];
const FIXED_DATE = '2026-10-15T04:00:00.000Z';
const VARIANT = { abstract: false, landmarks: true, windows: true, contact: false, relief: true };

function options() {
  const args = process.argv.slice(2), result = { out: null, camera: null, frames: 30, warmup: 8, port: 5288 };
  for (let i = 0; i < args.length; i += 2) {
    const key = args[i].slice(2);
    if (!args[i].startsWith('--') || !(key in result) || !args[i + 1]) throw new Error(`Unknown or incomplete option: ${args[i]}`);
    result[key] = args[i + 1];
  }
  for (const key of ['frames', 'warmup', 'port']) {
    result[key] = Number(result[key]);
    if (!Number.isInteger(result[key]) || result[key] < (key === 'warmup' ? 0 : 1)) throw new Error(`--${key} must be a positive integer`);
  }
  if (result.frames < 2 || result.port > 65535) throw new Error('Need at least two frames and a valid port');
  if (!result.out) throw new Error('Usage: NODE_PATH=<preinstalled Playwright path> node tools/cityview-benchmark/capture.cjs --out <directory> [--camera <id>] [--frames 30] [--warmup 8] [--port 5288]');
  if (result.camera && !VIEWS.some((v) => v.id === result.camera)) throw new Error(`Unknown camera ${result.camera}; choose ${VIEWS.map((v) => v.id).join(', ')}`);
  return result;
}

function percentile(values, p) {
  const sorted = [...values].sort((a, b) => a - b);
  const position = (sorted.length - 1) * p;
  const lo = Math.floor(position), hi = Math.ceil(position);
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (position - lo);
}

const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function serverReady(port, child) {
  for (let i = 0; i < 100; i++) {
    if (child.exitCode !== null) throw new Error(`Vite exited: ${child.exitCode}`);
    try { if ((await fetch(`http://127.0.0.1:${port}/`)).ok) return; } catch { /* starting */ }
    await pause(100);
  }
  throw new Error('Vite did not start within 10 seconds');
}

async function capture(context, port, view, frames, warmup, out) {
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('response', (response) => { if (response.status() >= 400) errors.push(`${response.status()} ${response.url()}`); });
  await page.addInitScript(() => {
    // Let loading use animation frames; once ready, drop the queued frame and drive tick() ourselves.
    const native = window.requestAnimationFrame.bind(window);
    window.requestAnimationFrame = (fn) => native((time) => { if (!window.__capturePaused) fn(time); });
  });
  const query = new URLSearchParams({
    area: view.area, cam: view.camera.join(','), time: String(view.hour), radius: String(view.radius),
    traffic: '0', birds: '0', cars: '0', clouds: '0', ortho: '0', preview: '0',
    abstract: '0', landmarks: '1', windows: '1', relief: '1', contact: '0',
  });
  try {
    await page.goto(`http://127.0.0.1:${port}/?${query}`, { waitUntil: 'load', timeout: 30000 });
    await page.waitForFunction(() => window.__app?.renderer && document.querySelector('canvas'), { timeout: 90000 });
    await page.evaluate(({ date, hour, variant }) => {
      window.__capturePaused = true;
      Date.now = () => new Date(date).getTime();
      const app = window.__app;
      Object.assign(app.clockTime, { live: false, play: false, hour });
      app.setVariant(variant);
    }, { date: FIXED_DATE, hour: view.hour, variant: VARIANT });
    await pause(100); // let the last scheduled animation frame be discarded
    // Tile workers and texture uploads are asynchronous. Fail instead of measuring a half loaded city.
    let settled = false;
    for (let i = 0; i < 300; i++) {
      const state = await page.evaluate(() => {
        const app = window.__app, streamer = app.streamer, size = streamer.manifest.tileSize;
        app.tick();
        const wanted = streamer.manifest.tiles.filter((t) =>
          Math.hypot((t.x + 0.5) * size - app.controls.target.x,
            (t.z + 0.5) * size - app.controls.target.z) <= streamer.radius).length;
        return { wanted, loaded: streamer.stats.loaded, pending: streamer.pending,
          failed: [...streamer.tiles.values()].filter((t) => t.state === 'failed').length };
      });
      if (state.failed) throw new Error(`${view.id}: ${state.failed} city tiles failed to load`);
      if (state.wanted > 0 && state.loaded === state.wanted && state.pending === 0) { settled = true; break; }
      await pause(100);
    }
    if (!settled) throw new Error(`${view.id}: city tiles did not settle within 30 seconds`);
    if (errors.length) throw new Error(`${view.id}: page errors: ${errors.join(' | ')}`);
    for (let i = 0; i < warmup; i++) await page.evaluate(() => window.__app.tick());
    const samples = await page.evaluate((count) => {
      const app = window.__app, gl = app.renderer.getContext(), values = [];
      for (let i = 0; i < count; i++) {
        const start = performance.now();
        app.tick();
        gl.finish();
        const ms = performance.now() - start, info = app.renderer.info.render;
        values.push({ ms, drawCalls: info.calls, triangles: info.triangles });
      }
      return values;
    }, frames);
    const calls = new Set(samples.map((s) => s.drawCalls));
    const triangles = new Set(samples.map((s) => s.triangles));
    if (calls.size !== 1 || triangles.size !== 1 || !samples[0].drawCalls || !samples[0].triangles)
      throw new Error(`${view.id}: render counts changed during sampling or scene was empty`);
    const png = `${view.id}.png`;
    await page.addStyleTag({ content: 'body > :not(canvas) { visibility: hidden !important; }' });
    await page.locator('canvas').first().screenshot({ path: path.join(out, png), animations: 'disabled' });
    const ms = samples.map((s) => s.ms);
    return { id: view.id, png, area: view.area, camera: view.camera, hour: view.hour,
      drawCalls: samples[0].drawCalls, triangles: samples[0].triangles,
      frameMs: { median: percentile(ms, 0.5), p95: percentile(ms, 0.95) } };
  } finally { await page.close(); }
}

(async () => {
  const opt = options();
  if (!fs.existsSync(VITE)) throw new Error('Run npm ci in Web/CityView first');
  if (!fs.existsSync(path.join(WEB, 'public/tiles/kaohsiung/manifest.json')))
    throw new Error('Missing compiled city tiles; see tools/procedural-city/README.md');
  fs.mkdirSync(opt.out, { recursive: true });
  const out = path.resolve(opt.out);
  const server = spawn(VITE, ['--host', '127.0.0.1', '--port', String(opt.port), '--strictPort'], { cwd: WEB, stdio: 'ignore' });
  let browser;
  try {
    await serverReady(opt.port, server);
    const executablePath = process.env.CHROMIUM_PATH || ['/usr/bin/chromium', chromium.executablePath()].find(fs.existsSync);
    if (!executablePath) throw new Error('No preinstalled Chromium found; set CHROMIUM_PATH to its executable');
    browser = await chromium.launch({ executablePath, headless: true,
      args: ['--enable-unsafe-swiftshader', '--use-gl=swiftshader'] });
    const context = await browser.newContext({ viewport: { width: 960, height: 540 }, deviceScaleFactor: 1 });
    const views = [];
    for (const view of VIEWS.filter((v) => !opt.camera || v.id === opt.camera)) {
      const result = await capture(context, opt.port, view, opt.frames, opt.warmup, out);
      views.push(result);
      console.log(`${result.id}: ${result.drawCalls} draws, ${result.triangles} triangles, ${result.frameMs.median.toFixed(2)} ms median, ${result.frameMs.p95.toFixed(2)} ms p95`);
    }
    fs.writeFileSync(path.join(out, 'measurements.json'), JSON.stringify({
      schemaVersion: 1, source: 'Web/CityView (Three.js/WebGL)', platform: process.platform,
      chromium: browser.version(), viewport: { width: 960, height: 540, deviceScaleFactor: 1 },
      fixedDate: FIXED_DATE, variant: VARIANT, settings: { traffic: false, birds: 0, clouds: 0, ortho: false, preview: false },
      frames: opt.frames, warmup: opt.warmup, timing: 'app.tick() + gl.finish(), no requestAnimationFrame/vsync',
      views,
    }, null, 2) + '\n');
  } finally {
    if (browser) await browser.close();
    server.kill();
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
