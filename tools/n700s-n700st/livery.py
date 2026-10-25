"""Owner photo based N700ST paint, in the supplied body's UV coordinates.

The source converter clips these polygons into the existing shell triangles.
There are no unsupported decals or photographic textures in the output.
"""
import numpy as np

N700ST_PALETTE = {
    'body': 0xF6F6F4, 'roof': 0xEDEFF0, 'skirt': 0x8F959B,
    'stripe': 0x1D4A44,
}


def n700st_regions(source_regions):
    """Keep doors, windows and equipment; reshape only the first cab side band.

    UV +X runs from nose toward the rear on the first atlas panel. The green
    starts on the shoulder, broadens beneath the cab doors, and narrows to a
    straight side band. The nose tip remains white as in the four photos.
    """
    regions = [(name, points) for name, points in source_regions
               if not (name == 'stripe' and np.min(points[:, 1]) < 450)]
    x = [390, 440, 500, 540, 610, 660, 1024]
    upper = [386, 380, 371, 376, 384, 386, 387]
    lower = [386, 400, 435, 445, 440, 415, 415]
    for i in range(len(x) - 1):
        polygon = np.array([(x[i], upper[i]), (x[i+1], upper[i+1]),
                            (x[i+1], lower[i+1]), (x[i], lower[i])], dtype=float)
        if i == 0:
            polygon = polygon[:3]
        regions.append(('stripe', polygon))
    return regions
