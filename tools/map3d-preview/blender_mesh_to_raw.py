#!/usr/bin/env python3
# Decision 457: a model of the reference repository's blender-buildings-v1
# (near.mesh.bin: position and normal, 24 bytes a vertex, three a
# triangle, coloured by model.json's drawGroups) as Map3DLandmarkStudio's
# raw file: 12 floats a vertex, colours in sRGB. For comparison pictures
# only; the game does not load these meshes.
#
#   python3 -I blender_mesh_to_raw.py <model folder> <out.raw>
import json
import struct
import sys

source, out = sys.argv[1], sys.argv[2]
with open(source + '/model.json') as f:
    lod = json.load(f)['lods']['near']
with open(source + '/' + lod['file'], 'rb') as f:
    data = f.read()
values = struct.unpack('<%df' % (len(data) // 4), data)
floats = []
for group in lod['drawGroups']:
    rgb = [min(1.0, c ** (1 / 2.2)) for c in group['color']]
    for i in range(group['start'], group['start'] + group['count']):
        floats += list(values[i * 6:i * 6 + 6]) + rgb + [0, 0, -1]
with open(out, 'wb') as f:
    f.write(struct.pack('<%df' % len(floats), *floats))
