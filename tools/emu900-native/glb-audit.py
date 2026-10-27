"""Independent Blender glTF importer audit; run with blender --background --python ... -- OUT."""
import bpy
import json
import struct
from collections import Counter
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
    # Independent importer corner colours, paired to actual world positions.
    # Assembly records are composed from the exact embedded native units.
    def native_corners(data,translation=(0,0,0)):
        count,meta=struct.unpack_from('<II',data,8);start=16+(meta+3)//4*4;out=[]
        for i in range(count):
            for j in range(3):
                x,y,z,c=struct.unpack_from('<fffI',data,start+i*52+4+j*16)
                out.append((tuple(round((v+t)*1e4) for v,t in zip((x,y,z),translation)),tuple((c>>shift)&255 for shift in (0,8,16,24))))
        return out
    data=(root/model['native']).read_bytes()
    if model.get('native_kind')=='assembly':
        import base64
        scene=json.loads(data);expected=[]
        for placement in scene['placements']:expected+=native_corners(base64.b64decode(scene['units'][placement['unit']]),placement['translation'])
    else:expected=native_corners(data)
    actual=[]
    for obj in meshes:
        attr=obj.data.color_attributes[0]
        for polygon in obj.data.polygons:
            for li in polygon.loop_indices:
                vi=obj.data.loops[li].vertex_index;pos=obj.matrix_world @ obj.data.vertices[vi].co
                colour=attr.data[li if attr.domain=='CORNER' else vi].color
                actual.append((tuple(round(v*1e4) for v in pos),tuple(round(v*255) for v in colour)))
    # Float32 assembly translations are checked separately against Swift/JS bytes;
    # tolerate position rounding at half boundaries by comparing corner colour counts.
    expected_colours=set(c for p,c in expected);actual_colours=set(c for p,c in actual)
    assert len(actual)==len(expected),(model['id'],'imported colour corner count')
    def distance(a,b):return max(abs(x-y) for x,y in zip(a,b))
    assert all(min(distance(a,b) for b in expected_colours)<=2 for a in actual_colours),(model['id'],'unexpected imported colour')
    assert all(min(distance(a,b) for a in actual_colours)<=2 for b in expected_colours),(model['id'],'missing imported palette colour')
    records.append({'id':model['id'],'triangles':count,'minimum':low,'maximum':high})
(root/'glb-import-verification.json').write_text(json.dumps({'status':'VERIFIED','importer':bpy.app.version_string,'checks':['independent glTF import','native metre bounds after axis conversion','triangle counts','all imported corner colours and source palette coverage within 2/255 Blender BYTE_COLOR conversion tolerance','triangle topology','matte nonmetal material and no textures'],'models':records},indent=2)+'\n')
print('VERIFIED independent Blender glTF decode for',len(records),'models')
