"""OLD-PORT-AUDIT: stop when an encoded landmark carries a ground plate.

The owner's earlier version's buildings often bring their own lot with
them: Fukuoka Tower's file begins with a 40 m square of plaza lying on the
ground (about 1 in 40 of the earlier catalogue's models has one as a
material of its own). The map draws its own ground and roads, so a model
that goes into the game leaves it out. `check` reads a model as
`tools/landmarks/glb_to_swift.py` encodes it and stops when level faces looking up, lying
on the model's lowest level, reach beyond its body (the box round
everything more than a metre, or an eighth of its height, above its foot)
by more than `LIMIT` square metres. Leave the plate out (as
`tools/fukuoka-map/fukuoka_tower.py`'s `PAINT` does) or, when it belongs
(a pier's deck, a forecourt), pass the tool's `--allow-ground-plate`.

`Map3DLandmarkGroundPlateTests` holds the models already in the game to
the same rule.
"""

import math
import struct

# The Bank of China Tower's corner garden is 8.7 m2; Fukuoka Tower's plaza 1,200.
LIMIT = 25.0


def plate_area(data, signed_z=False):
    """Square metres of ground plate beyond the body of the model `data`."""
    count = struct.unpack_from("<H", data, 0)[0]
    points = []
    for i in range(count):
        x, y, z = struct.unpack_from("<hh" + ("h" if signed_z else "H"), data, 2 + 6 * i)
        points.append((x / 100, y / 100, z / 100))
    at = 2 + 6 * count
    triangles = struct.unpack_from("<H", data, at)[0]
    low = min(p[2] for p in points)
    height = max(p[2] for p in points) - low
    body = [p for p in points if p[2] > low + max(1.0, 0.12 * height)]
    if not body:
        return 0.0
    box = (min(p[0] for p in body) - 0.5, min(p[1] for p in body) - 0.5, max(p[0] for p in body) + 0.5, max(p[1] for p in body) + 0.5)
    area = 0.0
    for i in range(triangles):
        a, b, c = (points[k] for k in struct.unpack_from("<HHH", data, at + 2 + 7 * i))
        if max(a[2], b[2], c[2]) > low + 0.05:
            continue
        u, v = [b[k] - a[k] for k in range(3)], [c[k] - a[k] for k in range(3)]
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        length = math.sqrt(sum(k * k for k in n))
        if length == 0 or n[2] / length < 0.98:
            continue
        if any(not (box[0] <= p[0] <= box[2] and box[1] <= p[1] <= box[3]) for p in (a, b, c)):
            area += length / 2
    return area


def check(data, name, signed_z=False, allow=False):
    area = plate_area(data, signed_z)
    if area > LIMIT and not allow:
        raise SystemExit(f"{name}: {area:.0f} m2 of ground plate lies beyond its body; leave it out, "
                         "or pass --allow-ground-plate if it belongs (tools/landmarks/ground_plate.py)")
    return area
