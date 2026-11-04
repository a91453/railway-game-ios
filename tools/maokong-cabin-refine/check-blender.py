import bpy,json,sys
from pathlib import Path
root=Path(sys.argv[sys.argv.index('--')+1]).resolve()
mf=json.loads((root/'manifest.json').read_text());rows=[]
for m in mf['models']:
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 bpy.ops.import_scene.gltf(filepath=str(root/m['glb']))
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];n=sum(len(o.data.polygons) for o in meshes)
 assert n==m['triangles'],(m['id'],n)
 assert all(len(p.vertices)==3 for o in meshes for p in o.data.polygons)
 mats={mat.name.split('.')[0] for o in meshes for mat in o.data.materials}
 assert 'inspection-glass-native-flag2' in mats and 'matte-vertex-colour' in mats
 for o in meshes:assert len(o.data.color_attributes)>0
 rows.append(dict(id=m['id'],triangles=n,materials=sorted(mats)))
(root/'blender-verification.json').write_text(json.dumps({'status':'VERIFIED','blender':bpy.app.version_string,'checks':'Independent glTF import, mesh triangles/materials/vertex-colour attributes; not iOS evidence','models':rows},indent=2)+'\n')
print('VERIFIED independent Blender import',len(rows))
