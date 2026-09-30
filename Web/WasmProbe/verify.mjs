import assert from 'node:assert/strict';
import { readFile, writeFile, readdir } from 'node:fs/promises';
import { openSync, closeSync } from 'node:fs';
import { WASI } from 'node:wasi';
import { chromium, firefox, webkit } from 'playwright';
import { startServer } from './serve.mjs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

process.chdir(path.dirname(fileURLToPath(import.meta.url)));
const native = JSON.parse(await readFile('.artifacts/native.json', 'utf8'));
const fixtureNames = (await readdir('../../GoldenScenarios')).filter(name => name.endsWith('.json')).sort();
const expectedChecks = ['failure-atomicity', 'ticks-and-s4-snapshot', 'full-width-and-overflow', 'codable-large-integer', 'clock-overflow-atomicity', 'golden-oracle-mutation'];
function validate(report, bits) {
  assert.equal(report.protocolVersion, 1);
  assert.equal(report.intBits, bits);
  assert.equal(report.intMax, bits === 32 ? '2147483647' : '9223372036854775807');
  assert.deepEqual(report.checks, expectedChecks);
  assert.deepEqual(report.goldenScenarios, fixtureNames);
  assert.equal(report.largeBalance, '9007199254735693');
}
validate(native, 64);
// Run the same binary with Node's WASI implementation, independently of the browser shim.
const stdout = openSync('.artifacts/node.json', 'w');
const stderr = openSync('.artifacts/node-stderr.txt', 'w');
try {
  const wasi = new WASI({ version: 'preview1', args: ['RailwayWasmProbe'], env: {}, preopens: {}, stdout, stderr, returnOnExit: true });
  const module = await WebAssembly.compile(await readFile('.artifacts/probe.wasm'));
  const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
  assert.equal(wasi.start(instance), 0);
} finally {
  closeSync(stdout);
  closeSync(stderr);
}
const node = JSON.parse(await readFile('.artifacts/node.json', 'utf8'));
validate(node, 32);
const { intBits, intMax, ...nativeBehavior } = native;
const { intBits: wasmBits, intMax: wasmMax, ...wasmBehavior } = node;
assert.deepEqual(wasmBehavior, nativeBehavior);
const server = await startServer(0);
try {
  const types = { chromium, firefox, webkit };
  for (const name of (process.env.PROBE_BROWSERS || 'chromium').split(',')) {
    assert.ok(types[name], `Unknown browser: ${name}`);
    const browser = await types[name].launch({
      headless: true,
      ...(name === 'chromium' && process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}),
    });
    try {
      const context = await browser.newContext();
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.goto(`http://127.0.0.1:${server.address().port}/`);
      await page.waitForFunction(() => window.probeResult !== undefined, null, { timeout: 65_000 });
      const result = await page.evaluate(() => window.probeResult);
      await writeFile(`.artifacts/${name}.json`, `${JSON.stringify(result, null, 2)}\n`);
      assert.deepEqual(errors, []);
      assert.equal(result.ok, true, JSON.stringify(result));
      validate(result.report, 32);
      assert.deepEqual(result.report, node);
      // A failed Wasm load must be reported as a failure, never a passing probe.
      await context.route('**/.artifacts/probe.wasm', route => route.fulfill({ status: 503, body: 'Unavailable' }));
      await page.reload();
      await page.waitForFunction(() => window.probeResult !== undefined, null, { timeout: 65_000 });
      const failedLoad = await page.evaluate(() => window.probeResult);
      assert.equal(failedLoad.ok, false);
      assert.match(failedLoad.error, /Wasm fetch failed: 503/);
      await writeFile(`.artifacts/${name}-error-path.json`, `${JSON.stringify(failedLoad, null, 2)}\n`);
      console.log(`VERIFIED ${name}: Worker + WASI, ${fixtureNames.length} golden scenarios, ${expectedChecks.length} checks`);
    } finally {
      await browser.close();
    }
  }
} finally {
  await new Promise(resolve => server.close(resolve));
}
console.log('VERIFIED native / Wasm behavior matches for this probe; Int width differs (64 / 32).');
