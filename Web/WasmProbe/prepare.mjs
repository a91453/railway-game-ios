// Reuse the committed runner and fixtures verbatim; never duplicate or rewrite expectations.
import { mkdir, readFile, writeFile, copyFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const generated = path.join(here, 'Generated');
await mkdir(generated, { recursive: true });
await copyFile(path.join(root, 'Tests/GameCoreTests/GoldenScenario.swift'), path.join(generated, 'GoldenScenario.swift'));
// The runner uses public enum ID helpers from NetworkSupport; its invariant
// campaigns depend on ReferenceWorld and are not part of this executable.
const support = await readFile(path.join(root, 'Tests/GameCoreTests/NetworkSupport.swift'), 'utf8');
const boundary = support.indexOf('enum NetworkInvariants {');
if (boundary < 0) throw new Error('NetworkSupport helper boundary changed');
await writeFile(path.join(generated, 'GoldenIDSupport.swift'), support.slice(0, boundary));
await copyFile(path.join(here, 'Probe.swift'), path.join(generated, 'Probe.swift'));
const fixtures = (await readdir(path.join(root, 'GoldenScenarios'))).filter(name => name.endsWith('.json')).sort();
if (!fixtures.length) throw new Error('No golden scenarios found');
const entries = [];
for (const name of fixtures) {
  const raw = await readFile(path.join(root, 'GoldenScenarios', name), 'utf8');
  // Swift raw multiline literals preserve JSON escapes and integer literals.
  if (raw.includes('"""#') || raw.includes('\\#(')) throw new Error(`Unsafe Swift literal: ${name}`);
  entries.push(`(${JSON.stringify(name)}, #"""\n${raw.trimEnd()}\n"""#)`);
}
await writeFile(path.join(generated, 'Fixtures.swift'), `let embeddedFixtures: [(String, String)] = [\n${entries.join(',\n')}\n]\n`);
console.log(`Prepared ${fixtures.length} golden scenarios from repository sources`);
