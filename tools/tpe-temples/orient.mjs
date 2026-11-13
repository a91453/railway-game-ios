// Decision 725: SketchUp's faces are wound either way (a face's back is
// often the one outside), and the game lights a face by its winding. Each
// face here is turned to whichever of its two sides sees more of the open
// air: rays from just off each side, in a fixed set of directions at or
// above the horizon (below it is ground), counted when they leave the
// model without meeting another face. Two faces over the same three corners
// (a face and its back, both exported) keep only the first.

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

// Turns each face (in place) to face its more open side. Returns how many
// were turned.
export function orientOutward(triangles) {
  const g = grid(triangles, 1.5);
  let turned = 0;
  triangles.forEach((t, i) => {
    const [a, b, c] = t.points, n = cross(sub(b, a), sub(c, a)), length = Math.hypot(...n);
    if (length === 0) return;
    const unit = n.map(v => v / length), mid = [0, 1, 2].map(k => (a[k] + b[k] + c[k]) / 3);
    let front = 0, back = 0;
    for (const d of rays) {
      const side = dot(d, unit);
      if (Math.abs(side) < 0.05) continue;
      const o = mid.map((v, k) => v + Math.sign(side) * unit[k] * 0.03);
      if (escapes(g, triangles, o, d, i)) { if (side > 0) front += Math.abs(side); else back += Math.abs(side); }
    }
    if (back > front) { [t.points[1], t.points[2]] = [t.points[2], t.points[1]]; turned++; }
  });
  return turned;
}
