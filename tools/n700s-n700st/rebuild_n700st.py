#!/usr/bin/env python3
"""Rebuild only N700ST from the private source with the forest green livery."""
import argparse
import json
from pathlib import Path
import shutil
import sys

import numpy as np
import trimesh

from build import close_surface, load_pipeline, running_gear
from livery import N700ST_PALETTE, n700st_regions


def main(pipeline, source, root, producer):
    pipe = load_pipeline(pipeline)
    original_regions = pipe.style_regions()
    pipe.style_regions = lambda: n700st_regions(original_regions)
    pipe.PALETTE.update(N700ST_PALETTE)
    temporary = root / '_n700st_painted_source'
    if temporary.exists():
        shutil.rmtree(temporary)
    pipe.convert_set(source, temporary, producer)
    target = root / 'n700st'
    rows, units = [], {}
    for letter in pipe.SOURCE_FILES:
        path = temporary / 'models' / f'railway-n700s-{letter}.m3dmodel'
        triangles, colors, meta = pipe.decode(path.read_bytes())
        colors = colors[:, 0].copy()
        triangles = triangles.copy()
        triangles[:, :, 2] += .74
        triangles, colors, closure = close_surface(triangles, colors)
        gear, gear_colors = running_gear(np.ptp(triangles[:, :, 0]), cab=letter == 'a')
        triangles = np.concatenate((triangles, gear))
        colors = np.concatenate((colors, gear_colors))
        meta = dict(meta)
        meta.update(kind='Railway N700ST static visual candidate', producerCommit=producer,
                    visualChanges='white/forest-green photo based livery; original closed shell and running gear retained',
                    paintReference='four owner supplied chat photos, visually read; no logo or texture copied',
                    surfaceClosure=closure,
                    wheelRailPlane='provisional wheel tread z=0; source units, not certified metres',
                    limitations=['engineering dimensions and exact bogie anchors unverified',
                                 'complete 16-car formation unverified', 'no animation'])
        result = pipe.write_native(target / 'models' / f'railway-n700st-{letter}.m3dmodel',
                                   triangles, colors, meta)
        rows.append(result)
        units[letter] = (triangles, colors)
    placements, placed, painted, end = [], [], [], 0.
    for slot, index in enumerate(pipe.SOURCE_ORDER, 1):
        letter = chr(ord('a') + abs(index) - 1)
        triangles, colors = units[letter]
        triangles = triangles.copy()
        if index < 0:
            triangles[:, :, :2] *= -1
        length = np.ptp(triangles[:, :, 0])
        center = -(end + length / 2)
        triangles[:, :, 0] += center
        end += length + .4
        placed.append(triangles)
        painted.append(colors)
        placements.append(dict(slot=slot, unit=letter, reversed=index < 0,
                               translationX=float(center), rotationDegrees=180 if index < 0 else 0,
                               gapSourceUnits=.4, nativeModel=f'railway-n700st-{letter}.m3dmodel'))
    all_triangles = np.concatenate(placed)
    all_colors = np.concatenate(painted)
    shift = (all_triangles[:, :, 0].min() + all_triangles[:, :, 0].max()) / 2
    all_triangles[:, :, 0] -= shift
    for placement in placements:
        placement['translationX'] -= float(shift)
    aggregate = dict(kind='SOURCE_10_BODY_VISUAL_DRAFT_NOT_REAL_FORMATION', producerCommit=producer,
                     variant='n700st', placements=placements, triangles=len(all_triangles),
                     bounds=np.array([all_triangles.min((0, 1)), all_triangles.max((0, 1))]).tolist(),
                     sourceOrder=pipe.SOURCE_ORDER,
                     nativeAssembly='instantiate five individual M3DM units with placement transforms')
    mesh = trimesh.Trimesh(vertices=all_triangles.reshape(-1, 3) @ pipe.basis('+x'),
                           faces=np.arange(len(all_triangles) * 3).reshape(-1, 3), process=False)
    mesh.visual.face_colors = all_colors
    trimesh.Scene(mesh).export(target / 'models' / 'railway-n700st-source-ten-body-draft.glb')
    pipe.write_json(target / 'assembly.json', aggregate)
    pipe.write_json(target / 'conversion_report.json', dict(models=rows, assembly=aggregate))
    shutil.rmtree(temporary)
    print([(row['id'], row['triangles']) for row in rows])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--pipeline', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--producer-commit', required=True)
    arguments = parser.parse_args()
    main(arguments.pipeline, arguments.source, arguments.root, arguments.producer_commit)
