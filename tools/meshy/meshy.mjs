// Makes the 3D models of tools/meshy/models.json with Meshy's Text to 3D API (https://docs.meshy.ai/en/api/text-to-3d)
// and packs them for the 3D city view (ARCHITECTURE decision 161). Run from the repository root:
//
//   MESHY_API_KEY=... node tools/meshy/meshy.mjs balance
//   MESHY_API_KEY=... node tools/meshy/meshy.mjs generate emu900-cab [more ids]   (30 credits each)
//   node tools/meshy/meshy.mjs pack emu900-cab [more ids]
//
// The key is read from the environment only, never written anywhere. `generate` makes a preview (the mesh,
// remeshed to the entry's polycount), textures it (refine), downloads the GLB and the thumbnail into
// Web/CityView/data/raw/meshy/<id>/ (not committed) and records the prompts, task ids and credits in
// tools/meshy/generated.json. An entry already recorded is downloaded again from its finished task instead of
// paying for a new one; `--again` makes a new one. `pack` shrinks the GLB's pictures (sharp, from
// Web/CityView's packages) to `--size` pixels (1024) and writes it to the entry's `out`. It keeps the GLB's
// `asset` and `extras` as they are: Meshy's terms (§2.4) ask that the AI identifiers stay in the output.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';

const ROOT = process.cwd();
const SPEC = path.join(ROOT, 'tools/meshy/models.json');
const RECORD = path.join(ROOT, 'tools/meshy/generated.json');
const RAW = path.join(ROOT, 'Web/CityView/data/raw/meshy');
const API = 'https://api.meshy.ai';
const AI_MODEL = 'latest';          // Meshy 7.1 (2026-10)
const POLL_MS = 5000, TIMEOUT_MS = 30 * 60 * 1000;

if (!fs.existsSync(SPEC)) { console.error('run from the repository root'); process.exit(1); }
const [command, ...rest] = process.argv.slice(2);
const flags = new Set(rest.filter((a) => a.startsWith('--') && !a.includes('=')));
const option = (name, fallback) => rest.find((a) => a.startsWith(`--${name}=`))?.split('=')[1] ?? fallback;
const ids = rest.filter((a) => !a.startsWith('--'));
const spec = JSON.parse(fs.readFileSync(SPEC, 'utf8')).models;
const entry = (id) => spec.find((m) => m.id === id) ?? fail(`no model "${id}" in tools/meshy/models.json`);
const record = () => (fs.existsSync(RECORD) ? JSON.parse(fs.readFileSync(RECORD, 'utf8')) : {});
function fail(message) { console.error(message); process.exit(1); }

async function api(method, route, body) {
  const key = process.env.MESHY_API_KEY ?? fail('MESHY_API_KEY is not set (see tools/meshy/README.md)');
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(API + route, {
      method,
      headers: { Authorization: `Bearer ${key}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.status === 429 && attempt < 5) { await sleep(2000 * 2 ** attempt); continue; }   // rate limit
    const text = await res.text();
    if (!res.ok) fail(`${method} ${route}: ${res.status} ${text.slice(0, 300)}`);
    return text ? JSON.parse(text) : null;
  }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function finished(taskId, label) {
  const start = Date.now();
  for (;;) {
    const task = await api('GET', `/openapi/v2/text-to-3d/${taskId}`);
    if (task.status === 'SUCCEEDED') { process.stdout.write('\n'); return task; }
    if (task.status === 'FAILED' || task.status === 'CANCELED') fail(`\n${label} ${task.status}: ${task.task_error?.message ?? ''}`);
    if (Date.now() - start > TIMEOUT_MS) fail(`\n${label}: still ${task.status} after 30 minutes (task ${taskId})`);
    process.stdout.write(`\r${label}: ${task.status} ${task.progress ?? 0}%   `);
    await sleep(POLL_MS);
  }
}

async function download(url, file) {
  const res = await fetch(url);
  if (!res.ok) fail(`download ${file}: ${res.status}`);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, Buffer.from(await res.arrayBuffer()));
}

async function generate(id) {
  const m = entry(id), done = record();
  let refine;
  if (done[id] && !flags.has('--again')) {
    console.log(`${id}: recorded (task ${done[id].refine_task}); downloading it again, --again makes a new one`);
    refine = await api('GET', `/openapi/v2/text-to-3d/${done[id].refine_task}`);
  } else {
    const previewId = (await api('POST', '/openapi/v2/text-to-3d', {
      mode: 'preview', prompt: m.prompt, ai_model: AI_MODEL, should_remesh: true, topology: 'triangle',
      target_polycount: m.target_polycount, target_formats: ['glb'],
    })).result;
    const preview = await finished(previewId, `${id} preview`);
    const refineId = (await api('POST', '/openapi/v2/text-to-3d', {
      mode: 'refine', preview_task_id: previewId, texture_prompt: m.texture_prompt, enable_pbr: false,
      texture_resolution: '2k', target_formats: ['glb'],
    })).result;
    refine = await finished(refineId, `${id} refine`);
    done[id] = {
      prompt: m.prompt, texture_prompt: m.texture_prompt, ai_model: AI_MODEL, target_polycount: m.target_polycount,
      preview_task: previewId, refine_task: refineId,
      credits: (preview.consumed_credits ?? 0) + (refine.consumed_credits ?? 0),
      finished: new Date(refine.finished_at || Date.now()).toISOString(),
    };
  }
  if (!refine.model_urls?.glb) fail(`${id}: the task has no GLB`);
  const glb = path.join(RAW, id, `${id}.glb`);
  await download(refine.model_urls.glb, glb);
  if (refine.thumbnail_url) await download(refine.thumbnail_url, path.join(RAW, id, 'thumbnail.png'));
  done[id].raw_sha256 = crypto.createHash('sha256').update(fs.readFileSync(glb)).digest('hex');
  done[id].raw_bytes = fs.statSync(glb).size;
  fs.writeFileSync(RECORD, JSON.stringify(done, null, 2) + '\n');
  console.log(`${id}: ${path.relative(ROOT, glb)} (${(done[id].raw_bytes / 1e6).toFixed(1)} MB, ${done[id].credits} credits)`);
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
  if (!fs.existsSync(raw)) fail(`${id}: ${path.relative(ROOT, raw)} is missing; run generate first`);
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
  console.log(`${id}: ${m.out} (${(fs.statSync(raw).size / 1e6).toFixed(1)} MB -> ${(fs.statSync(out).size / 1e6).toFixed(2)} MB, ${triangles} triangles)`);
}

if (command === 'balance') {
  const b = await api('GET', '/openapi/v1/balance');
  console.log(`credits: ${b.balance}`);
} else if (command === 'generate' || command === 'pack') {
  if (!ids.length) fail(`which models? ${spec.map((m) => m.id).join(', ')}`);
  for (const id of ids) await (command === 'generate' ? generate(id) : pack(id));
} else {
  fail('usage: node tools/meshy/meshy.mjs balance | generate <id...> [--again] | pack <id...> [--size=1024]');
}
