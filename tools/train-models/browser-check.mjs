// node browser-check.mjs RUN [INSPECTOR.html]
// Validate the final embedded inspector, not the static comparison gallery.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
const args = process.argv.slice(2), root = resolve(args[0]);
const reportAt = args.indexOf('--report-dir');
const reportDir = resolve(reportAt >= 0 ? args[reportAt + 1] : root);
const file = resolve(args[1] && !args[1].startsWith('--') ? args[1] : resolve(root, 'index.html'));
mkdirSync(reportDir, {recursive: true});
const manifest = JSON.parse(readFileSync(resolve(root, 'manifest.json')));
const {chromium} = createRequire(process.env.NODE_GLOBAL || '/opt/node22/lib/node_modules/')('playwright');
const server = createServer((q, s) => { s.setHeader('Content-Type', 'text/html'); s.end(readFileSync(file)); });
await new Promise(r => server.listen(0, '127.0.0.1', r));
let browser;
const errors = [], requests = [], rows = [];
try {
  browser = await chromium.launch({executablePath: process.env.CHROMIUM_PATH || '/opt/pw-browsers/chromium-1243/chrome-linux64/chrome', args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']});
  const page = await browser.newPage({viewport: {width: 1200, height: 900}, acceptDownloads: true});
  page.on('pageerror', e => errors.push(e.message));
  page.on('request', q => requests.push(q.url()));
  const base = `http://127.0.0.1:${server.address().port}`;
  await page.goto(base); await page.waitForFunction(() => window.inspectorReady);
  assert.equal(await page.locator('#model option').count(), manifest.models.length);
  for (const m of manifest.models) {
    await page.selectOption('#model', m.id);
    for (const view of ['top', 'bottom', 'left', 'right', 'front', 'back', 'isometric']) {
      await page.selectOption('#view', view);
      for (const time of ['day', 'night']) {
        await page.selectOption('#time', time);
        assert(await page.evaluate(() => r.count > 0 && r.gl.getError() === 0));
      }
    }
    for (const kind of ['native', 'glb']) {
      const waiting = page.waitForEvent('download');
      await page.locator('#downloads a').filter({hasText: new RegExp(`^${kind}$`)}).click();
      const download = await waiting;
      assert.deepEqual(readFileSync(await download.path()), readFileSync(resolve(root, m[kind])), `${m.id}: downloaded ${kind}`);
    }
    const waiting = page.waitForEvent('download'); await page.locator('#downloads a').filter({hasText: /^PNG$/}).click();
    const png = readFileSync(await (await waiting).path());
    assert.equal(png.subarray(0,8).toString('hex'), '89504e470d0a1a0a');
    rows.push({id: m.id, views: 7, lights: 2, native_glb_download_bytes: true, png_download: true});
  }
  const before = await page.evaluate(() => r.png());
  const box = await page.locator('canvas').boundingBox();
  await page.mouse.move(box.x+box.width/2,box.y+box.height/2);await page.mouse.down();await page.mouse.move(box.x+box.width/2+75,box.y+box.height/2+25);await page.mouse.up();
  assert.notEqual(await page.evaluate(() => r.png()), before, 'orbit did not change pixels');
  const rotated = await page.evaluate(() => r.png());await page.click('#in');
  assert.notEqual(await page.evaluate(() => r.png()), rotated, 'zoom did not change pixels');
  await page.setViewportSize({width: 390, height: 844});
  assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'mobile horizontal overflow');
  await page.screenshot({path: resolve(reportDir, 'inspector-mobile.png')});
  // The file protocol is a separate check; localhost success alone is insufficient.
  let fileProtocol;
  try {
    await page.goto(pathToFileURL(file).href);await page.waitForFunction(() => window.inspectorReady);
    assert(await page.evaluate(() => r.count > 0 && r.gl.getError() === 0));
    fileProtocol = {status: 'VERIFIED'};
  } catch (error) {
    if (!String(error).includes('ERR_BLOCKED_BY_ADMINISTRATOR')) throw error;
    fileProtocol = {status: 'UNVERIFIED', reason: 'Browser administration blocks file:// navigation; loopback checks passed.'};
  }
  assert.deepEqual(errors, []);
  assert(requests.every(u => u.startsWith(base) || u.startsWith('data:') || u.startsWith('file:')), 'external request');
  writeFileSync(resolve(reportDir, 'browser-verification.json'), JSON.stringify({status: 'VERIFIED', transport: 'loopback HTTP', models: rows, orbit_zoom_changed_pixels: true, mobile_width: 390, file_protocol: fileProtocol, errors, external_requests: 0, limits: ['Browser WebGL only; no device Metal, animation or appearance acceptance.']}, null, 2)+'\n');
  console.log(`VERIFIED ${rows.length} inspector models, downloads, orbit/zoom and mobile; file protocol ${fileProtocol.status}`);
} finally { if (browser) await browser.close(); server.close(); }
