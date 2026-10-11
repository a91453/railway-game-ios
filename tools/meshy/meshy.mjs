// Packs the Meshy models of tools/meshy/models.json for the 3D city view (ARCHITECTURE decision 161). The models
// are made with Meshy's own CLI (meshy-cli 0.4.0, MIT) as its skill says (.claude/skills/meshy-3d-generation), the
// job's workspace being Web/CityView/data/raw/meshy/<id>/ (not committed) and the delivered GLB <id>.glb in it
// (tools/meshy/README.md). Run from the repository root:
//
//   node tools/meshy/meshy.mjs pack emu900-cab [more ids] [--size=1024]
//
// `pack` shrinks the GLB's pictures (sharp, from Web/CityView's packages) to `--size` pixels, writes the GLB to the
// entry's `out` and lists it in index.json beside it. It keeps the GLB's `asset` and `extras` as they are: Meshy's
// terms (§2.4) ask that the AI identifiers stay in the output. Where the model came from (the CLI's task
// snapshots in the workspace: task ids, prompts, model, credits) goes into tools/meshy/generated.json.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';

const ROOT = process.cwd();
const SPEC = path.join(ROOT, 'tools/meshy/models.json');
const RECORD = path.join(ROOT, 'tools/meshy/generated.json');
const RAW = path.join(ROOT, 'Web/CityView/data/raw/meshy');

if (!fs.existsSync(SPEC)) { console.error('run from the repository root'); process.exit(1); }
const [command, ...rest] = process.argv.slice(2);
const option = (name, fallback) => rest.find((a) => a.startsWith(`--${name}=`))?.split('=')[1] ?? fallback;
const ids = rest.filter((a) => !a.startsWith('--'));
const spec = JSON.parse(fs.readFileSync(SPEC, 'utf8')).models;
const entry = (id) => spec.find((m) => m.id === id) ?? fail(`no model "${id}" in tools/meshy/models.json`);
function fail(message) { console.error(message); process.exit(1); }

// The CLI's task snapshots (task_<id>.json beside its metadata.json) anywhere in the model's workspace.
function provenance(dir) {
  const tasks = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (/^task_.+\.json$/.test(e.name)) {
        const t = JSON.parse(fs.readFileSync(p, 'utf8')), task = t.result ?? t.data ?? t;
        tasks.push({
          id: task.id, type: task.type ?? null, prompt: task.prompt ?? null, texture_prompt: task.texture_prompt ?? null,
          ai_model: task.ai_model ?? null, model_type: task.model_type ?? null, credits: task.consumed_credits ?? null,
          finished: task.finished_at ? new Date(task.finished_at).toISOString() : null,
        });
      }
    }
  };
  walk(dir);
  return tasks.sort((a, b) => String(a.finished).localeCompare(String(b.finished)));
}

// ---- GLB: a 12-byte header, a JSON chunk and a BIN chunk (https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#glb-file-format-specification)
function readGlb(buf) {
  if (buf.readUInt32LE(0) !== 0x46546c67 || buf.readUInt32LE(4) !== 2) fail('not a glTF 2.0 binary');
  let o = 12, json, bin = Buffer.alloc(0);
  while (o < buf.length) {
    const len = buf.readUInt32LE(o), type = buf.readUInt32LE(o + 4), data = buf.subarray(o + 8, o + 8 + len);
    if (type === 0x4e4f534a) json = JSON.parse(data.toString('utf8'));
    else if (type === 0x004e4942) bin = data;
    o += 8 + len;
  }
  return { json, bin };
}
function writeGlb(json, bin) {
  const pad = (b, fill) => Buffer.concat([b, Buffer.alloc((4 - (b.length % 4)) % 4, fill)]);
  const j = pad(Buffer.from(JSON.stringify(json), 'utf8'), 0x20), b = pad(bin, 0);
  const head = Buffer.alloc(12), jh = Buffer.alloc(8), bh = Buffer.alloc(8);
  head.writeUInt32LE(0x46546c67, 0); head.writeUInt32LE(2, 4); head.writeUInt32LE(12 + 8 + j.length + 8 + b.length, 8);
  jh.writeUInt32LE(j.length, 0); jh.writeUInt32LE(0x4e4f534a, 4);
  bh.writeUInt32LE(b.length, 0); bh.writeUInt32LE(0x004e4942, 4);
  return Buffer.concat([head, jh, j, bh, b]);
}

async function pack(id) {
  const m = entry(id), raw = path.join(RAW, id, `${id}.glb`);
  if (!fs.existsSync(raw)) fail(`${id}: ${path.relative(ROOT, raw)} is missing; make it with the Meshy CLI first (tools/meshy/README.md)`);
  const sharp = createRequire(path.join(ROOT, 'Web/CityView/package.json'))('sharp');
  const size = Number(option('size', 1024));
  const { json, bin } = readGlb(fs.readFileSync(raw));
  const views = (json.bufferViews ?? []).map((v) => bin.subarray(v.byteOffset ?? 0, (v.byteOffset ?? 0) + v.byteLength));
  for (const image of json.images ?? []) {
    if (image.bufferView === undefined) continue;
    const input = views[image.bufferView], meta = await sharp(input).metadata();
    const clear = meta.hasAlpha && !(await sharp(input).stats()).isOpaque; // pictures with transparency stay PNG
    const resized = sharp(input).resize({ width: Math.min(size, meta.width), height: Math.min(size, meta.height), fit: 'inside' });
    views[image.bufferView] = clear ? await resized.png({ compressionLevel: 9 }).toBuffer() : await resized.flatten().jpeg({ quality: 82 }).toBuffer();
    image.mimeType = clear ? 'image/png' : 'image/jpeg';
  }
  const parts = [];
  let offset = 0;
  views.forEach((data, i) => {
    const gap = (4 - (offset % 4)) % 4;
    if (gap) { parts.push(Buffer.alloc(gap)); offset += gap; }
    Object.assign(json.bufferViews[i], { buffer: 0, byteOffset: offset, byteLength: data.length });
    parts.push(data); offset += data.length;
  });
  if (json.buffers?.length) json.buffers = [{ byteLength: offset }];
  const out = path.join(ROOT, m.out);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, writeGlb(json, Buffer.concat(parts)));
  // the city view finds the models, and the way each one faces, in index.json beside them (src/world/trains.js)
  const indexFile = path.join(path.dirname(out), 'index.json');
  const index = fs.existsSync(indexFile) ? JSON.parse(fs.readFileSync(indexFile, 'utf8')) : {};
  index[id] = { file: path.basename(out), front: m.front ?? '+x' };
  fs.writeFileSync(indexFile, JSON.stringify(index, null, 2) + '\n');
  const triangles = (json.meshes ?? []).flatMap((mesh) => mesh.primitives)
    .reduce((n, p) => n + (p.indices !== undefined ? json.accessors[p.indices].count : json.accessors[p.attributes.POSITION].count) / 3, 0);
  const record = fs.existsSync(RECORD) ? JSON.parse(fs.readFileSync(RECORD, 'utf8')) : {};
  const tasks = provenance(path.dirname(raw));
  record[id] = {
    tasks, credits: tasks.reduce((n, t) => n + (t.credits ?? 0), 0),
    raw_sha256: crypto.createHash('sha256').update(fs.readFileSync(raw)).digest('hex'), raw_bytes: fs.statSync(raw).size,
  };
  fs.writeFileSync(RECORD, JSON.stringify(record, null, 2) + '\n');
  console.log(`${id}: ${m.out} (${(fs.statSync(raw).size / 1e6).toFixed(1)} MB -> ${(fs.statSync(out).size / 1e6).toFixed(2)} MB, ${triangles} triangles; ${tasks.length} Meshy tasks)`);
}

if (command === 'pack' && ids.length) {
  for (const id of ids) await pack(id);
} else {
  fail(`usage: node tools/meshy/meshy.mjs pack <id...> [--size=1024]; models: ${spec.map((m) => m.id).join(', ')}`);
}
