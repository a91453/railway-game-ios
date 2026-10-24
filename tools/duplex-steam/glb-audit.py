"""Independent Blender glTF importer audit; run with blender --background --python ... -- OUT."""
import bpy
import json
import sys
from pathlib import Path
from mathutils import Vector

root = Path(sys.argv[sys.argv.index('--')+1]).resolve()
manifest = json.loads((root/'manifest.json').read_text())
records=[]
for model in manifest['models']:
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(root/model['glb']))
    meshes=[obj for obj in bpy.context.scene.objects if obj.type=='MESH']
    points=[obj.matrix_world @ v.co for obj in meshes for v in obj.data.vertices]
    # Blender changes glTF Y up to Blender Z up; this yields native metre axes.
    low=[min(v[i] for v in points) for i in range(3)]
    high=[max(v[i] for v in points) for i in range(3)]
    count=sum(len(p.vertices)-2 for obj in meshes for p in obj.data.polygons)
    assert count==model['triangles'],(model['id'],count)
    for actual,expected in zip(low+high,model['minimum']+model['maximum']):
        assert abs(actual-expected)<0.0001,(model['id'],actual,expected)
    assert all(obj.data.color_attributes for obj in meshes)
    assert all(len(p.vertices)==3 for obj in meshes for p in obj.data.polygons)
    assert not bpy.data.images or all(image.name in {'Render Result','Viewer Node'} for image in bpy.data.images)
    for obj in meshes:
        for material in obj.data.materials:
            shader=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
            assert shader.inputs['Roughness'].default_value==1
            assert shader.inputs['Metallic'].default_value==0
    records.append({'id':model['id'],'triangles':count,'minimum':low,'maximum':high})
(root/'glb-import-verification.json').write_text(json.dumps({'status':'VERIFIED','importer':bpy.app.version_string,'checks':['independent glTF import','native metre bounds after axis conversion','triangle counts','vertex colors','triangle topology','matte nonmetal material and no textures'],'models':records},indent=2)+'\n')
print('VERIFIED independent Blender glTF decode for',len(records),'models')
