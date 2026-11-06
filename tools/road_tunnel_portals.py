"""Blender 4.x: rebuild decision 611 road portal GLBs and transparent views.

Usage: blender -b --python tools/road_tunnel_portals.py -- --output /path/to/revision-1
The geometry matches Map3DRoadTunnelPortals.swift's metre dimensions.
"""
import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


parser = argparse.ArgumentParser()
parser.add_argument("--output", required=True)
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (*color, 1)
    mat.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = 1
    return mat


concrete = material("concrete_CFCBC2", (0.62, 0.60, 0.56))
trim = material("coping_8B9096", (0.34, 0.37, 0.40))
lining = material("reveal_A9AFBE", (0.31, 0.33, 0.40))
asphalt = material("asphalt", (0.18, 0.21, 0.25))
grass = material("slope_9DB07E", (0.42, 0.54, 0.33))
line = material("road_edge", (0.93, 0.90, 0.76))


def box(name, center, scale, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def polygon(name, coords, mat):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(coords, [], [tuple(range(len(coords)))])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat)
    return obj


def p(x, y, z):
    return (x, y, z)


def build(style, width):
    half = {
        "divided-expressway": (3.75, 5.25),
        "mountain-arch": (3.1, 4.6),
        "nameplate": (4.0, 5.5),
        "narrow-lane": (2.5, 3.5),
    }[style][width == "two-way"]
    clear = 4.7 if style == "narrow-lane" else 5.2
    spring = 3.7 if style == "mountain-arch" else (4.35 if style == "narrow-lane" else clear)
    centres = [-(half + 0.7), half + 0.7] if style == "divided-expressway" else [0]
    outer = centres[-1] + half + (1.2 if style == "narrow-lane" else 2)
    top = clear + 1.3 + (1.1 if style == "nameplate" else 0)

    def roof(c):
        if style == "mountain-arch":
            return [(c - half, spring), (c - .76 * half, 4.5), (c - .4 * half, clear),
                    (c + .4 * half, clear), (c + .76 * half, 4.5), (c + half, spring)]
        if style == "narrow-lane":
            return [(c - half, spring), (c - .74 * half, clear),
                    (c + .74 * half, clear), (c + half, spring)]
        return [(c - half, clear), (c + half, clear)]

    # x points into the hill. The near facade lies at x=0.
    for x in (0, 1.2):
        for i, c in enumerate(centres):
            left, right = c - half, c + half
            left_end = -outer if i == 0 else centres[i-1] + half
            right_end = outer if i == len(centres)-1 else right
            for a, b in ((left_end, left), (right, right_end)):
                if b > a + .001:
                    polygon("headwall", [p(x,a,-.8), p(x,b,-.8), p(x,b,top), p(x,a,top)], concrete)
            prof = roof(c)
            for (a, za), (b, zb) in zip(prof, prof[1:]):
                polygon("roof_face", [p(x,a,za), p(x,b,zb), p(x,b,top), p(x,a,top)], concrete)
    for c in centres:
        for side in (-1, 1):
            y = c + side*half
            polygon("opening_reveal", [p(0,y,-.8), p(0,y,spring), p(1.2,y,spring), p(1.2,y,-.8)], lining)
            box("jamb_band", (-.13,y, spring/2), (.27,.42,spring+.8), trim)
        prof = roof(c)
        for (a, za), (b, zb) in zip(prof, prof[1:]):
            polygon("roof_reveal", [p(0,a,za), p(0,b,zb), p(1.2,b,zb), p(1.2,a,za)], lining)
            polygon("portal_band", [p(-.21,a,za), p(-.21,b,zb), p(-.21,b,zb+.45), p(-.21,a,za+.45)], trim)
    for side in (-1,1):
        y0 = side*outer
        y1 = side*(outer+2)
        polygon("wing_inner", [p(0,y0,-.8), p(0,y0,top-.2), p(-8,y1,.6), p(-8,y1,-.8)], concrete)
        polygon("wing_outer", [p(0,y0+side*.45,-.8), p(0,y0+side*.45,top-.2),
                                p(-8,y1+side*.45,.6), p(-8,y1+side*.45,-.8)], concrete)
        polygon("wing_coping", [p(0,y0,top-.2), p(0,y0+side*.45,top-.2),
                                 p(-8,y1+side*.45,.6), p(-8,y1,.6)], trim)
    if style == "nameplate":
        box("blank_nameplate", (-.24,0, (clear+.65+top-.28)/2), (.15,half*1.6,top-.28-clear-.65), trim)
    return outer, clear


def camera(azimuth, outer):
    bpy.ops.object.camera_add(location=(-25*math.cos(azimuth), 25*math.sin(azimuth), 14))
    cam = bpy.context.object
    target = Vector((-1.4, 0, 2.5))
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = max(outer*2.5, 21)
    bpy.context.scene.camera = cam
    return cam


scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 16
scene.cycles.use_denoising = False
for layer in scene.view_layers:
    layer.cycles.use_denoising = False
scene.render.resolution_x = 480
scene.render.resolution_y = 480
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = True
scene.world.color = (.8,.8,.8)
bpy.ops.object.light_add(type='AREA', location=(-10,-8,20))
bpy.context.object.data.energy = 2500
bpy.context.object.data.shape = 'DISK'
bpy.context.object.data.size = 15

styles = ("divided-expressway", "mountain-arch", "nameplate", "narrow-lane")
for style in styles:
    for width in ("one-way", "two-way"):
        bpy.ops.object.select_all(action='DESELECT')
        keep = [o for o in scene.objects if o.type == 'LIGHT']
        for obj in list(scene.objects):
            if obj not in keep:
                bpy.data.objects.remove(obj, do_unlink=True)
        outer, clear = build(style, width)
        stem = f"{style}-{width}"
        # Only the authored portal parts are exported. Road and hill are scene props.
        bpy.ops.object.select_all(action='SELECT')
        for obj in scene.objects:
            if obj.type == 'LIGHT': obj.select_set(False)
        bpy.context.view_layer.objects.active = next(o for o in scene.objects if o.type == 'MESH')
        bpy.ops.export_scene.gltf(filepath=str(out / f"{stem}.glb"), export_format='GLB', use_selection=True)
        for view, degrees in enumerate((-75,-50,-25,0,25,50,75), 1):
            cam = camera(math.radians(degrees), outer)
            scene.render.filepath = str(out / f"{stem}-view-{view}.png")
            bpy.ops.render.render(write_still=True)
            bpy.data.objects.remove(cam, do_unlink=True)
        print("BUILT", stem, "clear width", half if False else (outer), "clear height", clear, flush=True)

# Composition: a portal embedded in a faceted slope with a road entering it.
for obj in list(scene.objects):
    if obj.type != 'LIGHT': bpy.data.objects.remove(obj, do_unlink=True)
outer, _ = build("mountain-arch", "two-way")
box("road_surface", (-9,0,-.07), (18,8.6,.14), asphalt)
for y in (-3.8,3.8):
    box("edge_line", (-10,y,.02), (14,.13,.03), line)
for side in (-1,1):
    # Terrain starts at the wing's outer crest, then climbs outward and back.
    a = p(0,side*(outer+.45),6.3)
    b = p(-8,side*(outer+2+.45),.6)
    c = p(-8,side*(outer+9),2.7)
    d = p(2,side*(outer+12),9.8)
    e = p(2,side*(outer+.45),7.7)
    polygon("slope_lower_facet", [a,b,c], grass)
    polygon("slope_upper_facet", [a,c,d], grass)
    polygon("slope_back_facet", [a,d,e], grass)
cam = camera(math.radians(-30), outer+7)
scene.render.resolution_x = 960
scene.render.resolution_y = 600
scene.render.filepath = str(out / "hillside-road-composition.png")
bpy.ops.render.render(write_still=True)
