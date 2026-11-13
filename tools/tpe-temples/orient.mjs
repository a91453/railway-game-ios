// Decision 725: SketchUp's faces are wound either way (a face's back is
// often the one outside), and the game lights a face by its winding, so a
// face wound against its neighbours shows dark or not at all. Faces are
// first wound alike across every edge exactly two of them share, one
// connected piece at a time (breadth first); then each piece as a whole is
// turned to whichever side sees more of the open air: rays from just off
// each face's two sides, in a fixed set of directions at or above the
// horizon (below it is ground), counted when they leave the model without
// meeting another face, summed over the piece by area. Two faces over the
// same three corners (a face and its back, both exported) keep only the
// first.

const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const cross = (u, v) => [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
const dot = (u, v) => u[0] * v[0] + u[1] * v[1] + u[2] * v[2];

// Directions on and above the horizon: straight up, three rings.
export const rays = (() => {
  const out = [[0, 0, 1]];
  for (const [elevation, count] of [[0, 12], [25, 10], [55, 6]]) {
    const e = elevation * Math.PI / 180;
    for (let i = 0; i < count; i++) {
      const a = (i + (elevation === 25 ? 0.5 : 0)) * 2 * Math.PI / count;
      out.push([Math.cos(e) * Math.cos(a), Math.cos(e) * Math.sin(a), Math.sin(e)]);
    }
  }
  return out;
})();

export function dedupe(triangles) {
  const seen = new Set();
  return triangles.filter(t => {
    const key = t.points.map(p => p.map(v => Math.round(v * 100)).join(',')).sort().join('|');
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

// A uniform grid of the faces, for rays.
function grid(triangles, cell) {
  const low = [0, 1, 2].map(k => Math.min(...triangles.map(t => Math.min(t.points[0][k], t.points[1][k], t.points[2][k])))).map(v => v - cell);
  const high = [0, 1, 2].map(k => Math.max(...triangles.map(t => Math.max(t.points[0][k], t.points[1][k], t.points[2][k])))).map(v => v + cell);
  const size = [0, 1, 2].map(k => Math.max(1, Math.ceil((high[k] - low[k]) / cell)));
  const cells = new Map();
  triangles.forEach((t, i) => {
    const lo = [0, 1, 2].map(k => Math.floor((Math.min(t.points[0][k], t.points[1][k], t.points[2][k]) - low[k]) / cell));
    const hi = [0, 1, 2].map(k => Math.floor((Math.max(t.points[0][k], t.points[1][k], t.points[2][k]) - low[k]) / cell));
    for (let x = lo[0]; x <= hi[0]; x++) for (let y = lo[1]; y <= hi[1]; y++) for (let z = lo[2]; z <= hi[2]; z++) {
      const key = (z * size[1] + y) * size[0] + x;
      if (!cells.has(key)) cells.set(key, []);
      cells.get(key).push(i);
    }
  });
  return { low, size, cell, cells };
}

// Möller–Trumbore: the distance along `d` from `o` to the face, or -1.
function hit(o, d, [a, b, c]) {
  const e1 = sub(b, a), e2 = sub(c, a), p = cross(d, e2), det = dot(e1, p);
  if (Math.abs(det) < 1e-12) return -1;
  const s = sub(o, a), u = dot(s, p) / det;
  if (u < 0 || u > 1) return -1;
  const q = cross(s, e1), v = dot(d, q) / det;
  if (v < 0 || u + v > 1) return -1;
  return dot(e2, q) / det;
}

// Whether a ray from `o` along `d` leaves the grid without meeting a face
// other than `self` (3D DDA through the cells).
function escapes(g, triangles, o, d, self) {
  const { low, size, cell, cells } = g;
  const at = [0, 1, 2].map(k => Math.floor((o[k] - low[k]) / cell));
  if (at.some((v, k) => v < 0 || v >= size[k])) return true;
  const step = d.map(v => (v > 0 ? 1 : v < 0 ? -1 : 0));
  const next = [0, 1, 2].map(k => d[k] === 0 ? Infinity : ((at[k] + (d[k] > 0 ? 1 : 0)) * cell + low[k] - o[k]) / d[k]);
  const delta = d.map(v => (v === 0 ? Infinity : cell / Math.abs(v)));
  const tested = new Set();
  for (;;) {
    const list = cells.get((at[2] * size[1] + at[1]) * size[0] + at[0]);
    if (list) for (const i of list) {
      if (i === self || tested.has(i)) continue;
      tested.add(i);
      if (hit(o, d, triangles[i].points) > 1e-4) return false;
    }
    const k = next[0] < next[1] ? (next[0] < next[2] ? 0 : 2) : (next[1] < next[2] ? 1 : 2);
    at[k] += step[k];
    if (at[k] < 0 || at[k] >= size[k]) return true;
    next[k] += delta[k];
  }
}

// How much more open air a face's front sees than its back (rays, by area).
function openness(g, triangles, i) {
  const [a, b, c] = triangles[i].points, n = cross(sub(b, a), sub(c, a)), length = Math.hypot(...n);
  if (length === 0) return 0;
  const unit = n.map(v => v / length), mid = [0, 1, 2].map(k => (a[k] + b[k] + c[k]) / 3);
  let score = 0;
  for (const d of rays) {
    const side = dot(d, unit);
    if (Math.abs(side) < 0.05) continue;
    const o = mid.map((v, k) => v + Math.sign(side) * unit[k] * 0.03);
    if (escapes(g, triangles, o, d, i)) score += side;
  }
  return score * length / 2;
}

const flip = t => { [t.points[1], t.points[2]] = [t.points[2], t.points[1]]; };

// Winds the faces (in place) alike across every edge exactly two of them
// share (`cornerKey` names a corner: faces meet where their keys do), then
// turns each connected piece to its more open side. Returns how many faces
// were turned, how many pieces there are, and the shared edges still wound
// alike (a piece that cannot be wound one way, after simplification).
export function orientConsistent(triangles, cornerKey) {
  const corners = triangles.map(t => t.points.map(cornerKey)), edges = new Map();
  corners.forEach((c, f) => {
    if (new Set(c).size < 3) return;
    for (let k = 0; k < 3; k++) {
      const from = c[k], to = c[(k + 1) % 3], key = from < to ? `${from}|${to}` : `${to}|${from}`;
      if (!edges.has(key)) edges.set(key, []);
      edges.get(key).push({ f, from });
    }
  });
  const next = triangles.map(() => []);
  for (const list of edges.values()) {
    if (list.length !== 2 || list[0].f === list[1].f) continue;
    const same = list[0].from === list[1].from;
    next[list[0].f].push([list[1].f, same]);
    next[list[1].f].push([list[0].f, same]);
  }
  const turn = new Int8Array(triangles.length).fill(-1), piece = new Int32Array(triangles.length).fill(-1);
  let pieces = 0;
  for (let s = 0; s < triangles.length; s++) {
    if (turn[s] >= 0) continue;
    turn[s] = 0; piece[s] = pieces;
    const queue = [s];
    for (let q = 0; q < queue.length; q++) {
      const f = queue[q];
      for (const [g, same] of next[f]) {
        if (turn[g] >= 0) continue;
        turn[g] = turn[f] ^ (same ? 1 : 0); piece[g] = pieces;
        queue.push(g);
      }
    }
    pieces++;
  }
  triangles.forEach((t, f) => { if (turn[f]) flip(t); });
  const g = grid(triangles, 1.5), score = new Float64Array(pieces);
  triangles.forEach((t, f) => { score[piece[f]] += openness(g, triangles, f); });
  let turned = 0;
  triangles.forEach((t, f) => {
    const out = score[piece[f]] < 0;
    if (out) flip(t);
    if (out !== (turn[f] === 1)) turned++;
  });
  // A shared edge both faces still walk the same way.
  let alike = 0;
  for (const list of edges.values()) {
    if (list.length !== 2 || list[0].f === list[1].f) continue;
    const [x, y] = [list[0].from, corners[list[0].f][(corners[list[0].f].indexOf(list[0].from) + 1) % 3]];
    const walks = f => { const c = triangles[f].points.map(cornerKey); return [0, 1, 2].some(k => c[k] === x && c[(k + 1) % 3] === y); };
    if (walks(list[0].f) === walks(list[1].f)) alike++;
  }
  return { turned, pieces, alike };
}
