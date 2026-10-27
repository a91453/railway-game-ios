// Budget and hash checks for a run directory (export.swift's OUT):
//   node check.mjs OUT [--lock hashes.lock.json] [--allow id,id] [--new-set key,key]
//   node check.mjs OUT --grandfather-write   (rewrites budgets.json's list from this run; once, with main's models)
// Fails (exit 1) when
//  - a near car has more triangles than budgets.json's nearCarMax;
//  - a 12-car train (head, 10 middle, tail) of a set is over nearTrainMax /
//    its far train over farTrainMax;
//  - a far car has half or more of its near car's triangles, or does not fit
//    the near car's box (decisions 420, 432);
//  - a fine car (a near car from fineCarFromTriangles) of a set named in
//    --new-set has no far version (decision 417 rule 1);
//  - a model's hash differs from the lock, unless it is named in --allow
//    (a deliberate model change the PR must justify), or a locked model is gone.
// Sets listed under "grandfathered" in budgets.json keep their old results.
import {readFileSync, writeFileSync, existsSync} from 'node:fs';
import {resolve, dirname} from 'node:path';
const argv = process.argv.slice(2);
const flag = (name, fallback) => { const at = argv.indexOf(name); return at >= 0 ? argv[at + 1] : fallback; };
const here = dirname(new URL(import.meta.url).pathname);
const root = resolve(argv[0]);
const manifest = JSON.parse(readFileSync(resolve(root, 'manifest.json')));
const budgets = JSON.parse(readFileSync(resolve(here, 'budgets.json')));
const lockPath = resolve(flag('--lock', resolve(here, 'hashes.lock.json')));
const allow = new Set((flag('--allow', '') || '').split(',').filter(Boolean));
const newSets = new Set((flag('--new-set', '') || '').split(',').filter(Boolean));
const grand = budgets.grandfathered;
const byId = new Map(manifest.models.map(m => [m.id, m]));
const failures = [], notes = [], found = {noFar: {}, farBox: {}, farShare: {}};
const writeGrand = argv.includes('--grandfather-write');
const fail = (kind, text, id) => { found[kind][id] = found[kind][id] || text; if ((grand[kind] || {})[id] || writeGrand) notes.push(`grandfathered ${kind}: ${text}`); else failures.push(text); };
const sum = list => list.reduce((s, m) => s + m.triangles, 0);

for (const m of manifest.models.filter(m => m.role === 'near')) {
  if (m.triangles > budgets.nearCarMax) failures.push(`${m.id}: ${m.triangles} triangles, over the near car budget ${budgets.nearCarMax} (decision 417)`);
}
for (const set of manifest.sets) {
  const unit = name => byId.get(`set-${set.key}-${name}`);
  const head = unit('head') || unit('single'), middle = unit('middle') || unit('car'), tail = unit('tail') || head;
  const train = (pick) => head && middle ? [pick(head), ...Array(budgets.referenceCars - 2).fill(pick(middle)), pick(tail)] : null;
  const near = train(m => m);
  if (near && sum(near) > budgets.nearTrainMax) failures.push(`${set.key}: a ${budgets.referenceCars}-car train is ${sum(near)} triangles, over ${budgets.nearTrainMax}`);
  if (!set.far) {
    const fine = [...byId.values()].filter(m => m.id.startsWith(`set-${set.key}-`) && m.role === 'near' && m.triangles >= budgets.fineCarFromTriangles);
    if (fine.length) {
      const text = `${set.key}: ${fine.length} car(s) of ${budgets.fineCarFromTriangles}+ triangles and no far version (decision 417)`;
      if (newSets.has(set.key)) failures.push(text); else fail('noFar', text, set.key);
    }
    continue;
  }
  const far = train(m => byId.get(m.far) || m);
  if (far && sum(far) > budgets.farTrainMax) failures.push(`${set.key}: the far ${budgets.referenceCars}-car train is ${sum(far)} triangles, over ${budgets.farTrainMax}`);
  for (const m of [...byId.values()].filter(m => m.id.startsWith(`set-${set.key}-`) && m.far)) {
    const f = byId.get(m.far);
    if (!f) continue;
    if (!(f.triangles < m.triangles * budgets.farCarShareOfNearBelow)) fail('farShare', `${m.id}: far ${f.triangles} of near ${m.triangles}, not under ${budgets.farCarShareOfNearBelow * 100}% (decision 420)`, set.key);
    const b = budgets.farBox;
    if (Math.abs(f.minimum[0] - m.minimum[0]) > b.xMetres || Math.abs(f.maximum[0] - m.maximum[0]) > b.xMetres
        || Math.abs(f.maximum[2] - m.maximum[2]) > b.topMetres || Math.abs(f.minimum[2]) > b.groundMetres) fail('farBox', `${m.id}: the far car is not in the near car's box`, set.key);
  }
}

let hashed = 0;
if (existsSync(lockPath)) {
  const lock = JSON.parse(readFileSync(lockPath)).models;
  for (const m of manifest.models) {
    const locked = lock[m.id];
    if (!locked) { notes.push(`new model ${m.id} (${m.triangles} triangles, hash ${m.hash}): add it to the lock`); continue; }
    hashed++;
    if ((locked.hash !== m.hash || locked.triangles !== m.triangles) && !allow.has(m.id)) failures.push(`${m.id}: hash ${m.hash} (${m.triangles} triangles), the lock has ${locked.hash} (${locked.triangles}); a deliberate change is named with --allow ${m.id}`);
  }
  if (manifest.models.length > 100) for (const id of Object.keys(lock)) if ((id.startsWith('set-') || id.startsWith('style-')) && !byId.has(id)) failures.push(`${id}: in the lock, not in this run`);
} else notes.push(`no lock at ${lockPath}`);

if (writeGrand) {
  // Only for the day this tool was made: the sets on main that already break a rule.
  for (const k of Object.keys(found)) grand[k] = Object.fromEntries(Object.entries(found[k]).map(([id, text]) => [id, text.replace(/^.*?: /, '')]));
  writeFileSync(resolve(here, 'budgets.json'), JSON.stringify(budgets, null, 2) + '\n');
  console.log('wrote the grandfathered sets to budgets.json');
}
console.log(`${manifest.models.length} models, ${manifest.sets.length} sets, ${hashed} hashes compared with the lock`);
for (const n of notes) console.log('note: ' + n);
for (const f of failures) console.log('FAIL: ' + f);
if (failures.length) { console.log(`${failures.length} failure(s)`); process.exit(1); }
console.log('ok');
