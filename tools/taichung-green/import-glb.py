import bpy,json,sys
from pathlib import Path
root=Path(sys.argv[sys.argv.index('--')+1]);manifest=json.loads((root/'manifest.json').read_text());rows=[]
for m in manifest['models']:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.import_scene.gltf(filepath=str(root/m['glb']))
 objs=[o for o in bpy.context.scene.objects if o.type=='MESH'];tri=sum(len(o.data.polygons) for o in objs)
 assert tri==m['triangles'],(m['id'],tri)
 # Blender importer maps glTF Y-up into Blender Z-up; native axis retained.
 pts=[o.matrix_world@v.co for o in objs for v in o.data.vertices]
 low=[min(p[i] for p in pts) for i in range(3)];high=[max(p[i] for p in pts) for i in range(3)]
 for got,expected in [(low,m['minimum']),(high,m['maximum'])]:assert max(abs(a-b) for a,b in zip(got,expected))<1e-4,(m['id'],got,expected)
 assert all(o.data.color_attributes for o in objs),'vertex colour missing'
 rows.append({'id':m['id'],'triangles':tri,'minimum':low,'maximum':high,'vertex_colors':True})
(root/'independent-glb.json').write_text(json.dumps({'importer':bpy.app.version_string,'status':'VERIFIED','models':rows},indent=2)+'\n')
