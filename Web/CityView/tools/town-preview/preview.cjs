#!/usr/bin/env node
/**
 * Web/CityView/tools/town-preview/preview.cjs
 *
 * Boots the existing CityView Vite server and drives headless Chrome via CDP
 * (using Node's built-in WebSocket — zero additional npm dependencies) to
 * render the 5 required comparison screenshots into the directory given as
 * its argument:
 *   node Web/CityView/tools/town-preview/preview.cjs <output directory>
 * The 2026-10-17 run is in a91453/railway-reference-private:
 * Railway/game-art-previews/docs/art/town-scene-preview-2026-10-17/; this
 * repository keeps only its README and one overview
 * (docs/HANDOFF.md §2), so do not write the screenshots back into docs/art.
 */

const fs = require('fs');
const path = require('path');
const http = require('http');
const { spawn } = require('child_process');

const cityViewDir = path.resolve(__dirname, '../..');
if (!process.argv[2]) {
  console.error('Usage: node Web/CityView/tools/town-preview/preview.cjs <output directory>');
  process.exit(2);
}
const outDir = path.resolve(process.argv[2]);

const SHOTS = [
  { file: 'a-kenney-sunny.png',  mode: 'A', view: 'overview', desc: 'A 照 Kenney 原樣（同一視角・晴）' },
  { file: 'b-taiwan-sunny.png',  mode: 'B', view: 'overview', desc: 'B 配成台灣版（同一視角・晴）' },
  { file: 'c-taiwan-rain.png',   mode: 'C', view: 'overview', desc: 'C 台灣版＋午後雷陣雨（同一視角・weather.js rain）' },
  { file: 'd-taiwan-closeup.png', mode: 'B', view: 'close',    desc: '拉近特寫（看得到人的臉與車的細節）' },
  { file: 'e-taiwan-mid.png',    mode: 'B', view: 'mid',      desc: '中距離視角（遊戲 3D 地圖拉近高度）' },
];

function findChromeBinary() {
  const candidates = [
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    'google-chrome',
    'chromium',
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  throw new Error('Could not find Chrome/Edge executable for headless rendering.');
}

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

class CDPClient {
  constructor(wsUrl) {
    this.wsUrl = wsUrl;
    this.nextId = 1;
    this.pending = new Map();
  }
  async connect() {
    this.ws = new WebSocket(this.wsUrl);
    await new Promise((resolve, reject) => {
      this.ws.addEventListener('open', resolve, { once: true });
      this.ws.addEventListener('error', reject, { once: true });
    });
    this.ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        if (msg.error) reject(new Error(JSON.stringify(msg.error)));
        else resolve(msg.result);
      }
    });
  }
  send(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }
  async eval(expression) {
    const res = await this.send('Runtime.evaluate', {
      expression,
      awaitPromise: true,
      returnByValue: true,
    });
    if (res.exceptionDetails) {
      throw new Error('Page evaluation error: ' + JSON.stringify(res.exceptionDetails));
    }
    return res.result ? res.result.value : undefined;
  }
  close() {
    if (this.ws) this.ws.close();
  }
}

async function main() {
  fs.mkdirSync(outDir, { recursive: true });

  // 1. Start Vite server from Web/CityView
  const vitePath = require.resolve('vite', { paths: [cityViewDir] });
  const { createServer } = require(vitePath);
  const server = await createServer({
    root: cityViewDir,
    logLevel: 'silent',
    server: { port: 0, host: '127.0.0.1' },
  });
  await server.listen();
  const port = server.httpServer.address().port;
  const baseUrl = `http://127.0.0.1:${port}/tools/town-preview/index.html`;
  console.log(`Vite server listening at ${baseUrl}`);

  // 2. Launch headless Chrome with remote debugging port
  const os = require('os');
  const debugPort = 9345;
  const userDataDir = path.join(os.tmpdir(), 'town-preview-chrome-' + Date.now());
  const chromeBin = findChromeBinary();
  const chromeProc = spawn(
    chromeBin,
    [
      '--headless=new',
      `--remote-debugging-port=${debugPort}`,
      `--user-data-dir=${userDataDir}`,
      '--window-size=1440,900',
      '--force-device-scale-factor=1',
      '--enable-webgl',
      '--ignore-gpu-blocklist',
      '--use-angle=d3d11',
      '--no-first-run',
      '--no-default-browser-check',
      baseUrl,
    ],
    { stdio: 'ignore' }
  );

  try {
    // Wait for DevTools endpoint
    let pageTarget = null;
    for (let retry = 0; retry < 40; retry++) {
      try {
        const list = await fetchJson(`http://127.0.0.1:${debugPort}/json/list`);
        pageTarget = list.find((t) => t.type === 'page' && t.url.includes('town-preview'));
        if (pageTarget) break;
      } catch (_) {}
      await new Promise((r) => setTimeout(r, 250));
    }
    if (!pageTarget) throw new Error('Timed out waiting for Chrome DevTools target.');

    const cdp = new CDPClient(pageTarget.webSocketDebuggerUrl);
    await cdp.connect();
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: 1440,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false,
    });

    // Wait for initial scene load
    for (let i = 0; i < 60; i++) {
      const ready = await cdp.eval('Boolean(window.__TOWN_PREVIEW_READY__)');
      if (ready) break;
      await new Promise((r) => setTimeout(r, 250));
    }

    const summaryStats = [];
    for (const shot of SHOTS) {
      const stats = await cdp.eval(`window.setPreviewState(${JSON.stringify(shot.mode)}, ${JSON.stringify(shot.view)})`);
      // Give WebGL + canvas textures 250ms to settle
      await new Promise((r) => setTimeout(r, 250));
      await cdp.eval(`new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))`);

      const { data } = await cdp.send('Page.captureScreenshot', { format: 'png' });
      const outPath = path.join(outDir, shot.file);
      fs.writeFileSync(outPath, Buffer.from(data, 'base64'));
      console.log(`Saved ${shot.file} -> totalTris=${stats.totalTriangles}`);
      summaryStats.push({ file: shot.file, desc: shot.desc, ...stats });
    }

    fs.writeFileSync(path.join(outDir, 'stats.json'), JSON.stringify(summaryStats, null, 2) + '\n');
    cdp.close();
  } finally {
    chromeProc.kill();
    await server.close();
    try {
      fs.rmSync(userDataDir, { recursive: true, force: true });
    } catch (_) {}
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
