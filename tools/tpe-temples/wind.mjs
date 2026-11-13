// Decision 725: after simplifying, each face is still wound by its own
// guess (orientOutward's rays, through the source faces under it), so two
// neighbours could disagree and the map, which lights a face by its winding,
// showed one of them dark (the "broken" patches; Map3DBundledModelFilesTests
// counted 21 to 700 such edges per temple). Here the faces are wound alike
// across every edge exactly two of them share (a walk through each connected
// piece), and each piece then faces the sky where nothing stands above it:
// its faces that see straight up (no face above their middle) are turned up
// by area; a piece with none keeps the winding most of its area had voted
// for. Where a piece cannot be wound alike all round (a fold that meets
// itself the other way), one face of each edge still against its neighbour
// is drawn from both sides: a twin wound the other way over the same corners.
//
// Corners are matched by their 32-bit float bits, as the file stores them
// and as the test reads them.

const f32 = new Float32Array(1), u32 = new Uint32Array(f32.buffer);
const bits = v => { f32[0] = v; return u32[0]; };
const cornerKey = p => p.map(bits).join(',');
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const cross = (u, v) => [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
const area = ([a, b, c]) => Math.hypot(...cross(sub(b, a), sub(c, a))) / 2;
const upward = ([a, b, c]) => { const n = cross(sub(b, a), sub(c, a)); return n[2] / (Math.hypot(...n) || 1); };

// Whether any face other than `self` lies above `o` (a vertical ray up),
// through a grid of the faces' footprints, `cell` metres.
function skyTest(triangles, cell = 2) {
  const cells = new Map(), key = (x, y) => `${x},${y}`;
  triangles.forEach((t, i) => {
    const xs = t.points.map(p => p[0]), ys = t.points.map(p => p[1]);
    for (let x = Math.floor(Math.min(...xs) / cell); x <= Math.floor(Math.max(...xs) / cell); x++)
      for (let y = Math.floor(Math.min(...ys) / cell); y <= Math.floor(Math.max(...ys) / cell); y++) {
        if (!cells.has(key(x, y))) cells.set(key(x, y), []);
        cells.get(key(x, y)).push(i);
      }
  });
  const side = (p, q, r) => (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]);
  return (o, self) => (cells.get(key(Math.floor(o[0] / cell), Math.floor(o[1] / cell))) ?? []).some(i => {
    if (i === self) return false;
    const [a, b, c] = triangles[i].points, whole = side(a, b, c);
    if (Math.abs(whole) < 1e-9) return false;
    const u = side(b, c, o) / whole, v = side(c, a, o) / whole, w = 1 - u - v;
    if (u < 0 || v < 0 || w < 0) return false;
    return u * a[2] + v * b[2] + w * c[2] > o[2] + 0.05;
  });
}

// `triangles`: [{ points: [[x,y,z] x3], ... }], changed in place (points
// reordered); twins are appended. Returns { flipped, twins, pieces }.
export function windConsistently(triangles) {
  const keys = triangles.map(t => t.points.map(cornerKey));
  const faceKey = k => [...k].sort().join('|');
  const faceCount = new Map();
  for (const k of keys) faceCount.set(faceKey(k), (faceCount.get(faceKey(k)) ?? 0) + 1);
  const single = keys.map(k => faceCount.get(faceKey(k)) === 1);
  // Each edge: the faces walking it, and which way (from the lower key).
  const edges = new Map();
  keys.forEach((k, i) => {
    if (!single[i]) return;
    for (let e = 0; e < 3; e++) {
      const a = k[e], b = k[(e + 1) % 3], key = a < b ? `${a}/${b}` : `${b}/${a}`;
      if (!edges.has(key)) edges.set(key, []);
      edges.get(key).push({ face: i, forward: a < b });
    }
  });
  const neighbours = triangles.map(() => []);
  for (const walks of edges.values()) {
    if (walks.length !== 2) continue;
    const [x, y] = walks;
    // Wound alike across the edge when they walk it opposite ways.
    neighbours[x.face].push({ face: y.face, same: x.forward !== y.forward });
    neighbours[y.face].push({ face: x.face, same: x.forward !== y.forward });
  }
  // flip[i]: whether face i turns round, relative to how it came.
  const flip = new Array(triangles.length).fill(null);
  const covered = skyTest(triangles);
  let pieces = 0, flipped = 0;
  for (let start = 0; start < triangles.length; start++) {
    if (flip[start] !== null || !single[start]) continue;
    pieces++;
    const piece = [start];
    flip[start] = false;
    for (let at = 0; at < piece.length; at++) {
      const i = piece[at];
      for (const n of neighbours[i]) {
        if (flip[n.face] !== null) continue;
        // Same winding now: keep the same relative turn; else the opposite.
        flip[n.face] = n.same ? flip[i] : !flip[i];
        piece.push(n.face);
      }
    }
    // Faces open to the sky face up; else the piece keeps the winding
    // most of its area voted for.
    let against = 0, total = 0, skyUp = 0, skyDown = 0;
    for (const i of piece) {
      const p = triangles[i].points, w = area(p), z = upward(p) * (flip[i] ? -1 : 1);
      total += w;
      if (flip[i]) against += w;
      if (Math.abs(z) >= 0.3 && !covered(p.reduce((m, q) => m.map((v, k) => v + q[k] / 3), [0, 0, 0]), i)) {
        if (z > 0) skyUp += w; else skyDown += w;
      }
    }
    const invert = skyUp + skyDown > 0 ? skyDown > skyUp : against > total / 2;
    for (const i of piece) {
      if (invert) flip[i] = !flip[i];
      if (flip[i]) { const p = triangles[i].points; [p[1], p[2]] = [p[2], p[1]]; flipped++; }
    }
  }
  // Edges still wound alike: draw the smaller face from both sides.
  const now = triangles.map(t => t.points.map(cornerKey));
  const twinned = new Set();
  for (const walks of edges.values()) {
    if (walks.length !== 2) continue;
    const [x, y] = walks.map(w => w.face);
    if (twinned.has(x) || twinned.has(y)) continue;
    const dir = (i) => {
      const k = now[i];
      for (let e = 0; e < 3; e++) {
        const a = k[e], b = k[(e + 1) % 3];
        const key = a < b ? `${a}/${b}` : `${b}/${a}`;
        if (edges.get(key) === walks) return a < b;
      }
      throw new Error('edge not on its face');
    };
    if (dir(x) !== dir(y)) continue;
    twinned.add(area(triangles[x].points) <= area(triangles[y].points) ? x : y);
  }
  for (const i of [...twinned].sort((a, b) => a - b)) {
    const t = triangles[i];
    triangles.push({ ...t, points: [t.points[0], t.points[2], t.points[1]] });
  }
  return { flipped, twins: twinned.size, pieces };
}
