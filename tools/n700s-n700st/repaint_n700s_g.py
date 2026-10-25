#!/usr/bin/env python3
"""Make the game-original N700S-G from the private blue-stripe native units.

This only replaces the authored navy stripe colour with the game's existing
deep green. The five source units, their triangles and all other face colours
remain byte-for-byte equal after native readback.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

import numpy as np
import trimesh

from build import load_pipeline

BLUE = np.array([0x2B, 0x33, 0x56, 0xFF], dtype=np.uint8)
GAME_GREEN = np.array([0x1D, 0x4A, 0x44, 0xFF], dtype=np.uint8)


def main(pipeline, root, producer):
    pipe = load_pipeline(pipeline)
    original = root / 'n700s'
    target = root / 'n700s-g'
    (target / 'models').mkdir(parents=True, exist_ok=True)
    rows = []
    for letter in 'abcde':
        source = original / 'models' / f'railway-n700s-{letter}.m3dmodel'
        triangles, vertex_colors, metadata = pipe.decode(source.read_bytes())
        assert np.all(vertex_colors == vertex_colors[:, :1, :])
        colors = vertex_colors[:, 0].copy()
        stripe = np.all(colors == BLUE, axis=1)
        if not stripe.any():
            raise ValueError(f'No original N700S blue stripe in unit {letter}')
        colors[stripe] = GAME_GREEN
        metadata = dict(metadata)
        metadata.update(kind='Railway N700S-G static game-original livery',
                        producerCommit=producer,
                        baseNativeSha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                        paint='only the original N700S navy stripe changed to game deep green #1D4A44',
                        recolouredTriangles=int(stripe.sum()))
        output = target / 'models' / f'railway-n700s-g-{letter}.m3dmodel'
        rows.append(pipe.write_native(output, triangles, colors, metadata))
        readback, actual, _ = pipe.decode(output.read_bytes())
        if not np.array_equal(readback, triangles):
            raise ValueError(f'Geometry changed in unit {letter}')
        if not np.array_equal(actual[:, 0], colors):
            raise ValueError(f'Paint readback changed in unit {letter}')
    source_assembly = json.loads((original / 'assembly.json').read_text())
    assembly = copy.deepcopy(source_assembly)
    assembly.update(variant='n700s-g', producerCommit=producer,
                    kind='SOURCE_10_BODY_VISUAL_DRAFT_NOT_REAL_FORMATION',
                    livery='game-original deep green stripe; original N700S and orange N700ST retained')
    for placement in assembly['placements']:
        placement['nativeModel'] = placement['nativeModel'].replace('railway-n700s-', 'railway-n700s-g-')
    placed, painted = [], []
    for placement in assembly['placements']:
        path = target / 'models' / placement['nativeModel']
        triangles, colors, _ = pipe.decode(path.read_bytes())
        if placement['reversed']:
            triangles[:, :, :2] *= -1
        triangles[:, :, 0] += placement['translationX']
        placed.append(triangles)
        painted.append(colors[:, 0])
    all_triangles = np.concatenate(placed)
    all_colors = np.concatenate(painted)
    if len(all_triangles) != source_assembly['triangles']:
        raise ValueError('Assembly triangle count changed')
    mesh = trimesh.Trimesh(vertices=all_triangles.reshape(-1, 3) @ pipe.basis('+x'),
                           faces=np.arange(len(all_triangles) * 3).reshape(-1, 3), process=False)
    mesh.visual.face_colors = all_colors
    trimesh.Scene(mesh).export(target / 'models' / 'railway-n700s-g-source-ten-body-draft.glb')
    pipe.write_json(target / 'assembly.json', assembly)
    pipe.write_json(target / 'conversion_report.json', dict(models=rows, assembly=assembly))
    print([(row['id'], row['triangles']) for row in rows])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--pipeline', type=Path, required=True)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--producer-commit', required=True)
    args = parser.parse_args()
    main(args.pipeline, args.root, args.producer_commit)
