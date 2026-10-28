// Decision 467: the Khronos glTF Validator (npm `gltf-validator`,
// Apache-2.0, pinned in package.json) over the repository's GLB and glTF
// files, or the ones named. A file with an error fails the run, but the
// errors `known.json` lists for it (third-party sources kept as they came,
// a fixture made to lack something); warnings and notes are counted, not
// failed.
//
// usage (repository root, Node 22, `npm ci --ignore-scripts` done here):
//   node tools/gltf-validate/validate.mjs [file.glb ...]
import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import validator from 'gltf-validator';

const known = JSON.parse(await readFile(new URL('./known.json', import.meta.url), 'utf8')).files;

const root = fileURLToPath(new URL('../..', import.meta.url));
const named = process.argv.slice(2);
const files = named.length > 0 ? named.map(f => resolve(f))
  : execFileSync('git', ['-C', root, 'ls-files', '*.glb', '*.gltf'], { encoding: 'utf8' }).split('\n').filter(Boolean).map(f => join(root, f));

const started = Date.now();
let failed = 0;
for (const file of files) {
  const report = await validator.validateBytes(new Uint8Array(await readFile(file)), {
    uri: file,
    maxIssues: 100,
    // A .gltf's buffers and images, beside it.
    externalResourceFunction: uri => readFile(join(dirname(file), decodeURIComponent(uri))).then(b => new Uint8Array(b)),
  });
  const { numErrors, numWarnings, numInfos } = report.issues;
  const name = file.startsWith(root) ? file.slice(root.length) : file;
  const allowed = new Set(known[name]?.errors ?? []);
  const errors = report.issues.messages.filter(m => m.severity === 0 && !allowed.has(m.code));
  const label = errors.length > 0 ? 'FAIL' : numErrors > 0 ? 'known' : 'ok';
  process.stdout.write(`${label.padEnd(5)} ${name}: ${numErrors} errors, ${numWarnings} warnings, ${numInfos} notes\n`);
  if (errors.length > 0) {
    failed += 1;
    for (const issue of errors) process.stdout.write(`       ${issue.code} ${issue.pointer ?? ''} ${issue.message}\n`);
  }
}
process.stdout.write(`${files.length} files, ${failed} with errors, ${((Date.now() - started) / 1000).toFixed(1)} s\n`);
if (failed > 0) process.exit(1);
