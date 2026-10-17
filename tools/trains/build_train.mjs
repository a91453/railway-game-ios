// Builds the city-view N700ST train models and their analytical ambient occlusion textures
// directly from Node.js (with no external dependencies):
//
//   node tools/trains/build_train.mjs [n700st-cab n700st-car]
//
// Mirrors the parametric loft and UV conventions of tools/trains/build_train.py and
// Web/CityView/src/world/trains.js:
//   - TEXCOORD_0: the livery atlas coordinates painted at run time by trains.js (side strip +
//                 top-of-nose windscreen chart + plain roof/underframe swatches).
//   - TEXCOORD_1: per-face packed UV grid for the analytical ambient occlusion PNGs
//                 (n700st-cab-ao.png, n700st-car-ao.png).
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import zlib from 'zlib';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '../..');
const OUT_DIR = path.join(ROOT, 'Web/CityView/public/models/trains');

const STOCK = {
  'n700st-cab': {
    name: 'THSR N700ST cab car',
    length: 24.4,
    nose: 9.0,
    shell: {
      halfW: 1.45, floor: 0.62, roof: 3.75, drop: 1.78, lift: 0.1,
      tuck: 0.34, cap: 0.56, wing: 0.06, shoulder: 0.64, canopy: 0.24,
    },
    window: { from: 0.555, to: 0.780, pitch: 1.0, width: 0.50 },
    door: { width: 0.85 },
    skirtTop: 0.28,
    screen: true,
    pantograph: false,
  },
  'n700st-car': {
    name: 'THSR N700ST intermediate car',
    length: 24.4,
    nose: 0.0,
    shell: {
      halfW: 1.45, floor: 0.62, roof: 3.75, drop: 1.78, lift: 0.1,
      tuck: 0.34, cap: 0.56, wing: 0.06, shoulder: 0.64, canopy: 0.24,
    },
    window: { from: 0.555, to: 0.780, pitch: 1.0, width: 0.50 },
    door: { width: 0.85 },
    skirtTop: 0.28,
    screen: false,
    pantograph: false,
  },
};

const RING = 28, NOSE_RINGS = 22, BODY_STEP = 1.2;
const SIDE = 'side', ROOF = 'roof', UNDER = 'under', SCREEN = 'screen';
const TEX_W = 2048, TEX_H = 512, SIDE_Y0 = 16, SIDE_Y1 = 256;
const V_SIDE = [1 - SIDE_Y1 / TEX_H, 1 - SIDE_Y0 / TEX_H];
const SWATCH = 1 - SIDE_Y0 / 2 / TEX_H;
const SWATCH_U = { [ROOF]: 0.25, [UNDER]: 0.75 };
const NOSE_X0 = 16, NOSE_X1 = 1456, NOSE_Y0 = 264, NOSE_Y1 = 504, NOSE_ACROSS = 3;

const ease = (x) => {
  const t = Math.min(1, Math.max(0, x));
  return t * t * (3 - 2 * t);
};

function section(t, sh) {
  const halfW = sh.halfW * (1 - sh.tuck * ease((t - 0.45) / 0.55));
  const top = sh.roof - sh.drop * ease(t);
  const bottom = sh.floor + sh.lift * ease((t - 0.6) / 0.4);
  const cap = 1 - sh.cap * ease((t - 0.88) / 0.12);
  return [halfW, top, bottom, cap, 2 / (8.5 - 5.6 * ease(t)), 2 / (4.6 - 2.3 * ease(t))];
}

function ring(x, t, sh) {
  const [halfW, top, bottom, cap, low, up] = section(t, sh);
  const cz = (top + bottom) / 2, hz = ((top - bottom) / 2) * cap;
  const canopy = sh.canopy ?? 0;
  const pts = [];
  for (let k = 0; k < RING; k++) {
    const a = -Math.PI / 2 + (2 * Math.PI * k) / RING;
    const c = Math.cos(a), s = Math.sin(a);
    let z = cz + Math.sign(s) * (Math.abs(s) ** (s < 0 ? low : up)) * hz;
    const rawF = (z - bottom) / Math.max(0.01, top - bottom);
    if (t > 0 && s > 0 && (canopy > 0 || sh.wing > 0)) {
      const dome = canopy * Math.sin(Math.PI * Math.min(1, t / 0.50)) * Math.exp(-((c / 0.48) ** 2)) * s;
      const cheek = sh.wing * 1.4 * 4 * t * (1 - t) * Math.exp(-(((Math.abs(c) - 0.76) / 0.20) ** 2)) * s;
      z = Math.min(sh.roof, z + (dome + cheek) * cap);
    }
    const f = Math.min(1, Math.max(0, (z - bottom) / Math.max(0.01, top - bottom)));
    const wing = 1 + sh.wing * Math.exp(-(((rawF - sh.shoulder) / 0.1) ** 2));
    const y = Math.sign(c) * Math.min(sh.halfW, (Math.abs(c) ** low) * halfW * wing * cap);
    pts.push([y, z, f]);
  }
  return pts;
}

function flank(t, sh, f) {
  const [halfW, top, bottom, cap, low, up] = section(t, sh);
  const cz = (top + bottom) / 2, hz = ((top - bottom) / 2) * cap;
  const z = bottom + f * (top - bottom);
  const q = hz === 0 ? 0 : (z - cz) / hz;
  const s = Math.sign(q) * (Math.min(1, Math.abs(q)) ** (1 / (q < 0 ? low : up)));
  const c = Math.sqrt(Math.max(0, 1 - s * s));
  const wing = 1 + sh.wing * Math.exp(-(((f - sh.shoulder) / 0.1) ** 2));
  return Math.min(sh.halfW, (c ** low) * halfW * wing * cap);
}

function layout(spec) {
  const span = spec.length - spec.nose;
  const dw = spec.door.width, w = spec.window;
  const doors = [1.3, span - 1.3 - dw];
  const panes = [];
  let x = doors[0] + dw + w.pitch * 0.6;
  while (x + w.width < doors[1] - w.pitch * 0.3) {
    panes.push(x);
    x += w.pitch;
  }
  return [doors, panes];
}

function noseUv(along, across) {
  return [
    (NOSE_X0 + along * (NOSE_X1 - NOSE_X0)) / TEX_W,
    1 - (NOSE_Y0 + across * (NOSE_Y1 - NOSE_Y0)) / TEX_H,
  ];
}

function buildCarMesh(spec) {
  const sh = spec.shell, half = spec.length / 2, nose = spec.nose;
  const bodyEnd = nose ? half - nose : half;
  const steps = Math.max(1, Math.round((bodyEnd + half) / BODY_STEP));
  const xs = [];
  for (let i = 0; i <= steps; i++) xs.push([-half + ((bodyEnd + half) * i) / steps, 0]);
  if (nose) {
    for (let i = 1; i <= NOSE_RINGS; i++) xs.push([bodyEnd + (nose * i) / NOSE_RINGS, i / NOSE_RINGS]);
  }
  const rings = xs.map(([x, t]) => [x, ring(x, t, sh), t]);

  // verts in Blender coords: x along (+front), y across (+left), z up (+up)
  const verts = [];
  const faces = []; // each face: { indices: [..], kind, smooth }
  const occluders = []; // boxes/panels that cast AO onto the body

  for (const [x, pts] of rings) {
    for (const [y, z] of pts) verts.push([x, y, z]);
  }
  const k0 = Math.floor(RING / 2) - NOSE_ACROSS, k1 = Math.floor(RING / 2) + NOSE_ACROSS;
  for (let i = 0; i < rings.length - 1; i++) {
    for (let k = 0; k < RING; k++) {
      const a = i * RING + k, b = i * RING + ((k + 1) % RING);
      const isScreen = spec.screen && i >= steps && i < steps + NOSE_RINGS && k >= k0 && k < k1;
      faces.push({
        indices: [a, b, b + RING, a + RING],
        kind: isScreen ? SCREEN : SIDE,
        smooth: true,
      });
    }
  }
  for (const [idx, front] of [[0, false], [rings.length - 1, true]]) {
    const [x, pts] = rings[idx];
    const centre = verts.length;
    let sy = 0, sz = 0;
    for (const p of pts) { sy += p[0] / RING; sz += p[1] / RING; }
    verts.push([x, sy, sz]);
    for (let k = 0; k < RING; k++) {
      const a = idx * RING + k, b = idx * RING + ((k + 1) % RING);
      faces.push({
        indices: front ? [centre, a, b] : [centre, b, a],
        kind: front && nose > 0 ? ROOF : SIDE,
        smooth: true,
      });
    }
  }

  function addBox(cx, cy, cz, sx, sy, sz, where) {
    const o = verts.length;
    for (const dx of [-1, 1]) {
      for (const dy of [-1, 1]) {
        for (const dz of [-1, 1]) {
          verts.push([cx + (dx * sx) / 2, cy + (dy * sy) / 2, cz + (dz * sz) / 2]);
        }
      }
    }
    for (const f of [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]) {
      faces.push({ indices: f.map((i) => o + i), kind: where, smooth: false });
    }
    occluders.push({ min: [cx - sx / 2, cy - sy / 2, cz - sz / 2], max: [cx + sx / 2, cy + sy / 2, cz + sz / 2], kind: where });
  }

  function addCylinder(cx, cy, cz, r, w, where, seg = 12) {
    const o = verts.length;
    for (const side of [-1, 1]) {
      for (let k = 0; k < seg; k++) {
        const a = (2 * Math.PI * k) / seg;
        verts.push([cx + r * Math.cos(a), cy + (side * w) / 2, cz + r * Math.sin(a)]);
      }
    }
    for (let k = 0; k < seg; k++) {
      const n = (k + 1) % seg;
      faces.push({ indices: [o + k, o + n, o + seg + n, o + seg + k], kind: where, smooth: false });
    }
    for (const [side, base] of [[0, o], [1, o + seg]]) {
      const c = verts.length;
      verts.push([cx, cy + ((side === 0 ? -1 : 1) * w) / 2, cz]);
      for (let k = 0; k < seg; k++) {
        const n = (k + 1) % seg;
        faces.push({
          indices: side ? [c, base + k, base + n] : [c, base + n, base + k],
          kind: where,
          smooth: false,
        });
      }
    }
    occluders.push({ min: [cx - r, cy - w / 2, cz - r], max: [cx + r, cy + w / 2, cz + r], kind: where });
  }

  function addPanel(left, side, f0, f1, length, proud, rows) {
    const [, top, bottom] = section(0, sh);
    const x0 = -spec.length / 2 + left, x1 = x0 + length;
    const o = verts.length;
    let minY = Infinity, maxY = -Infinity, minZ = Infinity, maxZ = -Infinity;
    for (let r = 0; r <= rows; r++) {
      const f = f0 + ((f1 - f0) * r) / rows;
      const z = bottom + f * (top - bottom);
      const out = flank(0, sh, f);
      for (const y of [out + proud, out]) {
        for (const x of [x0, x1]) {
          const sy = side * y;
          verts.push([x, sy, z]);
          if (sy < minY) minY = sy;
          if (sy > maxY) maxY = sy;
          if (z < minZ) minZ = z;
          if (z > maxZ) maxZ = z;
        }
      }
    }
    const quad = (...ix) => {
      const f = ix.map((i) => o + i);
      faces.push({ indices: side > 0 ? f : f.slice().reverse(), kind: SIDE, smooth: true });
    };
    for (let r = 0; r < rows; r++) {
      const p = r * 4, q = (r + 1) * 4;
      quad(p, q, q + 1, p + 1);
      quad(p + 2, q + 2, q, p);
      quad(p + 1, q + 1, q + 3, p + 3);
    }
    const t = rows * 4;
    quad(1, 3, 2, 0);
    quad(t, t + 2, t + 3, t + 1);
    occluders.push({ min: [x0, minY, minZ], max: [x1, maxY, maxZ], kind: 'panel', side, proud });
  }

  const bodyFrom = -half + 1.2, bodyTo = nose ? half - nose + 1.4 : half - 1.2;
  const [doors, panes] = layout(spec);
  const w = spec.window;
  for (const side of [-1, 1]) {
    for (const d of doors) {
      addPanel(d, side, spec.skirtTop, 0.94, spec.door.width, 0.012, 5);
    }
    for (const x of panes) {
      addPanel(x, side, w.from, w.to, w.width, 0.022, 3);
    }
  }
  for (const x of [bodyFrom + 2.6, bodyTo - 2.6]) {
    addBox(x, 0, 0.62, 2.9, 2.1, 0.42, UNDER);
    for (const wx of [x - 1.15, x + 1.15]) {
      for (const wy of [-1.06, 1.06]) {
        addCylinder(wx, wy, 0.43, 0.43, 0.14, UNDER);
      }
    }
  }
  addBox((bodyFrom + bodyTo) / 2, 0, 0.42, bodyTo - bodyFrom, 2.2, 0.45, UNDER);

  // Shinkansen roof: continuous high-voltage cable shrouds stopping clear of the cab nose;
  // the pantograph fairing is added only on cars that carry a pantograph (cars 4 and 9).
  const runFrom = bodyFrom + 0.6;
  const runTo = nose ? half - nose - 1.0 : bodyTo - 0.6;
  for (const y of [-0.72, 0.72]) {
    addBox((runFrom + runTo) / 2, y, sh.roof + 0.04, runTo - runFrom, 0.28, 0.16, ROOF);
  }
  if (spec.pantograph) {
    const pantoX = (runFrom + runTo) / 2;
    addBox(pantoX, 0, sh.roof + 0.07, 3.0, 1.62, 0.22, ROOF);
    addBox(pantoX, 0, sh.roof + 0.20, 1.8, 1.36, 0.08, UNDER);
  }

  return { verts, faces, rings, noseFrom: steps, occluders };
}

function computeLoopUV0(vi, where, verts, rings, noseFrom, spec) {
  const half = spec.length / 2, L = spec.length, sh = spec.shell;
  const u0 = spec.nose > 0 ? 0.0 : 0.5;
  const k0 = Math.floor(RING / 2) - NOSE_ACROSS;
  if (where === SCREEN) {
    const i = Math.floor(vi / RING), k = vi % RING;
    const pts = rings[i][1];
    const [u, v] = noseUv((i - noseFrom) / NOSE_RINGS, 0.5 - (0.5 * pts[k][0]) / pts[k0][0]);
    return [u, v];
  }
  if (where !== SIDE) {
    return [SWATCH_U[where], SWATCH];
  }
  const v = verts[vi];
  const along = Math.min(1, Math.max(0, u0 + 0.004 + ((v[0] + half) / L) * 0.492));
  // Use the ring's own f for shell vertices so nose bands follow the nose curve smoothly.
  let f;
  if (vi < rings.length * RING) {
    const i = Math.floor(vi / RING), k = vi % RING;
    f = rings[i][1][k][2];
  } else {
    f = Math.min(1, Math.max(0, (v[2] - sh.floor) / (sh.roof - sh.floor)));
  }
  return [along, V_SIDE[0] + (V_SIDE[1] - V_SIDE[0]) * f];
}

// Compute analytical ambient occlusion at point (x, y, z) with normal (nx, ny, nz) in Blender coords
function evaluateAO(p, n, occluders, sh) {
  const [x, y, z] = p;
  const [nx, ny, nz] = n;
  let ao = 1.0;

  // 1. Underbody & lower skirt ground-proximity shading
  if (z < sh.floor + 0.35) {
    const t = Math.max(0, Math.min(1, (sh.floor + 0.35 - z) / 0.65));
    ao *= 1.0 - 0.28 * t * t;
  }
  if (nz < -0.3) {
    ao *= 0.72;
  }

  // 2. Contact shadows around proud panels (windows & doors), roof shrouds, and bogies
  for (const occ of occluders) {
    const dx = Math.max(0, occ.min[0] - x, x - occ.max[0]);
    const dy = Math.max(0, occ.min[1] - y, y - occ.max[1]);
    const dz = Math.max(0, occ.min[2] - z, z - occ.max[2]);
    const dist = Math.hypot(dx, dy, dz);
    if (occ.kind === 'panel') {
      if (dist > 0.001 && dist < 0.14 && Math.sign(y) === occ.side && Math.abs(ny) > 0.4) {
        const s = 1 - dist / 0.14;
        ao *= 1.0 - 0.24 * s * s;
      }
      if (dist < 0.005 && Math.abs(ny) < 0.4) {
        ao *= 0.78;
      }
    } else if (occ.kind === ROOF) {
      if (dist > 0.001 && dist < 0.28 && z >= sh.roof - 0.12 && nz > 0.3) {
        const s = 1 - dist / 0.28;
        ao *= 1.0 - 0.26 * s * s;
      }
    } else if (occ.kind === UNDER) {
      if (dist > 0.001 && dist < 0.35 && z < sh.floor + 0.25) {
        const s = 1 - dist / 0.35;
        ao *= 1.0 - 0.22 * s * s;
      }
    }
  }
  return Math.max(0.28, Math.min(1.0, ao));
}

function writeGrayscalePNG(width, height, pixels, outPath) {
  const raw = Buffer.alloc(height * (1 + width));
  for (let y = 0; y < height; y++) {
    const rowStart = y * (1 + width);
    raw[rowStart] = 0;
    for (let x = 0; x < width; x++) {
      raw[rowStart + 1 + x] = pixels[y * width + x];
    }
  }
  const compressed = zlib.deflateSync(raw, { level: 9 });

  const crcTable = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crcTable[n] = c >>> 0;
  }
  const crc32 = (buf) => {
    let c = 0xffffffff;
    for (let i = 0; i < buf.length; i++) c = crcTable[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length, 0);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body), 0);
    return Buffer.concat([len, body, crc]);
  };

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 0;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  const png = Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr),
    chunk('IDAT', compressed),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  fs.writeFileSync(outPath, png);
}

function buildGLBAndAO(name, spec) {
  const { verts, faces, rings, noseFrom, occluders } = buildCarMesh(spec);

  const faceNormals = faces.map((f) => {
    const a = verts[f.indices[0]], b = verts[f.indices[1]], c = verts[f.indices[2]];
    const ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2];
    const vx = c[0] - a[0], vy = c[1] - a[1], vz = c[2] - a[2];
    const nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    const len = Math.hypot(nx, ny, nz) || 1;
    return [nx / len, ny / len, nz / len];
  });

  const smoothVertNormals = verts.map(() => [0, 0, 0]);
  faces.forEach((f, fi) => {
    if (!f.smooth) return;
    const fn = faceNormals[fi];
    for (const vi of f.indices) {
      smoothVertNormals[vi][0] += fn[0];
      smoothVertNormals[vi][1] += fn[1];
      smoothVertNormals[vi][2] += fn[2];
    }
  });
  for (const n of smoothVertNormals) {
    const len = Math.hypot(n[0], n[1], n[2]) || 1;
    n[0] /= len; n[1] /= len; n[2] /= len;
  }

  const AO_SIZE = 512;
  const gridCols = Math.ceil(Math.sqrt(faces.length));
  const cellPx = Math.floor(AO_SIZE / gridCols);
  const aoPixels = new Uint8Array(AO_SIZE * AO_SIZE).fill(255);

  const positions = [];
  const normals = [];
  const uv0s = [];
  const uv1s = [];
  const indices = [];

  const toGltfPos = ([x, y, z]) => [x, z, -y];
  const toGltfNorm = ([nx, ny, nz]) => [nx, nz, -ny];

  faces.forEach((f, fi) => {
    const col = fi % gridCols, row = Math.floor(fi / gridCols);
    const px0 = col * cellPx + 1, py0 = row * cellPx + 1;
    const pw = Math.max(1, cellPx - 2), ph = Math.max(1, cellPx - 2);
    const uMin = (px0 + 0.5) / AO_SIZE, uMax = (px0 + pw - 0.5) / AO_SIZE;
    const vMin = (py0 + 0.5) / AO_SIZE, vMax = (py0 + ph - 0.5) / AO_SIZE;

    const fn = faceNormals[fi];
    const cornerUV1 = f.indices.length === 4
      ? [[uMin, vMin], [uMax, vMin], [uMax, vMax], [uMin, vMax]]
      : [[(uMin + uMax) / 2, vMin], [uMin, vMax], [uMax, vMax]];

    const p0 = verts[f.indices[0]], p1 = verts[f.indices[1]], p2 = verts[f.indices[2]];
    const p3 = f.indices.length === 4 ? verts[f.indices[3]] : p2;
    for (let dy = -1; dy <= ph; dy++) {
      const ty = Math.min(AO_SIZE - 1, Math.max(0, py0 + dy));
      const sv = Math.min(1, Math.max(0, (dy + 0.5) / ph));
      for (let dx = -1; dx <= pw; dx++) {
        const tx = Math.min(AO_SIZE - 1, Math.max(0, px0 + dx));
        const su = Math.min(1, Math.max(0, (dx + 0.5) / pw));
        const px = (1 - su) * (1 - sv) * p0[0] + su * (1 - sv) * p1[0] + su * sv * p2[0] + (1 - su) * sv * p3[0];
        const py = (1 - su) * (1 - sv) * p0[1] + su * (1 - sv) * p1[1] + su * sv * p2[1] + (1 - su) * sv * p3[1];
        const pz = (1 - su) * (1 - sv) * p0[2] + su * (1 - sv) * p1[2] + su * sv * p2[2] + (1 - su) * sv * p3[2];
        const val = evaluateAO([px, py, pz], fn, occluders, spec.shell);
        aoPixels[ty * AO_SIZE + tx] = Math.round(val * 255);
      }
    }

    const baseVertex = positions.length / 3;
    f.indices.forEach((vi, ci) => {
      const gp = toGltfPos(verts[vi]);
      const gn = toGltfNorm(f.smooth ? smoothVertNormals[vi] : fn);
      const [u0, v0] = computeLoopUV0(vi, f.kind, verts, rings, noseFrom, spec);
      const [u1, v1] = cornerUV1[ci];
      positions.push(...gp);
      normals.push(...gn);
      uv0s.push(u0, v0);
      uv1s.push(u1, v1);
    });
    if (f.indices.length === 4) {
      indices.push(baseVertex, baseVertex + 1, baseVertex + 2, baseVertex, baseVertex + 2, baseVertex + 3);
    } else {
      indices.push(baseVertex, baseVertex + 1, baseVertex + 2);
    }
  });

  const aoPath = path.join(OUT_DIR, `${name}-ao.png`);
  writeGrayscalePNG(AO_SIZE, AO_SIZE, aoPixels, aoPath);

  const posArr = new Float32Array(positions);
  const normArr = new Float32Array(normals);
  const uv0Arr = new Float32Array(uv0s);
  const uv1Arr = new Float32Array(uv1s);
  const idxArr = new Uint16Array(indices);

  const minPos = [Infinity, Infinity, Infinity], maxPos = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < positions.length; i += 3) {
    for (let k = 0; k < 3; k++) {
      if (positions[i + k] < minPos[k]) minPos[k] = positions[i + k];
      if (positions[i + k] > maxPos[k]) maxPos[k] = positions[i + k];
    }
  }

  const pad4 = (buf) => {
    const rem = buf.length % 4;
    return rem === 0 ? buf : Buffer.concat([buf, Buffer.alloc(4 - rem)]);
  };

  const bPos = pad4(Buffer.from(posArr.buffer));
  const bNorm = pad4(Buffer.from(normArr.buffer));
  const bUv0 = pad4(Buffer.from(uv0Arr.buffer));
  const bUv1 = pad4(Buffer.from(uv1Arr.buffer));
  const bIdx = pad4(Buffer.from(idxArr.buffer));

  const binChunk = Buffer.concat([bPos, bNorm, bUv0, bUv1, bIdx]);
  const vCount = positions.length / 3;

  let offset = 0;
  const view = (buf, target) => {
    const v = { buffer: 0, byteOffset: offset, byteLength: buf.length, target };
    offset += buf.length;
    return v;
  };
  const bufferViews = [
    view(Buffer.from(posArr.buffer), 34962),
    { ...view(Buffer.from(normArr.buffer), 34962), byteOffset: bPos.length },
    { ...view(Buffer.from(uv0Arr.buffer), 34962), byteOffset: bPos.length + bNorm.length },
    { ...view(Buffer.from(uv1Arr.buffer), 34962), byteOffset: bPos.length + bNorm.length + bUv0.length },
    { ...view(Buffer.from(idxArr.buffer), 34963), byteOffset: bPos.length + bNorm.length + bUv0.length + bUv1.length },
  ];

  const gltfJson = {
    asset: { version: '2.0', generator: 'railway-game-ios tools/trains/build_train.mjs' },
    scene: 0,
    scenes: [{ name: 'Scene', nodes: [0] }],
    nodes: [{ mesh: 0, name: spec.name }],
    meshes: [{
      name: spec.name,
      primitives: [{
        attributes: { POSITION: 0, NORMAL: 1, TEXCOORD_0: 2, TEXCOORD_1: 3 },
        indices: 4,
        mode: 4,
      }],
    }],
    accessors: [
      { bufferView: 0, componentType: 5126, count: vCount, type: 'VEC3', min: minPos, max: maxPos },
      { bufferView: 1, componentType: 5126, count: vCount, type: 'VEC3' },
      { bufferView: 2, componentType: 5126, count: vCount, type: 'VEC2' },
      { bufferView: 3, componentType: 5126, count: vCount, type: 'VEC2' },
      { bufferView: 4, componentType: 5123, count: indices.length, type: 'SCALAR' },
    ],
    bufferViews,
    buffers: [{ byteLength: binChunk.length }],
  };

  let jsonBuf = Buffer.from(JSON.stringify(gltfJson), 'utf8');
  const jsonRem = jsonBuf.length % 4;
  if (jsonRem !== 0) {
    jsonBuf = Buffer.concat([jsonBuf, Buffer.alloc(4 - jsonRem, 0x20)]);
  }

  const totalLen = 12 + 8 + jsonBuf.length + 8 + binChunk.length;
  const header = Buffer.alloc(12);
  header.writeUInt32LE(0x46546c67, 0);
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(totalLen, 8);

  const jsonHeader = Buffer.alloc(8);
  jsonHeader.writeUInt32LE(jsonBuf.length, 0);
  jsonHeader.writeUInt32LE(0x4e4f534a, 4);

  const binHeader = Buffer.alloc(8);
  binHeader.writeUInt32LE(binChunk.length, 0);
  binHeader.writeUInt32LE(0x004e4942, 4);

  const glbPath = path.join(OUT_DIR, `${name}.glb`);
  fs.writeFileSync(glbPath, Buffer.concat([header, jsonHeader, jsonBuf, binHeader, binChunk]));
  console.log(`${name}: ${indices.length / 3} triangles, ${vCount} vertices -> ${path.basename(glbPath)} (${(totalLen / 1024).toFixed(1)} kB), ${path.basename(aoPath)} (${(fs.statSync(aoPath).size / 1024).toFixed(1)} kB)`);
  return {
    ao: `${name}-ao.png`,
    aoChannel: 1,
    file: `${name}.glb`,
    fit: false,
    front: '+x',
  };
}

const names = process.argv.slice(2);
const targets = names.length ? names : Object.keys(STOCK);
fs.mkdirSync(OUT_DIR, { recursive: true });
const indexPath = path.join(OUT_DIR, 'index.json');
const indexData = fs.existsSync(indexPath) ? JSON.parse(fs.readFileSync(indexPath, 'utf8')) : {};
for (const name of targets) {
  indexData[name] = buildGLBAndAO(name, STOCK[name]);
}
fs.writeFileSync(indexPath, JSON.stringify(indexData, null, 2) + '\n');
console.log('Updated', indexPath);
