"""Blender-only local clay study of the owner's merged GLB; never copies meshes.
Usage: blender --background --python reference-study.py -- PRIVATE_GLB OUT
"""
import bpy,json,sys,hashlib
from mathutils import Vector
from pathlib import Path
source,root=map(Path,sys.argv[sys.argv.index('--')+1:]);root.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(source))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
points=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
lo=Vector([min(p[i] for p in points) for i in range(3)]);hi=Vector([max(p[i] for p in points) for i in range(3)]);center=(lo+hi)/2
# Explicit neutral clay. The study is of geometry, not source paint or textures.
material=bpy.data.materials.new('LocalReferenceClay');material.diffuse_color=(.72,.72,.72,1)
for o in objects:o.data.materials.clear();o.data.materials.append(material)
sc=bpy.context.scene;sc.render.engine='BLENDER_EEVEE_NEXT';sc.eevee.taa_render_samples=16
sc.render.resolution_x=1100;sc.render.resolution_y=650;sc.render.resolution_percentage=100;sc.render.film_transparent=True;sc.world.color=(.75,.75,.75)
for pos,power,size in [((4,-10,16),2200,12),((-4,8,10),1700,14),((10,3,4),900,10)]:
 bpy.ops.object.light_add(type='AREA',location=center+Vector(pos));o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(center-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add();camera=bpy.context.object;camera.data.type='ORTHO';camera.data.ortho_scale=(hi-lo).length*1.08;sc.camera=camera
for name,direction in [('left',(0,-1,0)),('front',(1,0,0)),('top',(0,0,1)),('isometric',(1,-1,.65))]:
 camera.location=center+Vector(direction).normalized()*45;camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();sc.render.filepath=str(root/(name+'.png'));bpy.ops.render.render(write_still=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
(root/'glb-inspection.json').write_text(json.dumps({'actual_import':'Blender glTF importer','study':'neutral clay only; source colour/texture not copied','source_sha256':sha(source),'source_bounds':[list(lo),list(hi)],'source_units':'uncalibrated; not engineering metres','source_meshes':len(objects),'render_sha256':{p.name:sha(p) for p in root.glob('*.png')},'use':'visual cross-section relationship only; no source vertices exported into the new recipe'},indent=2)+'\n')
