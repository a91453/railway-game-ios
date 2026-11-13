// Decision 725: each temple's recipe, and the game's colours for the parts.
// `files`: the KMZ (unzipped folders) of one temple, the first giving its
// point. `eave`: metres above the ground under which an upward face is
// paving, not roof. `dark`: the most lightness a wall face may have and be
// an opening (default 0.3; never more than 45% of the temple's own walls). `dropMaterials`: the source's ground and terrain, by material.
// `keep`: rectangles (west, south, east, north metres from the point) the
// temple's faces are kept within. `triangles`, `maxError`: the simplifier's
// target and its error limit (metres). `tint`: which shade of a part.

// Each part has a few game colours; a block of faces (one part, joined by
// their edges: build.mjs's blockColours) takes the one nearest the mean
// colour of the photo under it (or the recipe's `tint`), so a temple's red
// wooden front, grey stone base and green-glazed ridge stay as they are,
// in the game's colours. The roof tiles (terracotta, brown, slate) are
// deep enough to stand off the map's near-white ground (decision 722's
// ΔL* 12); the pale ones are decision 457's landmark colours.
export const colours = {
  roof: { default: 0xC0805F, slate: 0x8F969E, green: 0x7E9E8A },
  ridge: { default: 0xD9B76C, green: 0x6F9A86, red: 0xB8553A },
  wall: { default: 0xF0E8DD, brick: 0xB86A55, redwood: 0x9A4A3C, darkwood: 0x6E4A40, stone: 0xB9B4AA },
  column: { default: 0xD08A7E, deep: 0xA8473A },
  soffit: { default: 0xB98B78, dark: 0x7A5A50 },
  opening: { default: 0x6E5F5A, dark: 0x3F3A38 },
  paving: { default: 0xE0D8CA, grey: 0xB8B4AC },
};

// Then every colour is lightened: its lightness (L*) taken `share` of the
// way toward the lightness of `toward`, the paving of decision 720's map
// (its option C), its colour (a*, b*) kept at `chroma`, so the temples
// sit in the map's light look without turning grey; an opening goes half
// as far, to stay a dark hole.
export const soften = { toward: 0xE4E3DF, share: 0.35, chroma: 0.9 };

export const recipes = [
  { id: 'tpe-temple-longshan', files: ['108003', '108003A'], eave: 4, dropMaterials: { 108003: ['material_15'] },
    triangles: 6000, maxError: 0.3 },
  { id: 'tpe-temple-xingtian', files: ['104001'], eave: 4, dropMaterials: { 104001: ['material_121'] },
    triangles: 5000, maxError: 0.3 },
  { id: 'tpe-temple-zhinan', files: ['116001'], eave: 4, dropMaterials: { 116001: ['material_11'] },
    triangles: 5000, maxError: 0.3 },
  { id: 'tpe-temple-provincial-city-god', files: ['100001'], eave: 4, triangles: 3000, maxError: 0.2 },
  { id: 'tpe-temple-xiahai-city-god', files: ['103002'], eave: 4, dropMaterials: { 103002: ['material_3'] }, triangles: 3000, maxError: 0.2 },
  { id: 'tpe-temple-tianhou', files: ['108001'], eave: 4, dropMaterials: { 108001: ['material_18'] },
    triangles: 3000, maxError: 0.2 },
  { id: 'tpe-temple-qingshui', files: ['108004'], eave: 4, keep: [[-10, -30, 50, 25]], triangles: 3000, maxError: 0.2 },
  { id: 'tpe-church-jinan', files: ['100005'], eave: 6, triangles: 5000, maxError: 0.3,
    tint: { roof: 'slate', wall: 'brick' } },
  { id: 'tpe-temple-cixian', files: ['111001_01'], eave: 4, triangles: 4000, maxError: 0.3 },
  { id: 'tpe-temple-huiji', files: ['111003'], eave: 4, dropMaterials: { 111003: ['material_0'] },
    triangles: 5000, maxError: 0.3 },
];
