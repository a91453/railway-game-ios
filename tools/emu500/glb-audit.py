import bpy, json, sys
from pathlib import Path
root=Path(sys.argv[-1]);manifest=json.loads((root/'manifest.json').read_text());rows=[]
for model in manifest['models']:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.import_scene.gltf(filepath=str(root/model['glb']))
 meshes=[o for o in bpy.data.objects if o.type=='MESH']
 assert meshes and sum(len(o.data.polygons) for o in meshes)==model['triangles']
 rows.append({'id':model['id'],'triangles':model['triangles']})
(root/'glb-import-verification.json').write_text(json.dumps({'status':'VERIFIED','tool':'Blender','models':rows},indent=2)+'\n')
print('VERIFIED Blender imported all GLB meshes')
