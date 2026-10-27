"""Independent Blender glTF importer: counts, coordinates, normals and materials."""
import bpy,json,sys
from pathlib import Path
from mathutils import Vector
root=Path(sys.argv[-1]);manifest=json.loads((root/'manifest.json').read_text());rows=[]
for model in manifest['models']:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.import_scene.gltf(filepath=str(root/model['glb']))
 meshes=[o for o in bpy.data.objects if o.type=='MESH']
 assert meshes and sum(len(o.data.polygons) for o in meshes)==model['triangles']
 vertices=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
 low=[min(v[k] for v in vertices) for k in range(3)];high=[max(v[k] for v in vertices) for k in range(3)]
 assert all(abs(low[k]-model['minimum'][k])<0.0003 and abs(high[k]-model['maximum'][k])<0.0003 for k in range(3)),(model['id'],low,high)
 assert all(p.area>0 and abs(p.normal.length-1)<0.001 for o in meshes for p in o.data.polygons)
 assert all(mat.use_nodes for o in meshes for mat in o.data.materials)
 rows.append({'id':model['id'],'triangles':model['triangles'],'minimum_native_m':low,'maximum_native_m':high})
(root/'glb-import-verification.json').write_text(json.dumps({'status':'VERIFIED','tool':bpy.app.version_string,'checks':['independent glTF import','triangle counts','native axes and bounds','nondegenerate unit face normals','imported node materials'],'models':rows},indent=2)+'\n')
print('VERIFIED Blender GLB import, counts, native bounds, normals and material nodes')
