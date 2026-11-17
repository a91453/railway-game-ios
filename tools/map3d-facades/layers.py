"""Decision 817: the five facade layers of Map3DSurfaces.png.

Draws `flatBalconies`, `officeRibbon`, `curtainSpandrel`, `officeFins` and
`hkWindows` (Map3DSurface 24 to 28) and writes them in at their place,
appending them when the file holds only the first 24 layers and replacing
them when they are already there; the other layers stay as they are.

    python3 -I tools/map3d-facades/layers.py RailwayGameApp/Resources/Map3D/Map3DSurfaces.png

Each layer is 256 x 256, one bay of one floor, the floor's top at the top
of the image: its colour on the left and its tint mask on the right (white
takes the vertex's colour, the wall's; black keeps the layer's own, glass
where it is dark). Flat shapes only, drawn here, no photograph (art-style
section 7): the shader reads a layer's brightness as a faint pattern on the
wall's own colour, its dark untinted pixels as the glass lit at night.

Proportions after the owner's Taipei city packs (`Railway/tw3d-reference-clean`,
`js/taipei-facades.js`: a home's window 0.52-0.62 of its bay and 0.30-0.78
of its floor, an office's 0.86 and 0.08-0.94, balcony slabs on the towers;
`Railway/slop-taipei-reference-clean`, Taipei_Basin_3D_Clean `js/buildings.js`
family 9's ribbon windows 0.80 x 0.42; MIT, slop-newyork). Needs Pillow and
NumPy.
"""
import sys

import numpy as np
from PIL import Image

SIDE = 256
FIRST = 24  # Map3DSurface.flatBalconies' raw value
WALL = 131  # the atlas's mid wall grey (flatWindows' wall)
GLASS = (44, 63, 82)  # flatWindows' glass
OFFICE_GLASS = (52, 80, 103)  # officeGlass's
FRAME = (189, 195, 200)  # flatWindows' frames
UNIT = (206, 208, 206)  # an air conditioner's casing


class Layer:
    def __init__(self, seed):
        rng = np.random.default_rng(seed)
        self.colour = np.clip(WALL + rng.normal(0, 2.5, (SIDE, SIDE)), 0, 255)[..., None].repeat(3, axis=2)
        self.mask = np.full((SIDE, SIDE), 255.0)

    def fill(self, x0, y0, x1, y1, colour, tint=False):
        """A rectangle, columns x0..x1 and rows y0..y1 from the top."""
        self.colour[y0:y1, x0:x1] = colour
        self.mask[y0:y1, x0:x1] = 255 if tint else 0

    def shade(self, x0, y0, x1, y1, grey):
        """A band of the wall itself, lighter or darker, still tinted."""
        self.colour[y0:y1, x0:x1] = grey
        self.mask[y0:y1, x0:x1] = 255

    def glass(self, x0, y0, x1, y1, colour=GLASS):
        """Glass a little lighter toward its top, as the layers' panes are."""
        rows = np.linspace(1.08, 0.94, y1 - y0)[:, None, None]
        self.colour[y0:y1, x0:x1] = np.clip(np.array(colour, float)[None, None, :] * rows, 0, 255)
        self.mask[y0:y1, x0:x1] = 0

    def frame(self, x0, y0, x1, y1, width=4):
        for box in ((x0, y0, x1, y0 + width), (x0, y1 - width, x1, y1), (x0, y0, x0 + width, y1), (x1 - width, y0, x1, y1)):
            self.fill(*box, FRAME)

    def image(self):
        colour = np.clip(self.colour, 0, 255).astype(np.uint8)
        mask = np.repeat(self.mask[..., None], 3, axis=2).astype(np.uint8)
        return np.concatenate([colour, mask], axis=1)


def balconies():
    """A tower of flats (大樓住宅): full-height glass doors behind a solid
    balcony parapet, an air conditioner on the balcony, the slab of the
    balcony above at the top."""
    layer = Layer(817)
    layer.shade(0, 0, SIDE, 14, 152)  # the slab over it
    layer.shade(0, 14, SIDE, 18, 112)
    layer.glass(18, 30, 238, 168)
    layer.frame(18, 30, 238, 168, 5)
    for x in (88, 160):
        layer.fill(x, 30, x + 5, 168, FRAME)
    layer.fill(178, 120, 232, 160, UNIT)  # the air conditioner, its top over the parapet
    layer.fill(184, 128, 226, 132, (150, 152, 150))
    layer.fill(184, 138, 226, 142, (150, 152, 150))
    layer.shade(0, 156, SIDE, 162, 182)  # the parapet's coping
    layer.shade(0, 162, SIDE, 248, 158)  # the parapet
    layer.shade(0, 248, SIDE, SIDE, 118)  # its foot's shadow line
    return layer


def ribbon():
    """An office of ribbon windows (帶狀窗): a band of glass the whole bay
    wide, mullions every quarter, solid spandrels over and under it."""
    layer = Layer(818)
    layer.shade(0, 0, SIDE, 6, 122)  # the joint between two spandrel panels
    layer.glass(0, 62, SIDE, 186, OFFICE_GLASS)
    for x in (0, 64, 128, 192):
        layer.fill(x, 62, x + 4, 186, FRAME)
    layer.fill(0, 58, SIDE, 62, FRAME)
    layer.fill(0, 186, SIDE, 192, (200, 202, 204))  # the sill
    layer.shade(0, 192, SIDE, 196, 116)
    return layer


def curtain():
    """A glass curtain wall with its spandrel band (窗間橫帶): glass from
    floor to the next floor's spandrel, a mullion at each half bay, the
    opaque panel band over the slab pale."""
    layer = Layer(819)
    layer.glass(0, 0, SIDE, 196, OFFICE_GLASS)
    for x in (0, 126):
        layer.fill(x, 0, x + 4, 196, (150, 160, 170))
    layer.fill(0, 0, SIDE, 3, (150, 160, 170))
    layer.fill(0, 196, SIDE, 200, (120, 128, 136))
    layer.fill(0, 200, SIDE, SIDE, (178, 186, 192))  # the spandrel panel
    layer.fill(0, 252, SIDE, SIDE, (150, 160, 170))
    return layer


def fins():
    """An office behind vertical sun fins (直條遮陽鰭): two tall narrow
    windows a bay, a pale pier between them and at its edges (the fins
    stand out of these, near), a dark line at each floor."""
    layer = Layer(820)
    layer.shade(0, 0, SIDE, SIDE, 160)  # the piers
    for x0, x1 in ((30, 116), (140, 226)):
        layer.glass(x0, 16, x1, 236, OFFICE_GLASS)
        layer.fill(x0, 120, x1, 124, FRAME)
    layer.shade(0, 236, SIDE, 248, 132)
    layer.shade(0, 248, SIDE, SIDE, 112)
    return layer


def hong_kong():
    """A Hong Kong flat's bay (香港密窗): a bay window (凸窗) of three panes
    in a pale frame, its hood and sill, a narrow bathroom window beside it
    over a window air conditioner."""
    layer = Layer(821)
    layer.fill(16, 34, 172, 44, (196, 198, 196))  # the hood
    layer.glass(24, 44, 164, 194)
    layer.frame(24, 44, 164, 194, 6)
    for x in (68, 114):
        layer.fill(x, 44, x + 5, 194, FRAME)
    layer.fill(16, 194, 172, 210, (188, 190, 188))  # the sill
    layer.shade(16, 210, 172, 214, 112)
    layer.glass(192, 54, 238, 140)
    layer.frame(192, 54, 238, 140, 4)
    layer.fill(188, 160, 242, 206, UNIT)
    for y in range(166, 202, 7):
        layer.fill(194, y, 236, y + 3, (160, 162, 160))
    return layer


def main(path):
    image = np.array(Image.open(path).convert("RGB"))
    assert image.shape[1] == 2 * SIDE and image.shape[0] % SIDE == 0, image.shape
    layers = [balconies(), ribbon(), curtain(), fins(), hong_kong()]
    keep = min(image.shape[0] // SIDE, FIRST)
    assert keep == FIRST, "the file must hold the 24 layers before these"
    out = np.concatenate([image[: FIRST * SIDE]] + [layer.image() for layer in layers], axis=0)
    Image.fromarray(out, "RGB").save(path, optimize=True)


if __name__ == "__main__":
    main(sys.argv[1])
