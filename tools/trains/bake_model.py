# Turns a dense, beautifully textured model into a game asset: decimated to a triangle budget,
# unwrapped afresh, and with the dense model's own colour and occlusion baked onto it.
#
#   pip install bpy
#   python3 -I tools/trains/bake_model.py <dense.glb> n700st-cab [n700st-car]
#
# WHY THIS EXISTS. A generated model (Meshy, tools/meshy) is made to be looked at once: the owner's
# N700ST is 280,838 triangles with 17 MB of JPEG. The city view draws twelve cars of it, several
# trains at a time, on a phone. The shape and the paint are what he wants; the triangle count and
# the texture size are not, and neither is anything we could draw by hand instead.
#
# High to low is the way a studio does this, and it is only three steps. Collapse the dense mesh
# until it fits the budget — the silhouette survives, because collapse spends its vertices where the
# curvature is. Unwrap the result (the dense model's own UVs do not survive a 99% collapse). Then
# bake the dense model onto it: the colour it was shipped with, and the occlusion of its own
# recesses. What comes out is one GLB and two small pictures.
#
# tools/trains/build_train.py is the other half of the same tool shed: it builds a car from nothing
# when there is no model to start from, and paints it with the city view's own canvas. This one
# starts from a model and keeps that model's paint.
import json
import math
import os
import sys

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# What each name wants, in the city view's own metres. `body` keeps only the part behind the nose,
# which is how an intermediate car is made from a cab car: there is no second model for it.
PLAN = {
    "n700st-cab": {"length": 24.4, "width": 2.9, "height": 3.9, "triangles": 8000, "body": False},
    "n700st-car": {"length": 24.4, "width": 2.9, "height": 3.9, "triangles": 6000, "body": True},
}
COLOUR, OCCLUSION = 1024, 512


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit(f"{path}: no mesh in it")
    for o in bpy.context.scene.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    flatten(ob)
    return ob


def flatten(ob):
    """Put the object's transform into its vertices and clear it. `mesh.transform` rather than the
    transform_apply operator: the operator depends on selection, mode and parenting, and when any of
    those is not what it wants it does nothing and says nothing — which is how the first version of
    this shipped a train running nose-last."""
    from mathutils import Matrix
    ob.data.transform(ob.matrix_world)
    ob.matrix_world = Matrix.Identity(4)


def lay_along_x(ob):
    """Nose towards +X, rail at z = 0, centred — the frame build_train.py writes and the city view
    reads (`front: '+x'`). Which end is the nose is measured, not assumed: it is the end whose
    cross-section is the smaller, because that is what a nose is."""
    co = [v.co.copy() for v in ob.data.vertices]
    lo = [min(c[i] for c in co) for i in range(3)]
    hi = [max(c[i] for c in co) for i in range(3)]
    size = [hi[i] - lo[i] for i in range(3)]
    along = max(range(3), key=lambda i: size[i])
    if along == 2:
        raise SystemExit("the model's longest axis is its height; it is not a vehicle")
    if along == 1:                                   # the long axis onto x, keeping z up
        turn(ob, math.radians(90))

    co = [v.co.copy() for v in ob.data.vertices]
    lo = [min(c[i] for c in co) for i in range(3)]
    hi = [max(c[i] for c in co) for i in range(3)]
    span = hi[0] - lo[0]
    ends = []
    for a, b in ((lo[0], lo[0] + span * 0.08), (hi[0] - span * 0.08, hi[0])):
        near = [c for c in co if a <= c[0] <= b]
        ends.append((max(c[1] for c in near) - min(c[1] for c in near))
                    * (max(c[2] for c in near) - min(c[2] for c in near)))
    if ends[0] < ends[1]:                            # the small end is at -x: turn it round
        turn(ob, math.pi)
    return span


def turn(ob, angle):
    from mathutils import Matrix
    ob.data.transform(Matrix.Rotation(angle, 4, "Z"))


def fit(ob, want):
    """To the city view's metres. A generated model's absolute size is never right — this one is 29%
    too wide for its length — so each axis is set rather than scaled together."""
    co = [v.co.copy() for v in ob.data.vertices]
    lo = [min(c[i] for c in co) for i in range(3)]
    hi = [max(c[i] for c in co) for i in range(3)]
    size = [max(1e-6, hi[i] - lo[i]) for i in range(3)]
    k = (want["length"] / size[0], want["width"] / size[1], want["height"] / size[2])
    mid = ((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2)
    for v in ob.data.vertices:
        v.co = ((v.co[0] - mid[0]) * k[0], (v.co[1] - mid[1]) * k[1], (v.co[2] - lo[2]) * k[2])


GANGWAY = (0.10, 0.11, 0.12, 1.0)      # what the end between two cars is: a dark rubber bellows


def cut_nose(ob, keep_from):
    """An intermediate car out of a cab car: cut the nose off and close the end. The new face is
    given its own dark material, because it has no place in the model's own picture and a bake with
    nothing to read lands on whatever is at the corner of that picture — a speckled grey block
    standing between every pair of cars."""
    import bmesh
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.scene.objects:
        o.select_set(o is ob)
    mat = bpy.data.materials.new("gangway")
    mat.use_nodes = True
    for node in mat.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            node.inputs["Base Color"].default_value = GANGWAY
    ob.data.materials.append(mat)

    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(ob.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                           plane_co=(keep_from, 0, 0), plane_no=(1, 0, 0), clear_outer=True)
    bmesh.update_edit_mesh(ob.data)
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.region_to_loop()
    bpy.ops.mesh.edge_face_add()
    ob.active_material_index = len(ob.data.materials) - 1
    bpy.ops.object.material_slot_assign()
    bpy.ops.object.mode_set(mode="OBJECT")


def triangles_of(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def weld(ob, threshold=0.001):
    """Merge coincident vertices and make the normals agree. A generated mesh is full of vertices
    that sit on each other without being joined, and a collapse across those seams tears holes
    instead of closing them: the first run of this came out as confetti below the waist."""
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.scene.objects:
        o.select_set(o is ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=threshold)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.mesh.delete_loose()
    bpy.ops.object.mode_set(mode="OBJECT")


def decimate(ob, triangles):
    """Collapse to the budget. Triangulate first, because the ratio is a fraction of the faces the
    modifier is handed and a mesh with n-gons in it grows again on the way out. Collapse twice if
    once does not get there: a non-manifold edge can stop the first pass short."""
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.scene.objects:
        o.select_set(o is ob)
    m = ob.modifiers.new("tri", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=m.name)
    for _ in range(3):
        faces = triangles_of(ob)
        if faces <= triangles * 1.05:
            return faces
        m = ob.modifiers.new("decimate", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = triangles / faces
        bpy.ops.object.modifier_apply(modifier=m.name)
    return triangles_of(ob)


def unwrap(ob):
    """The dense model's own UVs do not survive a 99% collapse, so the low one is unwrapped afresh
    and the colour is baked into the new coordinates."""
    bpy.context.view_layer.objects.active = ob
    ob.data.uv_layers.new(name="UVMap")
    ob.data.uv_layers.active = ob.data.uv_layers["UVMap"]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.006,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def unwrap(ob):
    """Fresh coordinates for the light mesh. The dense model's own do not survive the collapse — it
    drags vertices across the chart boundaries and the livery smears, which is subtler than a hole
    and reads as a torn window. Projecting, evening the islands out and packing them is what fills
    the picture; projecting alone leaves a confetti of islands in one corner, and the bake then
    catches a few pixels of each."""
    bpy.context.view_layer.objects.active = ob
    while ob.data.uv_layers:
        ob.data.uv_layers.remove(ob.data.uv_layers[0])
    ob.data.uv_layers.new(name="UVMap")
    for o in bpy.context.scene.objects:
        o.select_set(o is ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    # A collapse leaves the surface slightly noisy, and the projection splits an island wherever two
    # faces disagree: a noisy surface at the stock 66 degrees came out as hundreds of islands a few
    # texels across, which the bake fills with whatever is beside them. One smoothing pass and the
    # widest angle the operator takes give a handful of big islands instead.
    bpy.ops.mesh.vertices_smooth(factor=0.35, repeat=2)
    bpy.ops.uv.smart_project(angle_limit=math.radians(89), island_margin=0.006,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale()
    bpy.ops.uv.pack_islands(margin=0.006)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake(low, high, kind, size, path, samples, distance=0.3):
    """Bake the dense model onto the light one. `distance` is how far the bake looks for the dense
    surface from the low one; too short and the nose bakes empty, too long and the far flank bleeds
    through."""
    scene = bpy.context.scene
    if scene.world is None:
        scene.world = bpy.data.worlds.new("world")
    scene.world.light_settings.distance = 0.8
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.render.bake.margin = 16
    scene.render.bake.use_clear = True
    scene.render.bake.use_selected_to_active = high is not None
    if high is not None:
        # A short reach. The car is 2.9 m wide, so a cage of the half-width lets a ray from one
        # flank find the other and the roof comes out painted with the underframe.
        scene.render.bake.cage_extrusion = distance
        scene.render.bake.max_ray_distance = distance * 2
    if kind == "DIFFUSE":
        scene.render.bake.use_pass_direct = False
        scene.render.bake.use_pass_indirect = False
        scene.render.bake.use_pass_color = True

    mat = bpy.data.materials.new("bake-" + kind)
    mat.use_nodes = True
    low.data.materials.clear()
    low.data.materials.append(mat)
    img = bpy.data.images.new("bake", size, size)
    img.generated_color = (1.0, 1.0, 1.0, 1.0)
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    mat.node_tree.nodes.active = node

    for o in bpy.context.scene.objects:
        o.select_set(False)
    if high is not None:
        high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.bake(type=kind)

    settings = scene.render.image_settings
    settings.file_format = "PNG" if kind == "AO" else "JPEG"
    settings.color_mode = "BW" if kind == "AO" else "RGB"
    settings.color_depth = "8"
    settings.compression = 100
    settings.quality = 88
    img.save_render(path, scene=scene)
    low.data.materials.clear()
    return path


def one(source, which, out_dir):
    want = PLAN[which]
    high = load(source)
    span = lay_along_x(high)
    weld(high)
    if want["body"]:
        # An intermediate car is the cab car with its nose cut off, behind where the section stops
        # changing, so none of the taper is left on it. What it cannot be is right: a real
        # intermediate car has more windows, not wider-spaced ones, and stretching the body apart is
        # what this does. It is the best an eleven-car formation can be from one model of one car.
        cut_nose(high, -span / 2 + span * 0.36)
        weld(high)
    fit(high, want)

    low = high.copy()
    low.data = high.data.copy()
    bpy.context.collection.objects.link(low)
    low.name = which
    tris = decimate(low, want["triangles"])
    unwrap(low)
    colour = bake(low, high, "DIFFUSE", COLOUR, os.path.join(out_dir, which + ".jpg"), 4)
    ao = bake(low, None, "AO", OCCLUSION, os.path.join(out_dir, which + "-ao.png"), 48)
    bpy.data.objects.remove(high, do_unlink=True)

    glb = os.path.join(out_dir, which + ".glb")
    for o in bpy.context.scene.objects:
        o.select_set(o is low)
    bpy.context.view_layer.objects.active = low
    low.data.materials.clear()
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True,
                              export_apply=True, export_materials="NONE")
    print(f"{which}: {tris} triangles -> {os.path.basename(glb)} "
          f"({os.path.getsize(glb) / 1024:.0f} kB), colour -> {os.path.basename(colour)} "
          f"({os.path.getsize(colour) / 1024:.0f} kB), occlusion -> {os.path.basename(ao)} "
          f"({os.path.getsize(ao) / 1024:.0f} kB)")
    return {"file": which + ".glb", "colour": which + ".jpg", "ao": which + "-ao.png",
            "aoChannel": 0, "front": "+x", "fit": False}


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: bake_model.py <dense.glb> <name> [<name> ...]")
    source, names = sys.argv[1], sys.argv[2:]
    out_dir = os.path.join(ROOT, "Web/CityView/public/models/trains")
    os.makedirs(out_dir, exist_ok=True)
    built = {name: one(source, name, out_dir) for name in names}
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
