"""Decision 408: the N700S-G's cars from the author's own mesh, fewer triangles.

Reads the author's native models from a checkout of the private reference
repository (never copied into this repository), welds each car's triangles,
takes it down to its budget with quadric edge collapses that keep every
colour boundary (the dark green lines, the windows, the doors) where it is,
puts it into the game's units and heights, gives each colour its palette
entry and writes Sources/GamePresentation/Map3DN700SGMesh.swift.

    python3 -I tools/hsr-trains-408/decimate.py \
        <checkout>/Railway/n700s-n700st-2026-10-24/n700s-g/models \
        Sources/GamePresentation/Map3DN700SGMesh.swift

Needs NumPy (BSD), in a scratchpad virtual environment; nothing else.
"""
import base64, hashlib, heapq, struct, sys
import numpy as np

# The cars the game draws: A the cab (its back turned round for the tail),
# C between, D under the pantographs; each budget and whether the error is
# weighed by area (the cab's nose and wheels keep their shape better without:
# small curved parts then cost as much as large flat ones).
UNITS = [("a", 6000, False), ("c", 5000, True), ("d", 5000, True)]

# The author's colours (#RRGGBB) onto the palette's, by index into
# Map3DN700SG.meshPalette.
PALETTE = ["body", "line", "glass", "skirt", "door", "roof", "wheel", "under", "lamp"]
COLOURS = {
    0xF6F6F4: "body", 0x1D4A44: "line", 0x26313D: "glass", 0x8F959B: "skirt",
    0x5D6670: "door", 0x5B6269: "door", 0xC5C9CD: "roof", 0x2B3139: "wheel",
    0x494E55: "under", 0x41474F: "under", 0xFFF4D6: "lamp",
}


def read(path):
    """The triangles (n, 3, 3) and each one's colour (#RRGGBB) of an M3DM file."""
    data = open(path, "rb").read()
    assert data[:4] == b"M3DM" and struct.unpack_from("<HH", data, 4) == (1, 0), path
    count, meta = struct.unpack_from("<II", data, 8)
    corner = [("x", "<f4"), ("y", "<f4"), ("z", "<f4"), ("c", "<u4")]
    rows = np.frombuffer(data, np.dtype([("f", "<u4"), ("p", corner, (3,))]), count, 16 + (meta + 3) // 4 * 4)
    points = np.stack([rows["p"]["x"], rows["p"]["y"], rows["p"]["z"]], -1).astype(np.float64)
    abgr = rows["p"]["c"][:, 0].astype(np.int64)
    rgb = (abgr & 255) << 16 | (abgr >> 8 & 255) << 8 | (abgr >> 16 & 255)
    return points, rgb


def weld(points, step=1e-4):
    """Shared vertices for corners within `step` of each other."""
    flat = points.reshape(-1, 3)
    keys, index = np.unique(np.round(flat / step).astype(np.int64), axis=0, return_inverse=True)
    vertices = np.zeros((len(keys), 3))
    np.add.at(vertices, index, flat)
    vertices /= np.bincount(index)[:, None]
    return vertices, index.reshape(-1, 3)


def simplify(vertices, triangles, colours, target, area_weight, seam_weight=50.0):
    """Half-edge collapses, cheapest first (Garland and Heckbert's quadrics),
    until `target` triangles are left. A vertex on a colour boundary only
    slides along it, to a neighbour on the same boundary; where boundaries
    meet it stays. A collapse that would turn a triangle over (or nearly
    flat), or join two surfaces, is not made."""
    V = vertices
    faces = [list(t) for t in triangles]
    colour = list(colours)
    alive = [True] * len(faces)
    around = [set() for _ in V]
    for i, f in enumerate(faces):
        for v in f:
            around[v].add(i)
    Q = np.zeros((len(V), 4, 4))

    def plane(f):
        a, b, c = V[f[0]], V[f[1]], V[f[2]]
        n = np.cross(b - a, c - a)
        size = np.linalg.norm(n)
        if size < 1e-12:
            return None, 0.0
        n /= size
        return np.append(n, -n @ a), size / 2

    def shared(u, v):
        return around[u] & around[v]

    def boundary(u, v):
        fs = shared(u, v)
        return len(fs) != 2 or len({colour[i] for i in fs}) > 1

    for f in faces:
        p, area = plane(f)
        if p is not None:
            K = np.outer(p, p) * (area if area_weight else 1.0)
            for v in f:
                Q[v] += K
    # A plane through each boundary edge, upright on its triangles, holds
    # the boundary in place.
    done = set()
    for f in faces:
        for k in range(3):
            u, v = f[k], f[(k + 1) % 3]
            if (min(u, v), max(u, v)) in done or not boundary(u, v):
                continue
            done.add((min(u, v), max(u, v)))
            d = V[v] - V[u]
            length = np.linalg.norm(d)
            if length < 1e-12:
                continue
            for j in sorted(shared(u, v)):
                p, _ = plane(faces[j])
                if p is None:
                    continue
                m = np.cross(d / length, p[:3])
                m /= np.linalg.norm(m) or 1.0
                c = np.append(m, -m @ V[u])
                K = np.outer(c, c) * (length * length if area_weight else 1.0) * seam_weight
                Q[u] += K
                Q[v] += K

    def neighbours(u):
        out = set()
        for i in around[u]:
            out.update(faces[i])
        out.discard(u)
        return out

    def kind(u):
        edges = [w for w in neighbours(u) if boundary(u, w)]
        if not edges:
            return "inside", edges
        if len(edges) == 2 and len({colour[i] for i in around[u]}) <= 2:
            return "boundary", edges
        return "corner", edges

    def valid(u, v):
        k, along = kind(u)
        if k == "corner" or (k == "boundary" and v not in along):
            return False
        both = shared(u, v)
        if not both:
            return False
        opposite = set().union(*(faces[i] for i in both)) - {u, v}
        if neighbours(u) & neighbours(v) != opposite:
            return False
        for i in around[u] - both:
            f = faces[i]
            g = [v if x == u else x for x in f]
            n0 = np.cross(V[f[1]] - V[f[0]], V[f[2]] - V[f[0]])
            n1 = np.cross(V[g[1]] - V[g[0]], V[g[2]] - V[g[0]])
            l0, l1 = np.linalg.norm(n0), np.linalg.norm(n1)
            if l1 < 1e-10 or (l0 > 1e-12 and n0 @ n1 / (l0 * l1) < 0.5):
                return False
            longest = max(np.linalg.norm(V[g[1]] - V[g[0]]), np.linalg.norm(V[g[2]] - V[g[1]]), np.linalg.norm(V[g[0]] - V[g[2]]))
            if l1 / (longest * longest) < 0.02:
                return False
        return True

    version = [0] * len(V)
    heap = []

    def push(u):
        for v in sorted(neighbours(u)):
            p = np.append(V[v], 1.0)
            heapq.heappush(heap, (float(p @ (Q[u] + Q[v]) @ p), u, v, version[u], version[v]))

    for u in range(len(V)):
        if around[u]:
            push(u)
    count = len(faces)
    while count > target and heap:
        _, u, v, vu, vv = heapq.heappop(heap)
        if version[u] != vu or version[v] != vv or not around[u] or not around[v] or not valid(u, v):
            continue
        for i in shared(u, v):
            alive[i] = False
            for x in faces[i]:
                around[x].discard(i)
            count -= 1
        for i in sorted(around[u]):
            faces[i] = [v if x == u else x for x in faces[i]]
            around[v].add(i)
        around[u] = set()
        Q[v] += Q[u]
        ring = neighbours(v)
        for w in [u, v, *ring]:
            version[w] += 1
        push(v)
        for w in sorted(ring):
            push(w)
    kept = [i for i in range(len(faces)) if alive[i]]
    return [faces[i] for i in kept], [colour[i] for i in kept]


def game_point(p):
    """The author's units in metres (decision 408): ×1.22 along and across;
    up, the skirt (0.74) onto 0.62 m and the roof (4.02) onto 3.65 m, the
    wheels below the skirt squeezed onto the rail rather than through it."""
    x, y, z = p
    up = z * 0.62 / 0.74 if z < 0.74 else 0.62 + (z - 0.74) * 0.924
    return x * 1.22, y * 1.22, up


def encode(vertices, faces, colours):
    """Little-endian: the vertex count (UInt16), each vertex x, y, z in
    millimetres (Int16); the triangle count (UInt16), each triangle's three
    vertex indices (UInt16) and its palette index (UInt8)."""
    used = sorted({v for f in faces for v in f})
    new = {v: i for i, v in enumerate(used)}
    out = bytearray(struct.pack("<H", len(used)))
    for v in used:
        out += struct.pack("<hhh", *(int(round(c * 1000)) for c in game_point(vertices[v])))
    out += struct.pack("<H", len(faces))
    for f, c in zip(faces, colours):
        out += struct.pack("<HHHB", *(new[v] for v in f), PALETTE.index(COLOURS[c]))
    return bytes(out)


def main(models, output):
    blobs, notes = {}, []
    for unit, target, area_weight in UNITS:
        path = f"{models}/railway-n700s-g-{unit}.m3dmodel"
        points, colours = read(path)
        unknown = set(colours.tolist()) - set(COLOURS)
        assert not unknown, f"{unit}: colours with no palette entry {sorted(map(hex, unknown))}"
        vertices, triangles = weld(points)
        faces, kept = simplify(vertices, triangles, colours.tolist(), target, area_weight)
        blobs[unit] = encode(vertices, faces, kept)
        source = hashlib.sha256(open(path, "rb").read()).hexdigest()
        notes.append(f"//   {unit.upper()}: {len(points):,} triangles -> {len(faces):,} (source SHA-256 {source[:16]}...)")
        print(unit, len(points), "->", len(faces))
    lines = [
        "// Generated by tools/hsr-trains-408/decimate.py from the author's own",
        "// N700S-G (the reference repository's Railway/n700s-n700st-2026-10-24/",
        "// n700s-g/models/, #1214), with the author's consent. Do not edit: run",
        "// the tool again (tools/hsr-trains-408/README.md).",
        *notes,
        "",
        "extension Map3DN700SG {",
        "    /// Each unit's mesh: base64 of ``decodedMesh(_:)``'s bytes.",
        "    static let encodedMeshes: [Unit: String] = [",
    ]
    for unit, blob in blobs.items():
        text = base64.b64encode(blob).decode()
        lines.append(f"        .{unit}: \"\"\"")
        lines += ["        " + text[i:i + 100] for i in range(0, len(text), 100)]
        lines.append("        \"\"\",")
    lines += ["    ]", "}", ""]
    open(output, "w").write("\n".join(lines))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
