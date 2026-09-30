import { execFileSync } from 'node:child_process';
import { mkdir, copyFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
process.chdir(here);
const swift = process.env.SWIFT || 'swift';
const sdk = 'swift-6.4.0-RELEASE_wasm';
const version = execFileSync(swift, ['--version'], { encoding: 'utf8' });
if (!/Swift version 6\.4(?:\.0)?\s/.test(version)) throw new Error(`Requires Swift 6.4.0: ${version}`);
const sdkList = execFileSync(swift, ['sdk', 'list'], { encoding: 'utf8' });
if (!sdkList.split(/\r?\n/).includes(sdk)) throw new Error(`Install the matching ${sdk} SDK (see README)`);
execFileSync(process.execPath, ['prepare.mjs'], { stdio: 'inherit' });
await mkdir('.artifacts', { recursive: true });
const flags = ['--product', 'RailwayWasmProbe', '-c', 'release', '-Xswiftc', '-warnings-as-errors'];
for (const target of ['native', 'wasm']) {
  const options = ['--scratch-path', `.build/${target}`, ...(target === 'wasm' ? ['--swift-sdk', sdk] : [])];
  execFileSync(swift, ['build', ...options, ...flags], { stdio: 'inherit' });
  const bin = execFileSync(swift, ['build', ...options, '-c', 'release', '--show-bin-path'], { encoding: 'utf8' }).trim();
  if (target === 'native') {
    const report = execFileSync(path.join(bin, 'RailwayWasmProbe'), [], { encoding: 'utf8' });
    JSON.parse(report); // Fail if the executable did not emit one JSON report.
    await writeFile('.artifacts/native.json', report);
  } else {
    await copyFile(path.join(bin, 'RailwayWasmProbe.wasm'), '.artifacts/probe.wasm');
  }
}
await writeFile('.artifacts/toolchain.txt', `${version}\nSDK: ${sdk}\n`);
console.log('Built native report and Wasm executable in .artifacts/');
