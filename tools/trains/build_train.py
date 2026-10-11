# Builds a city-view train as a real game asset: modelled, UV-unwrapped, with its ambient occlusion
# baked into the colour, and exported as one GLB with one material.
#
#   pip install bpy                     # Blender as a Python module; CPU only, no GPU needed
#   python3 -I tools/trains/build_train.py n700st-cab
#
# WHY THIS EXISTS. The city view can draw a train two ways: procedurally in src/world/trains.js, or
# from a GLB listed in public/models/trains/index.json (the loader was built for the Meshy models and
# is the same one here). Procedural code is right for what must vary — buildings from footprints,
# track from OSM ways. A named vehicle does not vary, and drawing it in code throws away the two
# things that actually make a game vehicle look like one: a livery whose boundaries are geometry
# rather than pixels on a stretched atlas, and baked occlusion in every recess and seam.
#
# The shape is the same loft as trains.js (shellRing there, rings() here) so the silhouette the owner
# already approved is preserved; what this adds is recessed windows and doors, and the bake.
import json
import math
import os
import sys

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# ---------------------------------------------------------------- the trains
# Metres above the rail, nose towards +X (the city view's default `front`). Dimensions and colours
# carry their source; see .claude/skills/rolling-stock/SKILL.md for where each kind comes from.
STOCK = {
    "n700st-cab": {
        "name": "THSR N700ST cab car",
        "length": 24.4, "nose": 9.0,
        "shell": {"halfW": 1.45, "floor": 0.62, "roof": 3.75, "drop": 1.78, "lift": 0.1,
                  "tuck": 0.34, "cap": 0.56, "wing": 0.05, "shoulder": 0.66},
        "body": (0.965, 0.965, 0.957),          # the owner's photographs of set TS01
        "bands": [(0.380, 0.500, (0.918, 0.416, 0.118), 0.20),
                  (0.500, 0.566, (0.169, 0.200, 0.337), 0.20)],
        "skirt": (0.561, 0.584, 0.608), "skirtTop": 0.28,
        "glass": (0.106, 0.149, 0.196), "trim": (0.106, 0.125, 0.145),
        "window": {"from": 0.555, "to": 0.780, "pitch": 1.0, "width": 0.50},
        "door": {"width": 0.85, "at": 1.3},
        "canopy": {"from": 1.0, "to": 8.0, "f": 0.74},
        "lamp": {"at": 5.3, "f": 0.52},
    },
    "n700st-car": {
        "name": "THSR N700ST intermediate car",
        "length": 24.4, "nose": 0.0,
        "shell": {"halfW": 1.45, "floor": 0.62, "roof": 3.75, "drop": 1.78, "lift": 0.1,
                  "tuck": 0.34, "cap": 0.56, "wing": 0.05, "shoulder": 0.66},
        "body": (0.965, 0.965, 0.957),
        "bands": [(0.380, 0.500, (0.918, 0.416, 0.118), 0.0),
                  (0.500, 0.566, (0.169, 0.200, 0.337), 0.0)],
        "skirt": (0.561, 0.584, 0.608), "skirtTop": 0.28,
        "glass": (0.106, 0.149, 0.196), "trim": (0.106, 0.125, 0.145),
        "window": {"from": 0.555, "to": 0.780, "pitch": 1.0, "width": 0.50},
        "door": {"width": 0.85, "at": 1.3},
        "canopy": None, "lamp": None,
    },
}

RING, NOSE_RINGS = 28, 22


def ease(x):
    t = min(1.0, max(0.0, x))
    return t * t * (3 - 2 * t)


def ring(x, t, sh):
    """One ring of the shell at `x` along the car, `t` along the nose. Mirrors shellRing in
    trains.js so the silhouette stays the one already reviewed. Returns (y, z, f) per point, with f
    how high the point sits within its own ring — which is what the livery is measured in."""
    half_w = sh["halfW"] * (1 - sh["tuck"] * ease((t - 0.45) / 0.55))
    top = sh["roof"] - sh["drop"] * ease(t)
    bottom = sh["floor"] + sh["lift"] * ease((t - 0.6) / 0.4)
    cap = 1 - sh["cap"] * ease((t - 0.88) / 0.12)
    cz, hz = (top + bottom) / 2, ((top - bottom) / 2) * cap
    low, up = 2 / (8.5 - 5.6 * ease(t)), 2 / (4.6 - 2.3 * ease(t))
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


def band_colour(spec, f, x):
    """The livery colour at height f, at x along the car. A cab car's bands dive towards the nose,
    which here is a shift of the band's own limits rather than a slope painted on a texture."""
    nose, half = spec["nose"], spec["length"] / 2
    dive_t = 0.0
    if nose:
        start = half - nose
        if x > start:
            dive_t = ease((x - start) / nose)
    if f <= spec["skirtTop"]:
        return "skirt"
    for i, (lo, hi, _, dive) in enumerate(spec["bands"]):
        d = dive * dive_t
        if lo - d <= f <= hi - d:
            return "band%d" % i
    return "body"


def build(spec):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sh, half, nose = spec["shell"], spec["length"] / 2, spec["nose"]

    xs = [(-half, 0.0)]
    if nose:
        xs.append((half - nose, 0.0))
        xs += [(half - nose + nose * i / NOSE_RINGS, i / NOSE_RINGS) for i in range(1, NOSE_RINGS + 1)]
    else:
        xs.append((half, 0.0))
    rings = [(x, ring(x, t, sh)) for x, t in xs]

    verts, faces, fcol = [], [], []
    for x, pts in rings:
        for (y, z, _f) in pts:
            verts.append((x, y, z))
    for i in range(len(rings) - 1):
        x_mid = (rings[i][0] + rings[i + 1][0]) / 2
        for k in range(RING):
            a, b = i * RING + k, i * RING + (k + 1) % RING
            faces.append((a, b, b + RING, a + RING))
            f_mid = (rings[i][1][k][2] + rings[i][1][(k + 1) % RING][2]) / 2
            fcol.append(band_colour(spec, f_mid, x_mid))
    # the flat rear end and the small face at the tip
    for idx, front in ((0, False), (len(rings) - 1, True)):
        x, pts = rings[idx]
        centre = len(verts)
        verts.append((x, sum(p[0] for p in pts) / RING, sum(p[1] for p in pts) / RING))
        for k in range(RING):
            a, b = idx * RING + k, idx * RING + (k + 1) % RING
            faces.append((centre, a, b) if front else (centre, b, a))
            fcol.append("body")
    return verts, faces, fcol, rings


def add_box(verts, faces, fcol, cx, cy, cz, sx, sy, sz, colour):
    o = len(verts)
    for dx in (-1, 1):
        for dy in (-1, 1):
            for dz in (-1, 1):
                verts.append((cx + dx * sx / 2, cy + dy * sy / 2, cz + dz * sz / 2))
    q = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for f in q:
        faces.append(tuple(o + i for i in f))
        fcol.append(colour)


def add_cylinder(verts, faces, fcol, cx, cy, cz, r, w, colour, seg=12):
    o = len(verts)
    for side in (-1, 1):
        for k in range(seg):
            a = 2 * math.pi * k / seg
            verts.append((cx + r * math.cos(a), cy + side * w / 2, cz + r * math.sin(a)))
    for k in range(seg):
        n = (k + 1) % seg
        faces.append((o + k, o + n, o + seg + n, o + seg + k)); fcol.append(colour)
    for side, base in ((0, o), (1, o + seg)):
        c = len(verts)
        verts.append((cx, cy + (-1 if side == 0 else 1) * w / 2, cz))
        for k in range(seg):
            n = (k + 1) % seg
            faces.append((c, base + k, base + n) if side else (c, base + n, base + k))
            fcol.append(colour)


def furnish(spec, verts, faces, fcol):
    """The kit: recessed windows and doors, bogies with wheels, the roof run. The recesses are what
    the occlusion bake has to bite on — a flat side bakes to nothing."""
    sh, half, nose = spec["shell"], spec["length"] / 2, spec["nose"]
    body_from, body_to = -half + 1.2, (half - nose + 1.4) if nose else half - 1.2
    w = spec["window"]
    z_lo = sh["floor"] + (sh["roof"] - sh["floor"]) * w["from"]
    z_hi = sh["floor"] + (sh["roof"] - sh["floor"]) * w["to"]
    door_half = spec["door"]["width"] / 2
    doors = [body_from + spec["door"]["at"], body_to - spec["door"]["at"]]
    for side in (-1, 1):
        y = side * (sh["halfW"] - 0.04)
        for d in doors:                                   # a door leaf, sunk into the side
            add_box(verts, faces, fcol, d, y, (z_lo + z_hi) / 2 - 0.35,
                    spec["door"]["width"], 0.1, (z_hi - z_lo) + 1.5, "trim")
        x = doors[0] + door_half + w["pitch"] * 0.8
        while x < doors[1] - door_half - w["pitch"] * 0.5:
            add_box(verts, faces, fcol, x, y, (z_lo + z_hi) / 2, w["width"], 0.12, z_hi - z_lo, "glass")
            x += w["pitch"]
    for x in (body_from + 2.6, body_to - 2.6):            # bogies and their wheels
        add_box(verts, faces, fcol, x, 0, 0.62, 2.9, 2.1, 0.42, "trim")
        for wx in (x - 1.15, x + 1.15):
            for wy in (-1.06, 1.06):
                add_cylinder(verts, faces, fcol, wx, wy, 0.43, 0.43, 0.14, "trim")
    add_box(verts, faces, fcol, (body_from + body_to) / 2, 0, 0.42, body_to - body_from, 2.2, 0.45, "trim")
    run_from, run_to = body_from + 0.6, body_to - 0.6     # the air-conditioning run and its ducts
    units = max(2, round((run_to - run_from) / 3.2))
    for i in range(units):
        x = run_from + (run_to - run_from) * (i + 0.5) / units
        add_box(verts, faces, fcol, x, 0, sh["roof"] + 0.08, 2.1, 1.9, 0.26, "body")
    for y in (-0.95, 0.95):
        add_box(verts, faces, fcol, (run_from + run_to) / 2, y, sh["roof"] + 0.04, run_to - run_from, 0.26, 0.14, "trim")
    if spec["canopy"]:                                    # the cab glazing, as geometry not paint
        c = spec["canopy"]
        for i in range(6):
            t = (i + 0.5) / 6
            x = half - nose + c["from"] + (c["to"] - c["from"]) * t
            r = ring(x, max(0.0, (x - (half - nose)) / nose), sh)
            top = max(p[1] for p in r)
            add_box(verts, faces, fcol, x, 0, top - 0.12, (c["to"] - c["from"]) / 6 + 0.02, 1.9, 0.3, "glass")
    if spec["lamp"]:
        lp = spec["lamp"]
        x = half - nose + lp["at"]
        r = ring(x, (lp["at"]) / nose, sh)
        for side in (-1, 1):
            y = side * max(abs(p[0]) for p in r) * 0.82
            z = sh["floor"] + (sh["roof"] - sh["floor"]) * lp["f"]
            add_box(verts, faces, fcol, x, y, z, 1.1, 0.16, 0.26, "glass")


MATS = ["body", "band0", "band1", "skirt", "glass", "trim"]


def make_object(spec, verts, faces, fcol):
    mesh = bpy.data.meshes.new(spec["name"])
    mesh.from_pydata(verts, [], faces)
    ob = bpy.data.objects.new(spec["name"], mesh)
    bpy.context.collection.objects.link(ob)
    colours = {
        "body": spec["body"], "skirt": spec["skirt"], "glass": spec["glass"], "trim": spec["trim"],
        "band0": spec["bands"][0][2], "band1": spec["bands"][1][2],
    }
    for name in MATS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*colours[name], 1.0)
        bsdf.inputs["Roughness"].default_value = 0.1 if name == "glass" else (0.6 if name == "trim" else 0.25)
        ob.data.materials.append(m)
    # Assign before validate(): validate removes degenerate faces, and doing it the other way round
    # renumbered every polygon after the first removal, which quietly dropped the livery off the body.
    for i, poly in enumerate(mesh.polygons):
        poly.material_index = MATS.index(fcol[i]) if i < len(fcol) else 0
        poly.use_smooth = fcol[i] not in ("trim",) if i < len(fcol) else True
    mesh.validate()
    return ob


def bake_and_export(ob, out_glb, size=1024, samples=24):
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.012)
    bpy.ops.object.mode_set(mode="OBJECT")

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.margin = 8

    def bake(kind, name):
        img = bpy.data.images.new(name, size, size)
        for m in ob.data.materials:
            n = m.node_tree.nodes.new("ShaderNodeTexImage")
            n.image = img
            m.node_tree.nodes.active = n
        bpy.ops.object.bake(type=kind)
        return img

    diffuse = bake("DIFFUSE", "albedo")
    occlusion = bake("AO", "ao")
    px_d, px_a = list(diffuse.pixels), list(occlusion.pixels)
    # Occlusion multiplied into the colour: one texture, one material, and every recess and seam
    # carries its own shadow without a second map or a second UV set (the city view's loader keeps
    # only position, normal and uv, so a separate occlusion map would be dropped anyway).
    for i in range(0, len(px_d), 4):
        ao = 0.35 + 0.65 * px_a[i]
        px_d[i] *= ao; px_d[i + 1] *= ao; px_d[i + 2] *= ao; px_d[i + 3] = 1.0
    baked = bpy.data.images.new("baked", size, size)
    baked.pixels = px_d

    for m in list(ob.data.materials):
        bpy.data.materials.remove(m)
    ob.data.materials.clear()
    final = bpy.data.materials.new("livery")
    final.use_nodes = True
    bsdf = final.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.3
    tex = final.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = baked
    final.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    ob.data.materials.append(final)
    for poly in ob.data.polygons:
        poly.material_index = 0

    os.makedirs(os.path.dirname(out_glb), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out_glb, export_format="GLB", use_selection=True,
                              export_apply=True, export_image_format="AUTO")
    return len(ob.data.polygons)


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "n700st-cab"
    spec = STOCK[which]
    verts, faces, fcol, _rings = build(spec)
    furnish(spec, verts, faces, fcol)
    ob = make_object(spec, verts, faces, fcol)
    out = os.path.join(ROOT, "Web/CityView/data/raw/trains", which + ".glb")
    n = bake_and_export(ob, out)
    print(f"{which}: {n} faces -> {out} ({os.path.getsize(out) / 1024:.0f} kB)")


main()
