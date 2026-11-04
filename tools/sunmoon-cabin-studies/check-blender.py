import bpy,json,sys,struct
from pathlib import Path
root=Path(sys.argv[sys.argv.index('--')+1]).resolve()
(root/'blender-verification.json').unlink(missing_ok=True)
mf=json.loads((root/'manifest.json').read_text());rows=[]
for m in mf['models']:
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 bpy.ops.import_scene.gltf(filepath=str(root/m['glb']))
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];n=sum(len(o.data.polygons) for o in meshes)
 assert n==m['triangles'],(m['id'],n)
 assert all(len(p.vertices)==3 for o in meshes for p in o.data.polygons)
 mats={mat.name.split('.')[0] for o in meshes for mat in o.data.materials}
 assert {'inspection-glass-native-flag2','matte-vertex-colour','native-interior-lamp'}<=mats
 for o in meshes:assert len(o.data.color_attributes)>0
 raw=(root/m['native']).read_bytes();count,plen=struct.unpack_from('<II',raw,8);start=16+(plen+3)//4*4
 points=[struct.unpack_from('<fff',raw,start+i*52+4+j*16) for i in range(count) for j in range(3)]
 native_bounds=[[min(p[k] for p in points) for k in range(3)],[max(p[k] for p in points) for k in range(3)]]
 world=[o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
 actual=[[min(p[k] for p in world) for k in range(3)],[max(p[k] for p in world) for k in range(3)]]
 assert max(abs(a-b) for x,y in zip(native_bounds,actual) for a,b in zip(x,y))<1e-5,(m['id'],native_bounds,actual)
 rows.append(dict(id=m['id'],triangles=n,materials=sorted(mats),world_bounds_native_axes=actual))
(root/'blender-verification.json').write_text(json.dumps({'status':'VERIFIED','blender':bpy.app.version_string,'checks':'Independent glTF import, mesh triangles/materials/vertex-colour attributes and world bounds/axes; not iOS evidence','models':rows},indent=2)+'\n')
print('VERIFIED independent Blender import',len(rows))
