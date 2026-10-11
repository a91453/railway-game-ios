# Builds a city-view train as a real game asset: modelled, unwrapped twice, with its ambient
# occlusion baked, and exported as one GLB.
#
#   pip install bpy                     # Blender as a Python module; CPU only, no GPU needed
#   python3 -I tools/trains/build_train.py n700st-cab n700st-car
#
# WHY THIS EXISTS, AND WHAT IT SHARES WITH THE CODE. Drawing a vehicle procedurally in
# src/world/trains.js gets the livery right — a band at a given height is a stripe painted on a
# canvas, which is the one thing diffusion texturing could not do — and the shape acceptable. What it
# cannot get is the other half of why a game vehicle looks like one: surfaces that stand off the body
# rather than being painted onto it, and the occlusion that collects around them. Blender does that
# half, and the two halves are merged rather than chosen between.
#
# The shape is the same loft as trains.js (shellRing there, ring() here). The car is then unwrapped
# twice, because the two textures want opposite things:
#
#   UV0, "UVMap"  the coordinates trains.js paints in — along the car, and how high up its own
#                 section a point sits. Both flanks share them, which is what makes one painted
#                 canvas serve the whole car, and means the livery lands where the painter put it.
#   UV1, "AO"     a packed unwrap where every face has its own texels, which is what a bake needs:
#                 the body behind a window plate is nearly black and the plate itself is not, and on
#                 UV0 they are the same texel. Three.js reads this one through `aoMap`.
#
# Nothing here paints colour at all.
import json
import math
import os
import sys

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# ---------------------------------------------------------------- the trains
# Metres above the rail, nose towards +X (the city view's default `front`). Dimensions carry their
# source; see .claude/skills/rolling-stock/SKILL.md for where each number comes from. `length` is the
# car body, which is the stock's length in trains.js less the 0.6 m gap between cars.
STOCK = {
    "n700st-cab": {
        "name": "THSR N700ST cab car",
        "length": 24.4, "nose": 9.0,
        "shell": {"halfW": 1.45, "floor": 0.62, "roof": 3.75, "drop": 1.78, "lift": 0.1,
                  "tuck": 0.34, "cap": 0.56, "wing": 0.05, "shoulder": 0.66},
        "window": {"from": 0.555, "to": 0.780, "pitch": 1.0, "width": 0.50},
        "door": {"width": 0.85},
        "skirtTop": 0.28, "screen": True,
    },
    "n700st-car": {
        "name": "THSR N700ST intermediate car",
        "length": 24.4, "nose": 0.0,
        "shell": {"halfW": 1.45, "floor": 0.62, "roof": 3.75, "drop": 1.78, "lift": 0.1,
                  "tuck": 0.34, "cap": 0.56, "wing": 0.05, "shoulder": 0.66},
        "window": {"from": 0.555, "to": 0.780, "pitch": 1.0, "width": 0.50},
        "door": {"width": 0.85},
        "skirtTop": 0.28, "screen": False,
    },
}

RING, NOSE_RINGS = 28, 22
# The body rings are a straight prism, but one long quad shades poorly and gives the bake nothing to
# work with, so the body is cut into sections about the size of the nose's.
BODY_STEP = 1.2

# Which part of the livery a face takes. SIDE is the swept surface and everything standing on it, and
# is unwrapped into the painter's side strip; the kit over and under the body takes one plain swatch,
# exactly as the procedural geometry in trains.js does.
SIDE, ROOF, UNDER, SCREEN = "side", "roof", "under", "screen"


def ease(x):
    t = min(1.0, max(0.0, x))
    return t * t * (3 - 2 * t)


def section(t, sh):
    """The numbers that define one ring: the half width, the top and bottom of the section, how much
    the end is rounded over, and the two exponents that make it fuller below the crease than above."""
    half_w = sh["halfW"] * (1 - sh["tuck"] * ease((t - 0.45) / 0.55))
    top = sh["roof"] - sh["drop"] * ease(t)
    bottom = sh["floor"] + sh["lift"] * ease((t - 0.6) / 0.4)
    cap = 1 - sh["cap"] * ease((t - 0.88) / 0.12)
    return half_w, top, bottom, cap, 2 / (8.5 - 5.6 * ease(t)), 2 / (4.6 - 2.3 * ease(t))


def ring(x, t, sh):
    """One ring of the shell at `x` along the car, `t` along the nose. Mirrors shellRing in
    trains.js so the silhouette stays the one already reviewed. Returns (y, z, f) per point, with f
    how high the point sits within its own ring — which is what the livery is measured in."""
    half_w, top, bottom, cap, low, up = section(t, sh)
    cz, hz = (top + bottom) / 2, ((top - bottom) / 2) * cap
    pts = []
    for k in range(RING):
        a = -math.pi / 2 + (2 * math.pi * k) / RING
        c, s = math.cos(a), math.sin(a)
        z = cz + math.copysign(abs(s) ** (low if s < 0 else up), s) * hz
        f = (z - bottom) / (top - bottom)
        wing = 1 + sh["wing"] * math.exp(-(((f - sh["shoulder"]) / 0.1) ** 2))
        y = math.copysign(abs(c) ** low, c) * half_w * wing * cap
        pts.append((y, z, f))
    return pts


def flank(t, sh, f):
    """How far out the shell's flank stands at height f, in metres from the centre line. Anything that
    has to sit ON the body — a window plate, a door leaf — is placed from this rather than from the
    half width, because the section is widest at the crease and tucks in above it: a plate placed at
    the half width would sink inside the body over part of its height and vanish."""
    half_w, top, bottom, cap, low, up = section(t, sh)
    cz, hz = (top + bottom) / 2, ((top - bottom) / 2) * cap
    z = bottom + f * (top - bottom)
    q = 0.0 if hz == 0 else (z - cz) / hz
    s = math.copysign(min(1.0, abs(q)) ** (1 / (low if q < 0 else up)), q)
    c = math.sqrt(max(0.0, 1 - s * s))
    wing = 1 + sh["wing"] * math.exp(-(((f - sh["shoulder"]) / 0.1) ** 2))
    return c ** low * half_w * wing * cap


def build(spec):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sh, half, nose = spec["shell"], spec["length"] / 2, spec["nose"]

    body_end = half - nose if nose else half
    steps = max(1, round((body_end + half) / BODY_STEP))
    xs = [(-half + (body_end + half) * i / steps, 0.0) for i in range(steps + 1)]
    if nose:
        xs += [(body_end + nose * i / NOSE_RINGS, i / NOSE_RINGS) for i in range(1, NOSE_RINGS + 1)]
    rings = [(x, ring(x, t, sh)) for x, t in xs]

    verts, faces, kind = [], [], []
    for x, pts in rings:
        for (y, z, _f) in pts:
            verts.append((x, y, z))
    # The top of the nose is its own chart when this stock has a windscreen (see NOSE below), so its
    # quads are told apart here and unwrapped differently; the rest of the sweep is unchanged.
    k0, k1 = RING // 2 - NOSE_ACROSS, RING // 2 + NOSE_ACROSS
    for i in range(len(rings) - 1):
        for k in range(RING):
            a, b = i * RING + k, i * RING + (k + 1) % RING
            faces.append((a, b, b + RING, a + RING))
            kind.append(SCREEN if (spec["screen"] and steps <= i < steps + NOSE_RINGS
                                   and k0 <= k < k1) else SIDE)
    # the flat rear end and the small face at the tip
    for idx, front in ((0, False), (len(rings) - 1, True)):
        x, pts = rings[idx]
        centre = len(verts)
        verts.append((x, sum(p[0] for p in pts) / RING, sum(p[1] for p in pts) / RING))
        for k in range(RING):
            a, b = idx * RING + k, idx * RING + (k + 1) % RING
            faces.append((centre, a, b) if front else (centre, b, a))
            kind.append(SIDE)
    return verts, faces, kind, rings, steps


def add_box(verts, faces, kind, cx, cy, cz, sx, sy, sz, where):
    o = len(verts)
    for dx in (-1, 1):
        for dy in (-1, 1):
            for dz in (-1, 1):
                verts.append((cx + dx * sx / 2, cy + dy * sy / 2, cz + dz * sz / 2))
    for f in [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]:
        faces.append(tuple(o + i for i in f))
        kind.append(where)


def add_cylinder(verts, faces, kind, cx, cy, cz, r, w, where, seg=12):
    o = len(verts)
    for side in (-1, 1):
        for k in range(seg):
            a = 2 * math.pi * k / seg
            verts.append((cx + r * math.cos(a), cy + side * w / 2, cz + r * math.sin(a)))
    for k in range(seg):
        n = (k + 1) % seg
        faces.append((o + k, o + n, o + seg + n, o + seg + k)); kind.append(where)
    for side, base in ((0, o), (1, o + seg)):
        c = len(verts)
        verts.append((cx, cy + (-1 if side == 0 else 1) * w / 2, cz))
        for k in range(seg):
            n = (k + 1) % seg
            faces.append((c, base + k, base + n) if side else (c, base + n, base + k))
            kind.append(where)


def add_panel(verts, faces, kind, spec, left, side, f0, f1, length, proud, rows):
    """A panel standing on the flank: a bonded window unit, a plug door leaf. `left` is its near edge
    in metres from the car's rear end, and it stands `proud` metres off the shell, which is what gives
    the bake a contact shadow to lay around it — the recess the first version of this cut inward
    instead was simply inside a closed body, and invisible.

    It follows the flank in `rows` steps rather than being a flat box. The section is widest at the
    crease and tucks in towards the roof, so a box placed at the widest point stands 19 cm off the
    body at the top of a door and reads as a slab hung crookedly on the side."""
    sh = spec["shell"]
    _half_w, top, bottom, _cap, _low, _up = section(0.0, sh)
    x0 = -spec["length"] / 2 + left
    x1 = x0 + length
    o = len(verts)
    for r in range(rows + 1):
        f = f0 + (f1 - f0) * r / rows
        z = bottom + f * (top - bottom)
        out = flank(0.0, sh, f)
        for y in (out + proud, out):                      # the face, then where it meets the body
            for x in (x0, x1):
                verts.append((x, side * y, z))
    # Wound for the +y flank; the other side is the mirror of it, so its faces are reversed.
    def quad(*ix):
        f = tuple(o + i for i in ix)
        faces.append(f if side > 0 else f[::-1])
        kind.append(SIDE)
    for r in range(rows):
        p, q = r * 4, (r + 1) * 4                          # p: this row, q: the one above
        quad(p, q, q + 1, p + 1)                           # the face
        quad(p + 2, q + 2, q, p)                           # the rim at the near end
        quad(p + 1, q + 1, q + 3, p + 3)                   # and at the far end
    t = rows * 4
    quad(1, 3, 2, 0)                                       # the rim along the bottom
    quad(t, t + 2, t + 3, t + 1)                           # and along the top


def layout(spec):
    """Where the doors and the windows go, in metres from the car body's rear end. These are the
    painter's own numbers — doorsOf and carWindows in trains.js — because a plate has to land on the
    paint, not near it. A cab car's painted side stops where the nose begins."""
    span = spec["length"] - spec["nose"]
    dw, w = spec["door"]["width"], spec["window"]
    doors = [1.3, span - 1.3 - dw]
    panes, x = [], doors[0] + dw + w["pitch"] * 0.6
    while x + w["width"] < doors[1] - w["pitch"] * 0.3:
        panes.append(x)
        x += w["pitch"]
    return doors, panes


def furnish(spec, verts, faces, kind):
    """The kit: window units and door leaves standing on the side, bogies with wheels, the roof run.
    These are what the occlusion bake bites on — a bare swept tube bakes to almost nothing — and
    because they are unwrapped by the same analytic mapping as the shell, the painter's pane lands on
    the pane and its door leaf on the leaf.

    Nothing stands on the nose. A plate follows a flank, which is nearly flat, but a box sitting on a
    doubly curved surface cannot follow it: six of them along the N700ST's bill read as a staircase,
    which is worse than the canopy the painter already draws there."""
    sh, half, nose = spec["shell"], spec["length"] / 2, spec["nose"]
    body_from, body_to = -half + 1.2, (half - nose + 1.4) if nose else half - 1.2
    doors, panes = layout(spec)
    w = spec["window"]
    for side in (-1, 1):
        for d in doors:                                   # a plug door leaf, standing a little proud
            add_panel(verts, faces, kind, spec, d, side, spec["skirtTop"], 0.94,
                      spec["door"]["width"], 0.012, 5)
        for x in panes:
            add_panel(verts, faces, kind, spec, x, side, w["from"], w["to"], w["width"], 0.022, 3)
    for x in (body_from + 2.6, body_to - 2.6):            # bogies and their wheels
        add_box(verts, faces, kind, x, 0, 0.62, 2.9, 2.1, 0.42, UNDER)
        for wx in (x - 1.15, x + 1.15):
            for wy in (-1.06, 1.06):
                add_cylinder(verts, faces, kind, wx, wy, 0.43, 0.43, 0.14, UNDER)
    add_box(verts, faces, kind, (body_from + body_to) / 2, 0, 0.42, body_to - body_from, 2.2, 0.45, UNDER)
    # The air-conditioning run and its ducts. On a cab car they stop short of the nose: a box left on
    # the crown is the first thing a head-on view meets, and the real roof there is smooth.
    run_from = body_from + 0.6
    run_to = (half - nose - 1.0) if nose else body_to - 0.6
    units = max(2, round((run_to - run_from) / 3.2))
    for i in range(units):
        x = run_from + (run_to - run_from) * (i + 0.5) / units
        add_box(verts, faces, kind, x, 0, sh["roof"] + 0.08, 2.1, 1.9, 0.26, ROOF)
    for y in (-0.95, 0.95):
        add_box(verts, faces, kind, (run_from + run_to) / 2, y, sh["roof"] + 0.04,
                run_to - run_from, 0.26, 0.14, ROOF)


def make_object(spec, verts, faces, kind):
    mesh = bpy.data.meshes.new(spec["name"])
    mesh.from_pydata(verts, [], faces)
    ob = bpy.data.objects.new(spec["name"], mesh)
    bpy.context.collection.objects.link(ob)
    # The swept surface is one smooth form; the kit is made of boxes and wants its edges.
    for i, poly in enumerate(mesh.polygons):
        poly.use_smooth = kind[i] in (SIDE, SCREEN)
    mesh.validate()
    return ob


# ------------------------------------------------------------- the painter's atlas
# TEX_W/TEX_H/SIDE_Y0/SIDE_Y1 are trains.js's. UV0 is written in the coordinates the canvas is painted
# in, so the livery comes from the painter — where a band is a smooth stripe at a given height — and
# the model needs no texture of its own. The cab car takes the left half of the side strip and an
# intermediate car the right half, exactly as the procedural geometry does.
TEX_W, TEX_H, SIDE_Y0, SIDE_Y1 = 2048, 512, 16, 256
V_SIDE = (1 - SIDE_Y1 / TEX_H, 1 - SIDE_Y0 / TEX_H)
SWATCH = (1 - SIDE_Y0 / 2 / TEX_H)          # the plain swatches in the top 16 px
SWATCH_U = {ROOF: 0.25, UNDER: 0.75}        # as plainUv is called in trains.js
# The nose's own chart, laid out along the nose and across it: NOSE in trains.js, same numbers. A
# windscreen painted at a height instead goes right round the ring and comes out as a visor.
NOSE_X0, NOSE_X1, NOSE_Y0, NOSE_Y1, NOSE_ACROSS = 16, 1456, 264, 504, 3


def written(u, v):
    """A UV as it must be stored in Blender to arrive in trains.js as (u, v).

    glTF measures v from the top of the image and Blender from the bottom, so the exporter writes
    1 - v; the canvas texture on the other side is a CanvasTexture, which three.js uploads flipped,
    so its v is measured from the bottom again. The two conventions cancel to one flip, and this is
    it. Writing v straight through instead puts the whole livery half a picture out — the train comes
    out plain white, which reads as a missing texture rather than as a wrong coordinate."""
    return (u, 1 - v)


def nose_uv(along, across):
    return ((NOSE_X0 + along * (NOSE_X1 - NOSE_X0)) / TEX_W,
            1 - (NOSE_Y0 + across * (NOSE_Y1 - NOSE_Y0)) / TEX_H)


def unwrap(ob, spec, kind, rings, nose_from):
    """UV0 by hand, UV1 by projection. The side's coordinates are the painter's and may not move, and
    a car body is a swept surface, so it already has them: along the car, and how high up its own
    section a point sits. A projection would scatter the same surface into arbitrary islands and the
    livery would land anywhere. The bake wants the opposite — every face its own texels — so it gets
    its own layer, where a projection is exactly right."""
    half, L, sh = spec["length"] / 2, spec["length"], spec["shell"]
    u0 = 0.0 if spec["nose"] > 0 else 0.5
    mesh = ob.data
    mesh.uv_layers.new(name="UVMap")
    mesh.uv_layers.new(name="AO")
    project(ob, "AO")
    uv = mesh.uv_layers["UVMap"]            # looked up again: a trip through edit mode moves it
    k0 = RING // 2 - NOSE_ACROSS
    for poly in mesh.polygons:
        where = kind[poly.index]
        for li in poly.loop_indices:
            vi = mesh.loops[li].vertex_index
            if where == SCREEN:
                # A shell vertex's place in the sweep is its index: the rings were laid in order.
                # `across` is the point's own lateral position over the band's half width, so the
                # chart is a view from above; the ring index is not, because a superellipse keeps
                # the top nearly flat and crowds its points towards the flanks.
                i, k = vi // RING, vi % RING
                pts = rings[i][1]
                uv.data[li].uv = written(*nose_uv((i - nose_from) / NOSE_RINGS,
                                                  0.5 - 0.5 * pts[k][0] / pts[k0][0]))
                continue
            if where != SIDE:
                uv.data[li].uv = written(SWATCH_U[where], SWATCH)
                continue
            v = mesh.vertices[vi].co
            along = u0 + 0.004 + ((v.x + half) / L) * 0.492
            f = (v.z - sh["floor"]) / (sh["roof"] - sh["floor"])
            uv.data[li].uv = written(min(1, max(0, along)),
                                     V_SIDE[0] + (V_SIDE[1] - V_SIDE[0]) * min(1, max(0, f)))
    audit(mesh, kind, u0)
    mesh.uv_layers.active = mesh.uv_layers["AO"]   # what the bake writes into


def project(ob, layer):
    """Pack every face into one layer, each with its own texels."""
    mesh = ob.data
    mesh.uv_layers.active = mesh.uv_layers[layer]
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.012,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def audit(mesh, kind, u0):
    """Every side loop inside the side strip and inside this car's own half of it. Without this, the
    first version of the unwrap scattered the whole body across the picture and the result still
    rendered: a livery landing in the wrong place is not something a render reads as a defect."""
    uv = mesh.uv_layers["UVMap"]
    strips = {SIDE: (V_SIDE, (u0, u0 + 0.5)),
              SCREEN: ((1 - NOSE_Y1 / TEX_H, 1 - NOSE_Y0 / TEX_H), (NOSE_X0 / TEX_W, NOSE_X1 / TEX_W))}
    bad = 0
    for poly in mesh.polygons:
        want = strips.get(kind[poly.index])
        if want is None:
            continue
        (lo, hi), (ulo, uhi) = want
        for li in poly.loop_indices:
            u, v = uv.data[li].uv
            v = 1 - v                                     # back into the coordinates trains.js uses
            if not (lo - 1e-4 <= v <= hi + 1e-4 and ulo - 1e-4 <= u <= uhi + 1e-4):
                bad += 1
    if bad:
        raise SystemExit(f"unwrap: {bad} of {len(mesh.loops)} loops landed outside their strip")


def bake_ao(ob, path, size=512, samples=64, distance=0.8):
    """Occlusion only, into UV1. The colour comes from the painter at run time; what it cannot paint
    is the shadow a window unit lays on the body around it and the dark under the car, and that is
    what this carries. The image starts white so every texel no face claims reads as unoccluded.
    `distance` is how far a surface looks for something to shade it: a car's own flank is 2.9 m from
    the other flank, so a short reach darkens what stands on the body and leaves the paint alone."""
    mat = bpy.data.materials.new("bake")
    mat.use_nodes = True
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    img = bpy.data.images.new("ao", size, size)
    img.generated_color = (1.0, 1.0, 1.0, 1.0)
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    mat.node_tree.nodes.active = node

    scene = bpy.context.scene
    if scene.world is None:
        scene.world = bpy.data.worlds.new("world")
    scene.world.light_settings.distance = distance
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.render.bake.margin = 4
    scene.render.bake.use_clear = False          # keep the white outside the car's own islands
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.bake(type="AO")
    # One channel, eight bits: it is a shadow term, and an RGBA PNG of it is four times the download
    # for nothing. save_render is what reads the scene's image settings; img.save() would not.
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "BW"
    scene.render.image_settings.color_depth = "8"
    scene.render.image_settings.compression = 100
    img.save_render(path, scene=scene)
    return path


def one(which, out_dir):
    spec = STOCK[which]
    verts, faces, kind, rings, nose_from = build(spec)
    furnish(spec, verts, faces, kind)
    ob = make_object(spec, verts, faces, kind)
    unwrap(ob, spec, kind, rings, nose_from)
    ao = bake_ao(ob, os.path.join(out_dir, which + "-ao.png"))
    glb = os.path.join(out_dir, which + ".glb")
    ob.data.materials.clear()
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True,
                              export_apply=True, export_materials="NONE")
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print(f"{which}: {tris} triangles -> {os.path.basename(glb)} "
          f"({os.path.getsize(glb) / 1024:.0f} kB), occlusion -> {os.path.basename(ao)} "
          f"({os.path.getsize(ao) / 1024:.0f} kB)")
    # The city view finds the models, the way each one faces and its occlusion in index.json beside
    # them (src/world/trains.js); `fit` false says the model is already in the game's own metres, so
    # it is turned but never rescaled. Merged, because tools/meshy writes its models into the same file.
    return {"file": which + ".glb", "ao": which + "-ao.png", "front": "+x", "fit": False}


def main():
    names = sys.argv[1:] or list(STOCK)
    out_dir = os.path.join(ROOT, "Web/CityView/public/models/trains")
    os.makedirs(out_dir, exist_ok=True)
    built = {name: one(name, out_dir) for name in names}
    index_file = os.path.join(out_dir, "index.json")
    index = {}
    if os.path.exists(index_file):
        with open(index_file) as fh:
            index = json.load(fh)
    index.update(built)
    with open(index_file, "w") as fh:
        json.dump(index, fh, indent=2, sort_keys=True)
        fh.write("\n")


main()
