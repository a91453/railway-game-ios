"""Blender 4.x producer for decision 611/359 tunnel portal studies.

blender -b --python tools/road_tunnel_portals.py -- --output REVISION_DIR
Dimensions are duplicated in Map3DRoadTunnelPortals.swift for native meshes.
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

parser = argparse.ArgumentParser()
parser.add_argument("--output", required=True)
parser.add_argument("--composition-only", action="store_true")
parser.add_argument("--scene-check-only", action="store_true")
parser.add_argument("--scene-view", choices=("all","overview","front","side"), default="all")
parser.add_argument("--validate-only", action="store_true")
parser.add_argument("--views-only", action="store_true")
parser.add_argument("--fronts-only", action="store_true")
parser.add_argument("--only", default=None)
parser.add_argument("--engine", choices=("cycles","eevee"), default="cycles")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)


def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*rgb, 1)
    m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 1
    m.use_backface_culling = False
    return m


concrete = mat('concrete_CFCBC2', (.62,.60,.56))
trim = mat('coping_8B9096', (.34,.37,.40))
lining = [mat('lining_near_A9AFBE', (.42,.45,.53)),
          mat('lining_mid_6E7487', (.26,.28,.34)),
          mat('lining_deep_4B5162', (.15,.17,.21)),
          mat('lining_far_353948', (.08,.09,.12))]
capmat = mat('opaque_end_222630', (.025,.03,.045))
asphalt = mat('asphalt', (.18,.21,.25))
ballast = mat('ballast_7E786D', (.35,.33,.30))
railmat = mat('rail_6E7379', (.35,.37,.39))
roadline = mat('road_edge', (.93,.90,.76))
ground = mat('ground_ECEEF6', (236/255,238/255,246/255))
mountain = mat('embankment_9DB07E', (.40,.51,.32))
mountain2 = mat('embankment_light', (.48,.58,.38))


def p(x,y,z): return (x,y,z)  # x into mountain, y right, z up


def poly(name, coords, material, toward=None):
    if toward is not None and len(coords) >= 3:
        a,b,c = (Vector(v) for v in coords[:3])
        if (b-a).cross(c-a).dot(Vector(toward)) < 0:
            coords = list(reversed(coords))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(coords, [], [tuple(range(len(coords)))])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(material)
    return obj


def box(name, center, dims, material):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    return obj


def spec(kind, width=None):
    if kind.startswith('rail-'):
        tracks = 'double' if 'double' in kind else 'single'
        return dict(kind=kind, half=6.3 if tracks == 'double' else 3.2,
                    clear=6.0, spring=2.8, centres=[0], shoulder=2.0,
                    shape='rail', gallery='daylight' in kind, floor=-1.2,
                    nameplate=False, track=True)
    halves = {
        'divided-expressway': (3.75,5.25), 'mountain-arch': (3.1,4.6),
        'nameplate': (4.0,5.5), 'narrow-lane': (2.5,3.5),
        'daylight-gallery': (3.75,5.25),
    }
    half = halves[kind][width == 'two-way']
    clear = 4.7 if kind == 'narrow-lane' else 5.2
    return dict(kind=kind, half=half, clear=clear,
                spring=3.7 if kind == 'mountain-arch' else (4.35 if kind == 'narrow-lane' else clear),
                centres=[-(half+.7), half+.7] if kind == 'divided-expressway' else [0],
                shoulder=1.2 if kind == 'narrow-lane' else 2.0,
                shape='road-arch' if kind == 'mountain-arch' else ('narrow' if kind == 'narrow-lane' else 'box'),
                gallery=kind == 'daylight-gallery', floor=-.8,
                nameplate=kind == 'nameplate', track=False)


def roof(s,c):
    h,k,v = s['half'],s['clear'],s['spring']
    if s['shape'] == 'road-arch':
        return [(c-h,v),(c-.76*h,4.5),(c-.4*h,k),(c+.4*h,k),(c+.76*h,4.5),(c+h,v)]
    if s['shape'] == 'narrow':
        return [(c-h,v),(c-.74*h,k),(c+.74*h,k),(c+h,v)]
    if s['shape'] == 'rail':
        return [(c-h,v),(c-h+1.4,k),(c+h-1.4,k),(c+h,v)]
    return [(c-h,k),(c+h,k)]


def build(kind, width=None, offset=(0,0,0)):
    s=spec(kind,width)
    half,clear,centres=s['half'],s['clear'],s['centres']
    outer=centres[-1]+half+s['shoulder']
    top=clear+1.3+(1.1 if s['nameplate'] else 0)
    front=-12 if s['gallery'] else 0
    start=1.2 if s['gallery'] else front+1.2
    end=start+8
    floor=s['floor']
    ox,oy,oz=offset
    def q(x,y,z): return p(x+ox,y+oy,z+oz)
    def face(name,coords,material,toward): return poly(name,[q(*a) for a in coords],material,toward)
    def panel(a,b,low,high,x):
        if b>a:
            face('headwall', [p(x,a,low),p(x,b,low),p(x,b,high),p(x,a,high)],concrete,(-1 if x==front else 1,0,0))
    for x in (front,0 if s['gallery'] else 1.2):
        for i,c in enumerate(centres):
            left,right=c-half,c+half
            panel(-outer if i==0 else centres[i-1]+half,left,floor,top,x)
            if i==len(centres)-1: panel(right,outer,floor,top,x)
            prof=roof(s,c)
            for (a,za),(b,zb) in zip(prof,prof[1:]):
                face('facade_spandrel',[p(x,a,za),p(x,b,zb),p(x,b,top),p(x,a,top)],concrete,(-1 if x==front else 1,0,0))
    for c in centres:
        prof=roof(s,c)
        if s['gallery']:
            for side in (-1,1):
                y=c+half*side
                face('gallery_inner_retaining_wall',[p(front,y,floor),p(front,y,s['spring']),p(0,y,s['spring']),p(0,y,floor)],lining[0],(0,-side,0))
                y+=side*s['shoulder']
                face('gallery_outer_retaining_wall',[p(front,y,floor),p(front,y,top),p(0,y,top),p(0,y,floor)],concrete,(0,side,0))
            for (a,za),(b,zb) in zip(prof,prof[1:]):
                face('gallery_roof_underside',[p(front,a,za),p(front,b,zb),p(0,b,zb),p(0,a,za)],lining[0],(0,0,-1))
            face('gallery_outer_roof',[p(front,-outer,top),p(front,outer,top),p(0,outer,top),p(0,-outer,top)],trim,(0,0,1))
        for band,m in enumerate(lining):
            x0=start+2*band
            x1=x0+2
            for side in (-1,1):
                y=c+half*side
                face('darkening_side_wall',[p(x0,y,floor),p(x0,y,s['spring']),p(x1,y,s['spring']),p(x1,y,floor)],m,(0,-side,0))
            for (a,za),(b,zb) in zip(prof,prof[1:]):
                face('darkening_roof',[p(x0,a,za),p(x0,b,zb),p(x1,b,zb),p(x1,a,za)],m,(0,0,-1))
            face('darkening_floor',[p(x0,c-half,floor),p(x0,c+half,floor),p(x1,c+half,floor),p(x1,c-half,floor)],m,(0,0,1))
        # Solid, double-sided end wall: no aperture can show the far background.
        outline=[p(end,c-half,floor)]+[p(end,y,z) for y,z in prof]+[p(end,c+half,floor)]
        face('opaque_depth_cap',outline,capmat,(-1,0,0))
        face('opaque_depth_cap_reverse',list(reversed(outline)),capmat,(1,0,0))
        for (a,za),(b,zb) in zip(prof,prof[1:]):
            face('entrance_band',[p(front-.2,a,za),p(front-.2,b,zb),
                                 p(front-.2,b,zb+.45),p(front-.2,a,za+.45)],trim,(-1,0,0))
        for side in (-1,1):
            y=c+half*side
            box('entrance_jamb',q(front-.13,y,(s['spring']+floor)/2),(.27,.42,s['spring']-floor),trim)
    # Outer shell stops side-on views seeing through the lining from outside.
    for side in (-1,1):
        y=outer*side
        face('outer_bore_shell',[p(0,y,floor),p(0,y,top),p(end,y,top),p(end,y,floor)],concrete,(0,side,0))
    face('outer_bore_roof',[p(0,-outer,top),p(0,outer,top),p(end,outer,top),p(end,-outer,top)],concrete,(0,0,1))
    for side in (-1,1):
        y0=side*outer
        y1=side*(outer+2)
        face('wing_inner',[p(front,y0,floor),p(front,y0,top-.2),p(front-8,y1,.6),p(front-8,y1,floor)],concrete,(0,-side,0))
        face('wing_outer',[p(front,y0+side*.45,floor),p(front,y0+side*.45,top-.2),
                           p(front-8,y1+side*.45,.6),p(front-8,y1+side*.45,floor)],concrete,(0,side,0))
        face('wing_coping',[p(front,y0,top-.2),p(front,y0+side*.45,top-.2),
                            p(front-8,y1+side*.45,.6),p(front-8,y1,.6)],trim,(0,0,1))
    if s['nameplate']:
        box('blank_nameplate',q(front-.24,0,(clear+.65+top-.28)/2),
            (.15,half*1.6,top-.28-clear-.65),trim)
    return dict(**s,outer=outer,top=top,front=front,inner_end=end,offset=offset)


def clear_except_lights():
    for obj in list(bpy.context.scene.objects):
        if obj.type!='LIGHT': bpy.data.objects.remove(obj,do_unlink=True)


def camera(angle, aim, scale, height=14):
    bpy.ops.object.camera_add(location=(-26*math.cos(angle)+aim[0],26*math.sin(angle)+aim[1],height+aim[2]))
    cam=bpy.context.object
    cam.rotation_euler=(Vector(aim)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO'
    cam.data.ortho_scale=scale
    bpy.context.scene.camera=cam
    return cam


def validate_occlusion(s):
    """Entrance rays at several lateral and oblique angles must hit geometry."""
    bpy.context.view_layer.update()
    depsgraph=bpy.context.evaluated_depsgraph_get()
    front,end=s['front'],s['inner_end']
    for centre in s['centres']:
        for across in (-.45,0,.45):
            for target_across in (-.35,0,.35):
                origin=Vector((front-.8,centre+across*s['half'],1.8))
                target=Vector((end+2,centre+target_across*s['half'],1.8))
                vector=target-origin
                hit,point,normal,index,obj,matrix=scene.ray_cast(depsgraph,origin,vector.normalized(),distance=vector.length)
                assert hit and point.x <= end+.05, (s['kind'],across,target_across,'see-through')


def validate_ground_contact():
    """Model-space geometry must meet the same ground elevation within 5 cm."""
    def heights(prefixes):
        return [(obj.matrix_world @ vertex.co).z
                for obj in scene.objects if obj.type=='MESH'
                and obj.name.startswith(prefixes)
                for vertex in obj.data.vertices]
    ground_z=max(heights(('map_ground',)))
    for label,prefixes in (
        ('mountain',('earth_','mountain_','joined_bank_','wing_slope_')),
        ('wings',('wing_inner','wing_outer')),
        ('road and rail surfaces',('road_surface','rail_bed')),
    ):
        low=min(heights(prefixes))
        assert abs(low-ground_z)<=.05, f'{label} lowest {low:.3f} m, ground {ground_z:.3f} m'
    print(f'GROUND CONTACT: mountain, wings, roads/rails at {ground_z:.3f} m (±0.05 m)',flush=True)


scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE_NEXT' if args.engine=='eevee' else 'CYCLES'
scene.cycles.samples=32
scene.cycles.use_denoising=False
for layer in scene.view_layers: layer.cycles.use_denoising=False
scene.render.resolution_x=480
scene.render.resolution_y=480
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.film_transparent=True
scene.world.color=(.83,.86,.94)
scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.83,.86,.94,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.8
scene.view_settings.view_transform='Standard'
bpy.ops.object.light_add(type='AREA',location=(-12,-9,22))
bpy.context.object.data.energy=3000
bpy.context.object.data.shape='DISK'
bpy.context.object.data.size=16

models=[(kind,width) for kind in ('divided-expressway','mountain-arch','nameplate','narrow-lane','daylight-gallery')
        for width in ('one-way','two-way')]
models += [(kind,None) for kind in ('rail-single','rail-double','rail-daylight-single','rail-daylight-double')]
if args.composition_only: models = []
if args.only: models=[entry for entry in models if entry[0]==args.only]
connectors={}
for kind,width in models:
    clear_except_lights()
    s=build(kind,width)
    validate_occlusion(s)
    stem=kind if width is None else f'{kind}-{width}'
    connectors[stem]={
        'surface_center_m':[s['front'],0,0], 'into_tunnel':[1,0,0],
        'clear_width_m':2*s['half'], 'clear_height_m':s['clear'],
        'lining_depth_m':8, 'daylight_cover_length_m':12 if s['gallery'] else 0,
    }
    if args.validate_only: continue
    for obj in scene.objects: obj.select_set(obj.type=='MESH')
    bpy.context.view_layer.objects.active=next(o for o in scene.objects if o.type=='MESH')
    bpy.ops.export_scene.gltf(filepath=str(out/f'{stem}.glb'),export_format='GLB',use_selection=True)
    # View 1 is head-on. The rest cover both oblique sides and the rear.
    for view,angle in enumerate((0,-30,30,-60,60,-120,120),1):
        if args.fronts_only and view != 1: continue
        aim_x=s['front']+(4 if s['gallery'] else 1.5)
        cam=camera(math.radians(angle),(aim_x,0,2.5),
                   max(s['outer']*2.7,36 if s['gallery'] else 26),
                   height=5 if view==1 else 14)
        scene.render.filepath=str(out/f'{stem}-view-{view}.png')
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam,do_unlink=True)
    print('BUILT',stem,'depth',s['inner_end']-(1.2 if s['gallery'] else 1.2),'clear',s['clear'],flush=True)
if not args.only and not args.composition_only:
    (out/'connectors.json').write_text(json.dumps({
        'coordinates':'Blender metres: x into tunnel, y right, z up',
        'models':connectors},indent=2,sort_keys=True)+'\n')

# One review scene: five routes entering one continuous mountain face.
if args.validate_only:
    print('VALIDATED',len(models),'portal variants with frontal and oblique rays',flush=True)
    sys.exit(0)
if args.views_only or args.fronts_only: sys.exit(0)
clear_except_lights()
scene.render.film_transparent=False
scene.world.color=(236/255,238/255,246/255)
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(236/255,238/255,246/255,1)
scene.render.resolution_x=1600
scene.render.resolution_y=900
placements=[('mountain-arch','two-way',-57),('daylight-gallery','one-way',-29),
            ('rail-single',None,0),('rail-double',None,29),
            ('rail-daylight-double',None,58)]
scene_specs=[]
for kind,width,y in placements:
    # The authored portal mesh stays unchanged. Its buried wing base sits on
    # z=0 in this scene; an approach grade joins its surface to that ground.
    elevation=-spec(kind,width)['floor']
    s=build(kind,width,offset=(0,y,elevation))
    scene_specs.append(s)
    front=s['front']; half=s['half']; approach=front-24
    bed_half=half-(.35 if s['track'] else .18)
    bed_mat=ballast if s['track'] else asphalt
    bed_name='rail_bed' if s['track'] else 'road_surface'
    def route(x,across,height): return p(x,y+across,height)
    poly(bed_name,[route(approach,-bed_half,0),route(approach,bed_half,0),
                   route(front,bed_half,elevation),route(front,-bed_half,elevation)],
         bed_mat,(0,0,1))
    for side in (-1,1):
        edge=side*bed_half
        poly('route_ramp_side',[route(approach,edge,0),route(front,edge,0),
                                route(front,edge,elevation)],bed_mat,(0,side,0))
    if s['gallery']:
        poly(bed_name,[route(front,-bed_half,elevation),route(front,bed_half,elevation),
                       route(1.2,bed_half,elevation),route(1.2,-bed_half,elevation)],
             bed_mat,(0,0,1))
    for side in (-1,1):
        if s['track']:
            stripe=side*.75; stripe_half=.06; stripe_mat=railmat; stripe_name='rail'
        else:
            stripe=side*(half-.45); stripe_half=.055; stripe_mat=roadline; stripe_name='road_edge_line'
        poly(stripe_name,[route(approach,stripe-stripe_half,.04),route(approach,stripe+stripe_half,.04),
                          route(front,stripe+stripe_half,elevation+.04),route(front,stripe-stripe_half,elevation+.04)],
             stripe_mat,(0,0,1))
        if s['gallery']:
            poly(stripe_name,[route(front,stripe-stripe_half,elevation+.04),route(front,stripe+stripe_half,elevation+.04),
                              route(1.2,stripe+stripe_half,elevation+.04),route(1.2,stripe-stripe_half,elevation+.04)],
                 stripe_mat,(0,0,1))
    # The bank descends from the wing coping to ground and joins the roof
    # slope. There is no raised point behind the wing.
    for side in (-1,1):
        f=s['front']; o=s['outer']; t=s['top']
        cap=p(f,y+side*o,t+elevation+.02)
        root=p(f,y+side*(o+.45),t+elevation-.2)
        tip=p(f-8,y+side*(o+2+.45),elevation+.6)
        foot_near=p(f-9,y+side*(o+2+.45),0)
        foot_tip=p(f-5,y+side*(o+7),0)
        foot_root=p(f-2,y+side*(o+12),0)
        ridge_outer=p(12,y+side*(o+12),12.5)
        ridge_inner=p(12,y+side*o,12.5)
        poly('wing_slope_lower_a',[root,tip,foot_near],mountain,(0,0,1))
        poly('wing_slope_lower_b',[root,foot_near,foot_tip],mountain,(0,0,1))
        poly('wing_slope_lower_c',[root,foot_tip,foot_root],mountain,(0,0,1))
        poly('wing_slope_upper_a',[root,foot_root,ridge_outer],mountain,(0,0,1))
        poly('wing_slope_upper_b',[root,ridge_outer,ridge_inner],mountain2,(0,0,1))
        poly('wing_slope_join',[cap,root,ridge_inner],mountain,(0,0,1))
    f=s['front']; o=s['outer']; t=s['top']
    poly('earth_over_portal',[p(f,y-o,t+elevation+.02),p(f,y+o,t+elevation+.02),
                              p(12,y+o,12.5),p(12,y-o,12.5)],mountain,(0,0,1))
# Fill gaps between the portal banks from ground to the common ridge.
edges=[]
for s in scene_specs:
    y=s['offset'][1]; o=s['outer']; f=s['front']; t=s['top']
    front_height=t+s['offset'][2]+.02
    at_zero=front_height+(12.5-front_height)*((-f)/(12-f))
    edges.append((y-o,at_zero,y+o,at_zero))
gaps=[(-82,7.5,edges[0][0],edges[0][1])]
gaps += [(a[2],a[3],b[0],b[1]) for a,b in zip(edges,edges[1:])]
gaps.append((edges[-1][2],edges[-1][3],82,7.5))
for left,hleft,right,hright in gaps:
    a=p(0,left,hleft); b=p(0,right,hright)
    c=p(12,right,12.5); d=p(12,left,12.5)
    e=p(-7,right,0); f=p(-7,left,0)
    poly('joined_bank_upper_a',[a,b,c],mountain,(0,0,1))
    poly('joined_bank_upper_b',[a,c,d],mountain2,(0,0,1))
    poly('joined_bank_foot_a',[a,b,e],mountain,(0,0,1))
    poly('joined_bank_foot_b',[a,e,f],mountain,(0,0,1))
# Continuous faceted mountain: front bank, varied ridge, and closed flanks.
ridge_y=(-82,-43,-14,14,43,82)
ridge_h=(17,22,19,23,18,21)
for i,(y0,y1) in enumerate(zip(ridge_y,ridge_y[1:])):
    h0,h1=ridge_h[i:i+2]
    tint=mountain if i%2==0 else mountain2
    a=p(12,y0,12.5); b=p(12,y1,12.5); c=p(32,y1,h1); d=p(32,y0,h0)
    poly('mountain_rise_a',[a,b,c],tint,(0,0,1))
    poly('mountain_rise_b',[a,c,d],mountain2 if i%2==0 else mountain,(0,0,1))
    poly('mountain_back_slope',[d,c,p(53,y1,h1-3),p(53,y0,h0-3)],mountain,(0,0,1))
    poly('mountain_rear',[p(53,y0,0),p(53,y1,0),p(53,y1,h1-3),p(53,y0,h0-3)],mountain,(1,0,0))
for side,height in ((-1,ridge_h[0]),(1,ridge_h[-1])):
    y=82*side
    spine=[(-10,0),(0,7.5),(12,12.5),(32,height),(53,height-3)]
    for (x0,z0),(x1,z1) in zip(spine,spine[1:]):
        poly('mountain_side',[p(x0,y,0),p(x1,y,0),p(x1,y,z1),p(x0,y,z0)],mountain,(0,side,0))
# The ground slab's upper face is exactly z=0 m.
box('map_ground',(0,0,-.1),(20000,20000,.2),ground)
validate_ground_contact()
if args.scene_check_only:
    print('SCENE CHECK PASSED',flush=True)
    sys.exit(0)
scene.cycles.samples=48

def scene_camera(name,location,target,scale):
    location=Vector(location); target=Vector(target)
    # The orthographic image plane must stay above z=0 across its full frame.
    # Moving backward along the same ray keeps the chosen view unchanged.
    ray=target-location
    minimum_camera_z=scale*.52
    if location.z < minimum_camera_z:
        location-=ray*((minimum_camera_z-location.z)/(-ray.z))
    bpy.ops.object.camera_add(location=location)
    cam=bpy.context.object
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO'
    cam.data.ortho_scale=scale
    cam.data.clip_end=10000
    scene.camera=cam
    scene.render.filepath=str(out/name)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam,do_unlink=True)

if args.scene_view in ('all','overview'):
    scene_camera('mountain-road-rail-composition.png',(-95,-19,28),(-6,0,4),176)
if args.scene_view in ('all','front'):
    scene_camera('mountain-road-rail-front.png',(-115,0,8),(-5,0,4),176)
if args.scene_view in ('all','side'):
    # Isolate the same road portal as the leftmost one in the shared scene.
    # This removes overlapping tunnels behind it from the side inspection.
    clear_except_lights()
    sample=spec('mountain-arch','two-way')
    height=-sample['floor']
    s=build('mountain-arch','two-way',offset=(0,0,height))
    o=s['outer']; top=s['top']+height; half=s['half']-.18
    poly('road_surface',[p(-30,-half,0),p(-30,half,0),
                         p(0,half,height),p(0,-half,height)],asphalt,(0,0,1))
    for side in (-1,1):
        edge=side*half
        poly('route_ramp_side',[p(-30,edge,0),p(0,edge,0),p(0,edge,height)],asphalt,(0,side,0))
        root=p(0,side*(o+.45),top-.2)
        tip=p(-8,side*(o+2+.45),height+.6)
        foot_near=p(-9,side*(o+2+.45),0)
        foot_tip=p(-5,side*(o+7),0)
        foot_root=p(-2,side*(o+12),0)
        ridge_outer=p(12,side*(o+12),12.5)
        ridge_inner=p(12,side*o,12.5)
        cap=p(0,side*o,top+.02)
        poly('wing_slope_lower_a',[root,tip,foot_near],mountain,(0,0,1))
        poly('wing_slope_lower_b',[root,foot_near,foot_tip],mountain,(0,0,1))
        poly('wing_slope_lower_c',[root,foot_tip,foot_root],mountain,(0,0,1))
        poly('wing_slope_upper_a',[root,foot_root,ridge_outer],mountain,(0,0,1))
        poly('wing_slope_upper_b',[root,ridge_outer,ridge_inner],mountain2,(0,0,1))
        poly('wing_slope_join',[cap,root,ridge_inner],mountain,(0,0,1))
    poly('earth_over_portal',[p(0,-o,top+.02),p(0,o,top+.02),
                              p(12,o,12.5),p(12,-o,12.5)],mountain,(0,0,1))
    for side in (-1,1):
        y=side*(o+12)
        spine=[(-9,0),(-2,0),(12,12.5),(32,19),(53,16)]
        for (x0,z0),(x1,z1) in zip(spine,spine[1:]):
            poly('mountain_side',[p(x0,y,0),p(x1,y,0),p(x1,y,z1),p(x0,y,z0)],
                 mountain,(0,side,0))
    poly('mountain_rise',[p(12,-o-12,12.5),p(12,o+12,12.5),
                          p(32,o+12,19),p(32,-o-12,19)],mountain,(0,0,1))
    poly('mountain_back_slope',[p(32,-o-12,19),p(32,o+12,19),
                                p(53,o+12,16),p(53,-o-12,16)],mountain2,(0,0,1))
    box('map_ground',(0,0,-.1),(20000,20000,.2),ground)
    validate_ground_contact()
    scene_camera('mountain-road-rail-side.png',(-40,-37,19),(-9,0,4),75)

# Plain HTML and local PNG/GLB paths work directly from file://, offline.
model_stems=[f'{kind}-{width}' for kind in ('divided-expressway','mountain-arch',
             'nameplate','narrow-lane','daylight-gallery') for width in ('one-way','two-way')]
model_stems += ['rail-single','rail-double','rail-daylight-single','rail-daylight-double']
html='''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>公路與鐵路隧道洞口 revision 3</title>
<style>body{margin:0;padding:20px;background:#eceef6;color:#262c57;font:16px system-ui,sans-serif}main{max-width:1100px;margin:auto}h1{font-size:1.5rem}button,select,input{font:inherit;margin:3px;padding:7px}img{display:block;max-width:100%;max-height:70vh;margin:12px auto;background:#eceef6}section{background:#fff;padding:14px;margin:12px 0;border-radius:10px}.controls{display:flex;flex-wrap:wrap;align-items:center;gap:4px}a{color:#2f6db5}</style>
<main><h1>隧道洞口 revision 3 · 離線檢視</h1><p>七向預覽使用 revision 2 原模型；下方另可檢視組景、正面與側面接地圖。此頁不連網。</p>
<section><div class="controls"><label>模型 <select id="model"></select></label><button id="previous">◀</button><label>方向 <input id="view" type="range" min="1" max="7" value="1"></label><button id="next">▶</button><output id="direction"></output><a id="glb" download>下載 GLB</a></div><img id="model-image" alt="洞口預覽"></section>
<section><div class="controls"><button data-scene="mountain-road-rail-composition.png">共用山體</button><button data-scene="mountain-road-rail-front.png">正面接地</button><button data-scene="mountain-road-rail-side.png">側面接地</button></div><img id="scene-image" src="mountain-road-rail-composition.png" alt="公路與鐵路共用山體組景"><p>側面圖隔離最左側公路洞口，便於看道路坡道、翼牆及山腳。地面頂面為 0.00 m。</p></section>
<p>重建指令、尺寸、來源及授權見 <a href="README.md">README</a>；接點見 <a href="connectors.json">connectors.json</a>。</p></main>
<script>const stems=__MODELS__,model=document.querySelector('#model'),view=document.querySelector('#view'),preview=document.querySelector('#model-image'),label=document.querySelector('#direction'),glb=document.querySelector('#glb');
stems.forEach(stem=>model.add(new Option(stem,stem)));function draw(){const stem=model.value,n=Number(view.value);preview.src=`${stem}-view-${n}.png`;preview.alt=`${stem} 第 ${n} 向`;label.value=`${n} / 7`;glb.href=`${stem}.glb`;glb.download=`${stem}.glb`;}model.onchange=draw;view.oninput=draw;document.querySelector('#previous').onclick=()=>{view.value=Math.max(1,Number(view.value)-1);draw()};document.querySelector('#next').onclick=()=>{view.value=Math.min(7,Number(view.value)+1);draw()};document.querySelectorAll('[data-scene]').forEach(b=>b.onclick=()=>document.querySelector('#scene-image').src=b.dataset.scene);draw();</script></html>'''
(out/'viewer.html').write_text(html.replace('__MODELS__',json.dumps(model_stems)),encoding='utf-8')
