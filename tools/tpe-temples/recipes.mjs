// Decision 725: each temple's recipe, and the game's colours for the parts.
// `files`: the KMZ (unzipped folders) of one temple, the first giving its
// point. `eave`: metres above the model's own zero under which an upward
// face is paving, not roof. `dark`: lightness under which a wall face is an
// opening. `dropMaterials`: the source's ground and terrain, by material.
// `keep`: rectangles (west, south, east, north metres from the point) the
// temple's faces are kept within. `triangles`, `maxError`: the simplifier's
// target and its error limit (metres). `tint`: which shade of a part.

// Light to dark within a temple: paving and walls, roof, column, opening.
// The roof tiles are the temples' own families (terracotta, brown glaze,
// slate), deep enough to stand off the map's near-white ground (decision
// 722's ΔL* 12); walls, columns and stone take decision 457's pale
// landmark colours.
export const colours = {
  roof: { default: 0xC0805F, brown: 0xA0705E, slate: 0x8F969E, green: 0x7E9E8A },
  ridge: { default: 0xD9B76C },
  wall: { default: 0xF0E8DD, brick: 0xDDA996 },
  stone: { default: 0xD9D2C6 },
  column: { default: 0xD08A7E },
  soffit: { default: 0xB98B78 },
  opening: { default: 0x6E5F5A },
  paving: { default: 0xE0D8CA },
};

export const recipes = [
  { id: 'tpe-temple-longshan', files: ['108003', '108003A'], eave: 4, dark: 0.16, dropMaterials: { 108003: ['material_15'] },
    triangles: 6000, maxError: 0.3, tint: { roof: 'brown' } },
  { id: 'tpe-temple-xingtian', files: ['104001'], eave: 4, dark: 0.16, dropMaterials: { 104001: ['material_121'] },
    triangles: 5000, maxError: 0.3 },
  { id: 'tpe-temple-zhinan', files: ['116001'], eave: 4, dark: 0.16, dropMaterials: { 116001: ['material_11'] },
    triangles: 5000, maxError: 0.3, tint: { roof: 'brown' } },
  { id: 'tpe-temple-provincial-city-god', files: ['100001'], eave: 4, dark: 0.16, triangles: 3000, maxError: 0.2 },
  { id: 'tpe-temple-xiahai-city-god', files: ['103002'], eave: 4, dark: 0.16, triangles: 3000, maxError: 0.2 },
  { id: 'tpe-temple-tianhou', files: ['108001'], eave: 4, dark: 0.16, dropMaterials: { 108001: ['material_18'] },
    triangles: 3000, maxError: 0.2 },
  { id: 'tpe-temple-qingshui', files: ['108004'], eave: 4, dark: 0.16, triangles: 3000, maxError: 0.2 },
  { id: 'tpe-church-jinan', files: ['100005'], eave: 6, dark: 0.16, stoneWalls: true, triangles: 5000, maxError: 0.3,
    tint: { roof: 'slate', wall: 'brick' } },
  { id: 'tpe-temple-cixian', files: ['111001_01'], eave: 4, dark: 0.16, triangles: 4000, maxError: 0.3 },
  { id: 'tpe-temple-huiji', files: ['111003', '111003_archway'], eave: 4, dark: 0.16, dropMaterials: { 111003: ['material_0'] },
    triangles: 5000, maxError: 0.3 },
];
