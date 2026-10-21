import {writeFileSync, mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
import {PALETTE, MeshBuilder} from './mesh-builder.mjs';

const outputDir = resolve(process.argv[2] || 'C:/Users/11407/.gemini/antigravity/scratch/railway-reference-private/Railway/game-art-previews/docs/art/commercial-kit-2026-10-21');
const modelsDir = resolve(outputDir, 'models');
mkdirSync(modelsDir, {recursive: true});

function writeM3DModel(filePath, id, vertices, fidelity = 'remixed-native-game-asset') {
  const triangleCount = vertices.length / 3;
  const provenance = {
    asset: {generator: 'Map3DCommercialKit', version: '2.0'},
    extras: {
      assetId: id,
      recipeVersion: 2,
      source: 'native-procedural',
      fidelity,
      coordinateSystem: 'metres; +x front, +y left, +z up'
    }
  };
  const provText = Buffer.from(JSON.stringify(provenance));
  const pad = (4 - (provText.length % 4)) % 4;

  const header = Buffer.alloc(16);
  header.write('M3DM', 0, 4, 'ascii');
  header.writeUInt16LE(1, 4);
  header.writeUInt16LE(0, 6);
  header.writeUInt32LE(triangleCount, 8);
  header.writeUInt32LE(provText.length, 12);

  const triBuffer = Buffer.alloc(triangleCount * 52);
  let offset = 0;
  for (let i = 0; i < triangleCount; i++) {
    const v0 = vertices[i * 3];
    const v1 = vertices[i * 3 + 1];
    const v2 = vertices[i * 3 + 2];
    const flag = (v0.glows || v1.glows || v2.glows) ? 1 : 0;
    triBuffer.writeUInt32LE(flag, offset);
    offset += 4;

    for (const v of [v0, v1, v2]) {
      triBuffer.writeFloatLE(v.x, offset);
      triBuffer.writeFloatLE(v.y, offset + 4);
      triBuffer.writeFloatLE(v.z, offset + 8);
      triBuffer.writeUInt32LE(v.color >>> 0, offset + 12);
      offset += 16;
    }
  }

  const out = Buffer.concat([header, provText, Buffer.alloc(pad), triBuffer]);
  writeFileSync(filePath, out);
  return out;
}

// -------------------------------------------------------------
// 12 Commercial Buildings
// -------------------------------------------------------------

function buildDepartmentStore() {
  const b = new MeshBuilder();
  // 1F-2F Podium with dark plinth, arcade colonnade and warm display windows
  b.box(0, 0, 0, 19, 23, 7.0, PALETTE.warmWhite);
  b.box(0, 0, 0, 19.4, 23.4, 0.45, PALETTE.darkRoof);
  b.pane(9.55, 0.45, -5.5, 6.0, 3.2, PALETTE.darkRoof, PALETTE.warmGlow);
  b.pane(9.55, 0.45, 5.5, 6.0, 3.2, PALETTE.darkRoof, PALETTE.warmGlow);
  for (const pz of [-10, -5, 0, 5, 10]) {
    b.box(9.6, 0.45, pz, 0.45, 0.45, 6.5, PALETTE.concrete);
  }
  b.pane(9.55, 0.45, 0, 3.6, 3.2, PALETTE.chrome, PALETTE.glazing);
  b.commAwning(10.6, 4.2, 0, 2.5, 9.0, 0.25, PALETTE.commBlue);
  for (const pz of [-4, 4]) {
    b.beam([9.7, 5.8, pz], [11.8, 4.4, pz], 0.06, PALETTE.steel);
  }

  // 3F-5F Main shopping block with architectural sunshade fins
  b.box(-0.5, 7.0, 0, 16.5, 20.5, 9.0, PALETTE.tileWhite);
  for (let i = -8; i <= 8; i++) {
    b.box(7.85, 7.5, i * 1.1, 0.22, 0.08, 8.0, PALETTE.counters0);
  }
  b.commWindowBand(-0.5, 7.2, 0, 16.5, 20.5, 3, 5, PALETTE.playerRim, PALETTE.darkGlass);

  // Rooftop terrace, parapet, water tank and LED billboard
  b.box(-0.5, 16.0, 0, 16.8, 20.8, 0.4, PALETTE.concrete);
  b.box(-0.5, 16.4, 0, 16.2, 20.2, 0.65, PALETTE.roof);
  b.box(5.5, 16.4, 0, 0.08, 14.0, 1.0, PALETTE.glazing);
  b.box(-3.5, 16.4, 4.5, 5.0, 6.5, 3.2, PALETTE.concrete);
  b.waterTank(-3.5, 16.4, -4.5, 1.1, 1.6);
  b.box(6.2, 16.4, -7.0, 0.35, 6.0, 3.5, PALETTE.steel);
  b.box(6.4, 16.6, -7.0, 0.05, 5.6, 3.1, PALETTE.trainYellow, 1);
  return b;
}

function buildCinema() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 17, 15, 12, PALETTE.warmWhite);
  b.box(8.55, 0, 0, 0.45, 9.0, 14.5, PALETTE.commCyan);
  b.box(8.65, 0, 0, 0.55, 5.0, 16.0, PALETTE.templeRidge);
  b.box(8.75, 0, 0, 0.65, 2.2, 17.2, PALETTE.trainYellow);

  b.box(10.0, 4.2, 0, 3.2, 11.0, 0.55, PALETTE.darkRoof);
  b.box(10.0, 4.0, 0, 3.0, 10.6, 0.15, PALETTE.warmGlow, 1);
  b.beam([8.8, 8.5, -4.5], [11.2, 4.7, -4.5], 0.08, PALETTE.steel);
  b.beam([8.8, 8.5, 4.5], [11.2, 4.7, 4.5], 0.08, PALETTE.steel);

  b.box(10.2, 7.5, 0, 0.45, 0.85, 7.5, PALETTE.commCrimson);
  b.box(10.45, 7.8, 0, 0.10, 0.65, 6.8, PALETTE.warmGlow, 1);

  for (const pz of [-3.8, 0, 3.8]) {
    b.box(8.6, 1.2, pz, 0.18, 1.8, 2.4, PALETTE.darkRoof);
    const posterColor = pz < -1 ? PALETTE.commBlue : pz > 1 ? PALETTE.commMint : PALETTE.commRed;
    b.box(8.7, 1.35, pz, 0.05, 1.5, 2.1, posterColor, 1);
  }

  b.box(9.2, 0, 0, 1.6, 2.4, 2.6, PALETTE.darkWood);
  b.pane(9.95, 1.1, 0, 1.8, 1.3, PALETTE.warmWood, PALETTE.glazing);
  b.box(0, 12.0, 0, 17.5, 15.5, 0.35, PALETTE.darkRoof);
  return b;
}

function buildSupermarket() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 16, 24, 6.8, PALETTE.warmWhite);
  b.box(8.05, 4.8, 0, 0.22, 23.5, 1.6, PALETTE.commMint);
  b.box(8.18, 5.2, 0, 0.08, 21.0, 0.8, PALETTE.commOrange);

  b.pane(8.1, 0.45, 3.0, 8.5, 3.8, PALETTE.steel, PALETTE.glazing);
  b.commAwning(9.2, 4.4, 3.0, 2.4, 10.5, 0.25, PALETTE.commMint);
  for (const pz of [-1.5, 7.5]) {
    b.box(10.2, 0, 3.0 + pz, 0.25, 0.25, 4.4, PALETTE.steel);
  }

  b.box(8.8, 0, -6.5, 3.2, 4.2, 0.12, PALETTE.concrete);
  b.box(8.8, 0.12, -8.4, 3.0, 0.10, 0.95, PALETTE.steel);
  b.box(8.8, 0.12, -4.6, 3.0, 0.10, 0.95, PALETTE.steel);
  b.box(7.4, 0.12, -6.5, 0.10, 3.8, 0.95, PALETTE.steel);
  for (let i = 0; i < 4; i++) {
    b.box(7.9 + i * 0.65, 0.15, -6.5, 0.85, 0.55, 0.75, PALETTE.chrome);
  }

  b.box(0, 6.8, 0, 16.6, 24.6, 0.35, PALETTE.roof);
  b.airConditionerUnit(-3.5, 7.15, 6.0, 1.8, 1.2, 1.4);
  b.airConditionerUnit(-3.5, 7.15, 2.5, 1.8, 1.2, 1.4);
  b.cylinder(3.0, 7.15, -4.0, 0.95, 1.2, PALETTE.steel, 8);
  return b;
}

function buildCornerOffice() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 15, 16, 17, PALETTE.concrete);
  b.box(7.55, 0, 0, 0.45, 14.0, 16.5, PALETTE.darkRoof);
  b.commWindowBand(0, 4.2, 0, 15, 16, 4, 4, PALETTE.playerRim, PALETTE.glazing);
  b.pane(7.6, 0.45, 0, 11.0, 3.5, PALETTE.steel, PALETTE.glazing);
  b.box(5.5, 0.45, 0, 1.2, 3.2, 1.1, PALETTE.warmWood);
  b.box(5.5, 1.55, 0, 0.1, 2.8, 0.6, PALETTE.warmGlow, 1);

  b.commAwning(8.8, 4.2, 0, 2.6, 7.5, 0.25, PALETTE.darkRoof);
  for (const pz of [-3.2, 3.2]) {
    b.box(9.8, 0, pz, 0.25, 0.25, 4.2, PALETTE.chrome);
  }

  b.box(0, 17.0, 0, 15.6, 16.6, 0.45, PALETTE.darkRoof);
  b.cylinder(0, 17.45, 0, 0.15, 5.5, PALETTE.steel, 6);
  b.cylinder(0, 22.95, 0, 0.35, 0.25, PALETTE.trainYellow, 6);
  b.waterTank(-3.5, 17.45, 4.0, 0.95, 1.3);
  return b;
}

function buildYellowCafe() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 11, 13, 7.5, PALETTE.counters1);
  b.box(0, 0, 0, 11.4, 13.4, 0.35, PALETTE.concrete);
  b.gable(0, 7.5, 0, 11.8, 13.8, 3.2, PALETTE.templeRoof);

  b.box(3.2, 8.5, 0, 1.8, 2.2, 1.6, PALETTE.warmWhite);
  b.pane(4.15, 8.8, 0, 1.4, 1.1, PALETTE.warmWood, PALETTE.warmGlow);
  b.gable(3.2, 10.1, 0, 2.0, 2.4, 0.85, PALETTE.templeRoof);

  for (const pz of [-3.5, 3.5]) {
    b.pane(5.55, 4.2, pz, 2.2, 2.4, PALETTE.warmWood, PALETTE.warmGlow);
    b.stripedAwning(6.4, 6.2, pz, 1.6, 2.6, 0.45, PALETTE.commMint, PALETTE.warmWhite, 4);
  }

  b.pane(5.55, 0.45, 2.2, 3.5, 3.2, PALETTE.darkWood, PALETTE.warmGlow);
  b.box(6.8, 0, -2.5, 3.2, 5.0, 0.25, PALETTE.warmWood);
  b.box(8.2, 0.25, -2.5, 0.4, 4.6, 0.55, PALETTE.concrete);
  b.box(8.2, 0.75, -2.5, 0.3, 4.4, 0.35, PALETTE.greens[1]);
  for (let i = -1; i <= 1; i++) {
    b.cylinder(8.2, 1.1, -2.5 + i * 1.3, 0.15, 0.1, PALETTE.flowers[i + 1], 6);
  }
  return b;
}

function buildGasStation() {
  const b = new MeshBuilder();
  b.box(0, 5.2, 0, 13, 20, 0.85, PALETTE.warmWhite);
  b.box(0, 5.3, 0, 13.4, 20.4, 0.35, PALETTE.commBlue);
  b.box(0, 5.65, 0, 13.4, 20.4, 0.30, PALETTE.commRed);
  for (const sx of [-3.8, 3.8]) {
    for (const sz of [-5.5, 5.5]) {
      b.box(sx, 0, sz, 0.55, 0.55, 5.2, PALETTE.steel);
    }
  }

  for (const sz of [-5.5, 5.5]) {
    b.box(0, 0, sz, 7.5, 1.6, 0.25, PALETTE.concrete);
    for (const bx of [-3.4, 3.4]) {
      b.cylinder(bx, 0.25, sz, 0.16, 0.85, PALETTE.commYellow, 8);
    }
    for (const px of [-1.5, 1.5]) {
      b.box(px, 0.25, sz, 0.85, 0.55, 1.65, PALETTE.darkRoof);
      b.box(px, 1.1, sz, 0.88, 0.58, 0.45, PALETTE.commBlue);
      b.box(px + 0.44, 0.85, sz, 0.03, 0.40, 0.35, PALETTE.trainYellow, 1);
      b.box(px, 0.75, sz - 0.32, 0.2, 0.1, 0.5, PALETTE.commMint);
      b.box(px, 0.75, sz + 0.32, 0.2, 0.1, 0.5, PALETTE.commRed);
    }
  }

  b.box(-7.5, 0, 2.0, 5.5, 8.5, 4.0, PALETTE.warmWhite);
  b.pane(-4.7, 0.45, 2.0, 6.5, 3.0, PALETTE.steel, PALETTE.glazing);
  b.box(-7.5, 4.0, 2.0, 5.8, 8.8, 0.25, PALETTE.roof);

  b.box(6.8, 0, 9.5, 0.45, 1.4, 4.2, PALETTE.commBlue);
  b.box(6.8, 1.2, 9.5, 0.50, 1.2, 2.6, PALETTE.darkRoof);
  for (let i = 0; i < 3; i++) {
    b.box(7.06, 1.6 + i * 0.7, 9.5, 0.02, 0.9, 0.4, PALETTE.trainYellow, 1);
  }
  return b;
}

function buildParkingGarage() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 18, 16, 9.5, PALETTE.concrete);
  for (let floor = 0; floor < 3; floor++) {
    const fy = 0.5 + floor * 3.0;
    b.box(0, fy, 0, 18.2, 16.2, 0.9, PALETTE.steel);
    for (const sx of [-8.5, 0, 8.5]) {
      for (const sz of [-7.5, 7.5]) {
        b.box(sx, fy, sz, 0.8, 0.8, 3.0, PALETTE.concrete);
      }
    }
  }
  b.box(9.2, 0, 2.5, 0.45, 0.45, 1.2, PALETTE.commYellow);
  b.box(9.2, 0.85, 0.8, 0.08, 2.6, 0.15, PALETTE.commRed);
  b.stairs(-8.5, 0, -8.5, 6.0, 3.2, 3.0);
  for (const pz of [-6.0, 6.0]) {
    b.cylinder(0, 9.5, pz, 0.08, 3.2, PALETTE.steel, 6);
    b.box(0, 12.6, pz, 0.65, 0.35, 0.2, PALETTE.warmGlow, 1);
  }
  return b;
}

function buildCommercialHotel() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 15, 14, 16, PALETTE.warmWhite);
  b.box(0, 0, 0, 15.4, 14.4, 0.45, PALETTE.darkRoof);
  b.pane(7.55, 0.45, 0, 9.5, 3.4, PALETTE.chrome, PALETTE.warmGlow);

  b.box(9.6, 3.8, 0, 4.0, 10.0, 0.45, PALETTE.darkRoof);
  for (const pz of [-4.2, 4.2]) {
    b.box(11.2, 0, pz, 0.45, 0.45, 3.8, PALETTE.chrome);
  }

  b.commWindowBand(0, 4.2, 0, 15, 14, 3, 4, PALETTE.playerRim, PALETTE.glazing);
  b.box(0, 16.0, 0, 15.6, 14.6, 0.65, PALETTE.concrete);
  b.box(5.0, 16.65, 0, 0.35, 8.5, 1.8, PALETTE.commBlue);
  b.box(5.2, 16.85, 0, 0.05, 8.0, 1.4, PALETTE.warmGlow, 1);
  b.waterTank(-3.5, 16.65, 3.0, 0.95, 1.4);
  return b;
}

function buildBankBranch() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 14, 16, 9.5, PALETTE.concrete);
  b.box(0, 0, 0, 14.6, 16.6, 0.65, PALETTE.darkRoof);
  for (const pz of [-5.5, -1.8, 1.8, 5.5]) {
    b.box(7.2, 0.65, pz, 0.75, 0.75, 7.5, PALETTE.warmWhite);
  }
  b.gable(7.2, 8.15, 0, 1.8, 14.0, 1.8, PALETTE.warmWhite);
  b.pane(6.9, 0.65, 0, 6.5, 3.5, PALETTE.chrome, PALETTE.glazing);

  b.box(7.1, 0.65, 6.2, 0.85, 2.2, 3.2, PALETTE.commBlue);
  b.pane(7.55, 0.85, 6.2, 1.6, 2.4, PALETTE.steel, PALETTE.warmGlow);
  b.box(0, 9.5, 0, 14.5, 16.5, 0.45, PALETTE.darkRoof);
  return b;
}

function buildStackedShopHouse() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 12, 8, 13.5, PALETTE.warmWhite);
  b.box(4.5, 0, 0, 3.0, 8.0, 3.8, PALETTE.tileWhite);
  for (const pz of [-3.6, 3.6]) {
    b.box(5.8, 0, pz, 0.45, 0.45, 3.8, PALETTE.concrete);
  }
  b.pane(4.45, 0.35, 0, 5.5, 3.2, PALETTE.warmWood, PALETTE.warmGlow);

  b.pane(6.05, 4.2, 0, 5.5, 2.2, PALETTE.playerRim, PALETTE.glazing);
  b.box(6.15, 4.2, 0, 0.04, 5.5, 2.2, PALETTE.commMint);
  b.pane(6.05, 7.5, 0, 5.5, 2.2, PALETTE.playerRim, PALETTE.glazing);
  b.box(6.15, 7.5, 0, 0.04, 5.5, 2.2, PALETTE.commMint);

  b.box(6.4, 7.0, 0, 0.8, 6.5, 0.15, PALETTE.concrete);
  b.box(6.75, 7.15, 0, 0.06, 6.5, 0.85, PALETTE.steel);
  b.box(6.4, 7.15, -1.8, 0.4, 1.2, 0.45, PALETTE.greens[2]);
  b.box(6.4, 7.15, 1.8, 0.4, 1.2, 0.45, PALETTE.greens[0]);

  b.box(0, 13.5, 0, 11.5, 7.5, 2.8, PALETTE.commMint);
  b.gable(0, 16.3, 0, 11.8, 7.8, 1.2, PALETTE.roof);
  b.waterTank(-3.2, 13.5, 2.2, 0.85, 1.3);
  return b;
}

function buildWarehouseStore() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 18, 22, 8.5, PALETTE.concrete);
  b.box(0, 6.5, 0, 18.4, 22.4, 1.8, PALETTE.trainAccent);
  b.box(9.25, 7.1, 0, 0.05, 14.0, 0.9, PALETTE.templeRidge);

  b.pane(9.05, 0.45, 4.5, 8.5, 4.8, PALETTE.steel, PALETTE.glazing);
  b.commAwning(10.2, 5.2, 4.5, 2.4, 10.0, 0.35, PALETTE.trainAccent);

  b.box(9.05, 0.85, -6.5, 0.15, 5.5, 3.8, PALETTE.tankStand);
  b.box(9.8, 0, -6.5, 1.8, 6.5, 0.85, PALETTE.concrete);

  b.box(0, 8.5, 0, 18.5, 22.5, 0.35, PALETTE.roof);
  b.cylinder(-4.0, 8.85, 4.0, 1.2, 1.2, PALETTE.steel, 8);
  b.cylinder(-4.0, 8.85, -4.0, 1.2, 1.2, PALETTE.steel, 8);
  return b;
}

function buildMetroEntrance() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 7.5, 4.2, 0.35, PALETTE.concrete);
  b.stairs(0.5, 0, 0, 5.5, 3.2, 2.8);
  for (const pz of [-1.8, 1.8]) {
    b.box(0.5, 0.35, pz, 5.5, 0.08, 1.1, PALETTE.glazing);
    b.box(0.5, 1.45, pz, 5.5, 0.10, 0.08, PALETTE.chrome);
  }
  for (const px of [-1.8, 0.8, 3.4]) {
    b.beam([px, 0.35, -2.0], [px, 2.8, -2.0], 0.10, PALETTE.commMint);
    b.beam([px, 0.35, 2.0], [px, 2.8, 2.0], 0.10, PALETTE.commMint);
    b.beam([px, 2.8, -2.0], [px, 3.4, 0], 0.10, PALETTE.commMint);
    b.beam([px, 2.8, 2.0], [px, 3.4, 0], 0.10, PALETTE.commMint);
  }
  b.canopy(0.8, 3.1, 0, 6.2, 4.2, 0.45, PALETTE.glazing);

  b.box(3.8, 0, -2.4, 0.35, 0.35, 3.8, PALETTE.commMint);
  b.box(3.8, 3.2, -2.4, 0.45, 0.45, 0.65, PALETTE.commBlue);
  b.box(3.8, 3.3, -2.4, 0.48, 0.48, 0.45, PALETTE.warmWhite);
  return b;
}

// -------------------------------------------------------------
// 12 Street Shops & Dining
// -------------------------------------------------------------

function buildBubbleTeaShop() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 2.8, 4.8, 1.05, PALETTE.warmWood);
  b.box(0.05, 1.05, 0, 2.9, 4.9, 0.08, PALETTE.warmWhite);

  for (let i = 0; i < 4; i++) {
    const pz = -1.6 + i * 1.05;
    b.cylinder(-0.4, 1.13, pz, 0.22, 0.75, PALETTE.steel, 10);
    const tapColor = i === 0 ? PALETTE.commRed : i === 1 ? PALETTE.commMint : i === 2 ? PALETTE.teaAmber : PALETTE.bobaBrown;
    b.cylinder(-0.4, 1.88, pz, 0.18, 0.12, tapColor, 8);
  }

  b.box(0.3, 1.13, -1.8, 0.55, 0.45, 0.85, PALETTE.chrome);
  b.cylinder(0.3, 1.98, -1.8, 0.18, 0.25, PALETTE.commPink, 8);

  b.box(0.4, 1.13, 0.8, 0.55, 1.6, 0.35, PALETTE.glazing);
  b.box(0.4, 1.13, 0.8, 0.50, 1.5, 0.25, PALETTE.bobaBrown);
  b.box(0.4, 1.13, -0.4, 0.35, 0.40, 0.45, PALETTE.playerRim);

  b.box(-1.3, 0, 0, 0.25, 4.8, 3.4, PALETTE.tileWhite);
  b.box(-1.15, 1.8, 0, 0.05, 4.2, 1.2, PALETTE.darkRoof);
  b.box(-1.12, 1.9, 0, 0.02, 3.9, 1.0, PALETTE.warmGlow, 1);
  b.stripedAwning(0.6, 3.1, 0, 2.8, 5.0, 0.45, PALETTE.commMint, PALETTE.warmWhite, 6);
  return b;
}

function buildBentoShop() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 2.6, 4.6, 1.0, PALETTE.steel);
  b.box(0.2, 1.0, 0, 1.4, 4.2, 0.45, PALETTE.glazing);
  for (let i = 0; i < 6; i++) {
    const pz = -1.6 + i * 0.65;
    const foodColor = i % 2 === 0 ? PALETTE.counters1 : PALETTE.greens[2];
    b.box(0.2, 1.02, pz, 0.75, 0.55, 0.10, foodColor);
  }

  b.cylinder(-0.6, 1.0, -1.6, 0.32, 0.45, PALETTE.tatungGreen, 10);
  b.cylinder(-0.6, 1.45, -1.6, 0.30, 0.15, PALETTE.steel, 8);
  b.cylinder(-0.6, 1.0, 1.4, 0.38, 0.55, PALETTE.steel, 10);
  b.cylinder(-0.6, 1.55, 1.4, 0.35, 0.08, PALETTE.warmWood, 8);

  b.box(1.2, 2.6, 0, 0.05, 4.6, 0.95, PALETTE.commRed);
  b.box(1.23, 2.7, 0, 0.02, 4.2, 0.75, PALETTE.trainYellow, 1);

  b.box(2.8, 0, 0, 1.4, 2.0, 0.75, PALETTE.steel);
  for (const sz of [-1.4, 1.4]) {
    b.cylinder(2.8, 0, sz, 0.22, 0.45, PALETTE.commRed, 8);
  }
  return b;
}

function buildBakery() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 3.2, 4.8, 3.5, PALETTE.warmWhite);
  b.pane(1.65, 0.45, 0, 4.2, 2.3, PALETTE.darkRoof, PALETTE.glazing);
  b.box(1.2, 0.65, 0, 0.65, 3.8, 0.85, PALETTE.warmWood);
  for (let i = 0; i < 4; i++) {
    b.box(1.2, 1.52, -1.4 + i * 0.9, 0.45, 0.65, 0.25, PALETTE.counters0);
  }
  b.commAwning(2.2, 3.0, 0, 1.8, 5.0, 0.35, PALETTE.commCrimson);
  return b;
}

function buildPharmacy() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 3.4, 5.2, 3.6, PALETTE.warmWhite);
  b.box(1.75, 2.8, 0, 0.22, 5.2, 0.85, PALETTE.commCyan);
  b.box(1.88, 2.9, 0, 0.04, 4.8, 0.65, PALETTE.commOrange);
  b.pane(1.75, 0.35, 0, 4.6, 2.3, PALETTE.steel, PALETTE.glazing);
  for (const pz of [-1.6, 1.6]) {
    b.box(2.3, 0, pz, 0.65, 0.95, 0.75, PALETTE.chrome);
  }
  return b;
}

function buildCornerGrocery() {
  const b = new MeshBuilder();
  // Traditional Taiwanese corner grocery / kam-a-tiam (柑仔店)
  b.box(0, 0, 0, 3.2, 5.2, 3.5, PALETTE.warmWhite);
  // Red, white & green striped canopy
  b.stripedAwning(2.1, 2.9, 0, 1.8, 5.4, 0.45, PALETTE.commRed, PALETTE.commMint, 6);
  b.pane(1.65, 0.45, 0, 4.6, 2.2, PALETTE.darkWood, PALETTE.warmGlow);
  // Outdoor produce bins & egg crates
  for (let i = -1; i <= 1; i++) {
    b.box(2.1, 0, i * 1.2, 0.65, 0.95, 0.65, PALETTE.counters1);
    b.cylinder(2.1, 0.65, i * 1.2, 0.35, 0.15, PALETTE.greens[i + 1], 8);
  }
  return b;
}

function buildStationeryStore() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 3.2, 4.8, 3.4, PALETTE.warmWhite);
  b.pane(1.65, 0.45, 0.8, 2.8, 2.4, PALETTE.warmWood, PALETTE.glazing);
  b.box(1.3, 0.65, 0.8, 0.4, 2.4, 0.75, PALETTE.counters1);
  b.pane(1.65, 0.45, -1.5, 1.4, 2.4, PALETTE.warmWood, PALETTE.glazing);
  b.commAwning(2.2, 3.1, 0, 1.8, 5.0, 0.35, PALETTE.trainAccent);
  return b;
}

function buildRamenYatai() {
  const b = new MeshBuilder();
  b.box(0, 0.45, 0, 2.4, 3.8, 0.85, PALETTE.darkWood);
  b.box(0.1, 1.3, 0, 2.6, 4.0, 0.10, PALETTE.warmWood);

  b.wheelZ(0, 0.48, -1.95, 0.48, 0.12, PALETTE.darkRoof, PALETTE.warmWood, 10);
  b.wheelZ(0, 0.48, 1.95, 0.48, 0.12, PALETTE.darkRoof, PALETTE.warmWood, 10);

  for (const sx of [-1.0, 1.0]) {
    for (const sz of [-1.7, 1.7]) {
      b.box(sx, 1.4, sz, 0.12, 0.12, 1.6, PALETTE.darkWood);
    }
  }
  b.gable(0, 3.0, 0, 2.8, 4.2, 0.75, PALETTE.darkWood);
  b.box(1.15, 2.4, 0, 0.03, 3.6, 0.65, PALETTE.playerRim);

  b.cylinder(-0.4, 1.4, 0, 0.45, 0.65, PALETTE.steel, 10);
  b.box(-0.4, 2.05, 0, 0.6, 0.6, 0.08, PALETTE.warmWood);

  b.lantern(1.2, 2.1, -1.4, 0.22, 0.42, PALETTE.commRed);
  b.lantern(1.2, 2.1, 1.4, 0.22, 0.42, PALETTE.commRed);

  for (let i = -1; i <= 1; i++) {
    b.cylinder(1.7, 0, i * 1.1, 0.20, 0.65, PALETTE.warmWood, 8);
    b.cylinder(1.7, 0, i * 1.1, 0.04, 0.60, PALETTE.steel, 6);
  }
  return b;
}

function buildNightMarketFryer() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 2.4, 4.2, 0.95, PALETTE.steel);
  b.box(0.2, 0.95, 0, 1.2, 3.8, 0.85, PALETTE.glazing);
  for (let i = 0; i < 5; i++) {
    const pz = -1.4 + i * 0.7;
    b.box(0.2, 1.0, pz, 0.8, 0.5, 0.12, PALETTE.counters1);
  }

  b.box(-0.6, 0.95, -1.2, 0.95, 1.2, 0.55, PALETTE.steel);
  b.box(-0.6, 1.5, -1.2, 0.65, 0.95, 0.15, PALETTE.steel);
  b.box(-0.6, 2.2, -1.2, 1.1, 1.4, 0.45, PALETTE.steel);
  b.cylinder(-0.6, 2.65, -1.2, 0.16, 0.95, PALETTE.steel, 8);

  b.cylinder(0.5, 0.95, 1.4, 0.08, 0.25, PALETTE.chrome, 6);
  b.cylinder(0.5, 0.95, 1.6, 0.08, 0.25, PALETTE.commRed, 6);

  b.box(1.15, 2.6, 0, 0.04, 4.0, 0.95, PALETTE.commYellow);
  b.box(1.18, 2.7, 0, 0.02, 3.6, 0.75, PALETTE.commRed, 1);
  return b;
}

function buildNightMarketFruit() {
  const b = new MeshBuilder();
  // Night market fresh cut fruit stand (現切水果攤)
  b.box(0, 0, 0, 2.4, 4.0, 0.95, PALETTE.steel);
  b.box(0.2, 0.95, 0, 1.2, 3.6, 0.85, PALETTE.glazing); // ice showcase
  // Sliced fruits on crushed ice (watermelon, guava, mango, pineapple)
  const fruitColors = [PALETTE.commRed, PALETTE.commMint, PALETTE.commYellow, PALETTE.commOrange];
  for (let i = 0; i < 4; i++) {
    b.box(0.2, 1.0, -1.2 + i * 0.8, 0.75, 0.65, 0.15, fruitColors[i]);
  }
  // Fruit juice blender
  b.cylinder(-0.6, 0.95, 1.2, 0.18, 0.55, PALETTE.glazing, 8);
  b.box(-0.6, 0.95, 1.2, 0.45, 0.45, 0.25, PALETTE.steel);
  // Illuminated green marquee
  b.box(1.15, 2.6, 0, 0.04, 3.8, 0.85, PALETTE.commMint);
  b.box(1.18, 2.7, 0, 0.02, 3.4, 0.65, PALETTE.warmWhite, 1);
  return b;
}

function buildNightMarketGame() {
  const b = new MeshBuilder();
  // Taiwanese night market pinball marble game stall (夜市打彈珠遊戲攤)
  b.box(0, 0, 0, 2.6, 3.6, 0.85, PALETTE.warmWood);
  // Slanted pinball marble board
  b.commAwning(0.2, 0.85, 0, 1.6, 3.2, 0.45, PALETTE.trainYellow);
  for (let i = 0; i < 6; i++) {
    b.cylinder(0.2, 1.15, -1.2 + i * 0.48, 0.04, 0.08, PALETTE.chrome, 6); // metal pins
  }
  // Prize display shelf with colorful plush toys overhead
  b.box(-1.0, 1.8, 0, 0.35, 3.6, 1.4, PALETTE.warmWood);
  for (let i = 0; i < 3; i++) {
    b.cylinder(-0.8, 2.2, -1.0 + i * 1.0, 0.22, 0.35, PALETTE.flowers[i], 8); // plush prizes
  }
  // 2 Round player stools
  for (const sz of [-0.9, 0.9]) {
    b.cylinder(1.6, 0, sz, 0.20, 0.45, PALETTE.commBlue, 8);
  }
  return b;
}

function buildVendingBank() {
  const b = new MeshBuilder();
  // 3 Distinct modern commercial vending machines with side recycling bin
  const colors = [PALETTE.commBlue, PALETTE.counters1, PALETTE.commRed];
  for (let i = 0; i < 3; i++) {
    const pz = -1.5 + i * 1.5;
    b.box(0, 0, pz, 1.1, 1.35, 2.2, colors[i]);
    b.box(0.56, 0.75, pz, 0.04, 1.15, 1.05, PALETTE.darkRoof);
    b.box(0.59, 0.85, pz, 0.02, 1.05, 0.85, PALETTE.warmGlow, 1); // bottle display
    b.box(0.56, 0.22, pz, 0.04, 0.95, 0.35, PALETTE.darkRoof); // retrieval flap
  }
  // Dual-hole bottle recycling bin
  b.box(0, 0, 3.0, 0.95, 0.85, 1.1, PALETTE.commMint);
  b.cylinder(0, 1.1, 2.85, 0.12, 0.04, PALETTE.darkRoof, 8);
  b.cylinder(0, 1.1, 3.15, 0.12, 0.04, PALETTE.darkRoof, 8);
  return b;
}

function buildMobileFoodCart() {
  const b = new MeshBuilder();
  // Traditional three-wheeled street food trike (三輪外帶餐車)
  b.box(0, 0.35, 0, 2.4, 1.4, 0.75, PALETTE.warmWood);
  b.wheelZ(-1.0, 0.38, 0, 0.38, 0.10, PALETTE.darkRoof, PALETTE.chrome, 10);
  b.wheelZ(0.8, 0.38, -0.75, 0.38, 0.10, PALETTE.darkRoof, PALETTE.chrome, 10);
  b.wheelZ(0.8, 0.38, 0.75, 0.38, 0.10, PALETTE.darkRoof, PALETTE.chrome, 10);
  // Stainless steel cooking counter & steamer
  b.box(0.2, 1.1, 0, 1.4, 1.3, 0.10, PALETTE.steel);
  b.cylinder(0.2, 1.2, 0, 0.35, 0.45, PALETTE.steel, 10);
  // Canvas sunshade canopy
  for (const sx of [-0.6, 0.8]) {
    for (const sz of [-0.6, 0.6]) {
      b.box(sx, 1.1, sz, 0.04, 0.04, 1.2, PALETTE.steel);
    }
  }
  b.canopy(0.1, 2.3, 0, 1.8, 1.6, 0.35, PALETTE.commYellow);
  return b;
}

// -------------------------------------------------------------
// 12 Commercial Facilities & Transit
// -------------------------------------------------------------

function buildVerticalNeonSign() {
  const b = new MeshBuilder();
  for (const hy of [0.8, 4.2]) {
    b.box(0.25, hy, 0, 0.50, 0.08, 0.08, PALETTE.steel);
  }
  b.cylinder(0.50, 0.4, 0, 0.06, 4.2, PALETTE.steel, 6);
  const colors = [PALETTE.commRed, PALETTE.commYellow, PALETTE.commBlue];
  for (let i = 0; i < 3; i++) {
    const sy = 0.6 + i * 1.3;
    b.box(0.95, sy, 0, 0.85, 0.22, 1.15, colors[i]);
    b.box(0.95, sy + 0.1, 0.12, 0.70, 0.03, 0.95, PALETTE.warmWhite, 1);
    b.box(0.95, sy + 0.1, -0.12, 0.70, 0.03, 0.95, PALETTE.warmWhite, 1);
  }
  return b;
}

function buildHorizontalSignboard() {
  const b = new MeshBuilder();
  b.box(0.12, 0.3, 0, 0.24, 4.2, 1.1, PALETTE.counters1);
  b.box(0.25, 0.35, 0, 0.03, 4.0, 0.95, PALETTE.commYellow);
  for (let i = 0; i < 3; i++) {
    const sz = -1.4 + i * 1.4;
    b.beam([0.05, 1.4, sz], [0.55, 1.6, sz], 0.04, PALETTE.steel);
    b.cylinder(0.55, 1.50, sz, 0.08, 0.12, PALETTE.steel, 6);
  }
  return b;
}

function buildTotemLightbox() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 0.9, 1.5, 0.18, PALETTE.concrete);
  b.box(0, 0.18, 0, 0.38, 1.3, 3.5, PALETTE.commBlue);
  for (const sign of [-1, 1]) {
    b.box(sign * 0.20, 0.6, 0, 0.04, 1.05, 2.6, PALETTE.warmWhite);
    b.box(sign * 0.22, 1.2, 0, 0.02, 0.95, 1.8, PALETTE.warmGlow, 1);
  }
  return b;
}

function buildAFrameSign() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 0.58, 0.78, 1.10, PALETTE.warmWood);
  b.box(0, 0.18, 0, 0.62, 0.65, 0.78, PALETTE.playerRim);
  b.box(0.32, 0.35, 0, 0.02, 0.50, 0.55, PALETTE.trainYellow, 1);
  b.beam([-0.18, 0.45, 0], [0.18, 0.45, 0], 0.02, PALETTE.steel);
  return b;
}

function buildCommercialBannerPole() {
  const b = new MeshBuilder();
  b.cylinder(0, 0, 0, 0.22, 0.45, PALETTE.concrete, 8);
  b.cylinder(0, 0.45, 0, 0.08, 5.0, PALETTE.steel, 8);
  b.cylinder(0, 5.45, 0, 0.35, 0.25, PALETTE.commYellow, 8);
  for (const by of [2.2, 4.6]) {
    b.beam([0, by, -1.0], [0, by, 1.0], 0.04, PALETTE.steel);
  }
  for (const sign of [-0.60, 0.60]) {
    b.box(0, 2.2, sign, 0.03, 0.75, 2.4, PALETTE.commBlue);
    b.box(0, 2.6, sign, 0.04, 0.60, 1.6, PALETTE.warmWhite);
  }
  return b;
}

function buildRetractableAwning() {
  const b = new MeshBuilder();
  b.box(0.06, 0.8, 0, 0.12, 3.8, 0.18, PALETTE.steel);
  for (const az of [-1.6, 1.6]) {
    b.beam([0.08, 0.8, az], [1.1, 0.65, az], 0.05, PALETTE.steel);
    b.beam([1.1, 0.65, az], [2.2, 0.5, az], 0.05, PALETTE.steel);
  }
  b.stripedAwning(1.2, 0.52, 0, 2.2, 3.8, 0.38, PALETTE.commYellow, PALETTE.warmWhite, 6);
  b.box(2.3, 0.34, 0, 0.04, 3.8, 0.20, PALETTE.commRed);
  return b;
}

function buildCafeUmbrellaSet() {
  const b = new MeshBuilder();
  b.cylinder(0, 0, 0, 0.38, 0.06, PALETTE.playerRim, 12);
  b.cylinder(0, 0.06, 0, 0.05, 2.4, PALETTE.steel, 8);
  b.cylinder(0, 0.72, 0, 0.72, 0.05, PALETTE.warmWood, 12);
  b.canopy(0, 2.0, 0, 2.8, 2.8, 0.65, PALETTE.commMint);

  for (let i = 0; i < 4; i++) {
    const a = (i * 2 * Math.PI) / 4.0;
    const cx = Math.cos(a) * 1.05, cz = Math.sin(a) * 1.05;
    b.cylinder(cx, 0, cz, 0.24, 0.45, PALETTE.warmWood, 8);
    b.cylinder(cx * 1.15, 0.45, cz * 1.15, 0.24, 0.40, PALETTE.steel, 8);
  }
  return b;
}

function buildCommercialPlanter() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 1.4, 2.8, 0.75, PALETTE.concrete);
  b.box(0, 0.75, 0, 1.25, 2.65, 0.45, PALETTE.greens[1]);
  for (let i = -1; i <= 1; i++) {
    b.cylinder(0, 1.2, i * 0.85, 0.22, 0.15, PALETTE.flowers[i + 1], 6);
  }
  return b;
}

function buildCommercialRecycling() {
  const b = new MeshBuilder();
  // 3-stream commercial stainless sorting station (General, Recycle, Paper)
  b.box(0, 0, 0, 0.85, 2.6, 0.95, PALETTE.steel);
  const binColors = [PALETTE.darkRoof, PALETTE.commYellow, PALETTE.commBlue];
  for (let i = 0; i < 3; i++) {
    const pz = -0.8 + i * 0.8;
    b.box(0, 0.95, pz, 0.75, 0.70, 0.08, binColors[i]);
    b.cylinder(0, 1.03, pz, 0.16, 0.04, PALETTE.darkRoof, 8);
  }
  return b;
}

function buildCoolingTower() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 2.6, 2.6, 0.25, PALETTE.steel);
  b.box(0, 0.25, 0, 2.4, 2.4, 1.8, PALETTE.warmWhite);
  for (const side of [-1.22, 1.22]) {
    b.box(0, 0.45, side, 2.2, 0.04, 1.3, PALETTE.darkRoof);
  }
  b.cylinder(0, 2.05, 0, 0.95, 0.55, PALETTE.concrete, 12);
  b.cylinder(0, 2.60, 0, 0.88, 0.06, PALETTE.steel, 8);
  return b;
}

function buildFireEscapeStair() {
  const b = new MeshBuilder();
  b.box(1.0, 3.2, 0, 2.0, 1.8, 0.12, PALETTE.steel);
  b.box(2.0, 3.32, 0, 0.08, 1.8, 0.9, PALETTE.steel);
  b.box(1.0, 3.32, -0.9, 2.0, 0.08, 0.9, PALETTE.steel);
  b.stairs(1.0, 0, 1.8, 2.8, 1.1, 3.2);
  for (const hy of [0.5, 3.2]) {
    b.box(0.2, hy, -0.8, 0.4, 0.12, 0.12, PALETTE.steel);
    b.box(0.2, hy, 0.8, 0.4, 0.12, 0.12, PALETTE.steel);
  }
  return b;
}

function buildTransitFeederBus() {
  const b = new MeshBuilder();
  const length = 10.4, width = 2.5, wheelR = 0.46;
  const chassisY = 0.35;

  b.box(0, chassisY, 0, length, width, 0.85, PALETTE.warmWhite);
  b.box(0, chassisY, 0, length + 0.15, width + 0.05, 0.22, PALETTE.darkRoof);

  b.box(0, chassisY + 0.35, -width / 2 - 0.015, length * 0.85, 0.03, 0.35, PALETTE.commBusGreen);
  b.box(0, chassisY + 0.35, width / 2 + 0.015, length * 0.85, 0.03, 0.35, PALETTE.commBusGreen);

  b.box(0, chassisY + 0.85, 0, length, width, 1.35, PALETTE.darkGlass);
  for (let i = -3; i <= 3; i++) {
    const px = i * 1.35;
    b.box(px, chassisY + 0.85, -width / 2, 0.12, 0.04, 1.35, PALETTE.playerRim);
    b.box(px, chassisY + 0.85, width / 2, 0.12, 0.04, 1.35, PALETTE.playerRim);
  }

  b.box(0, chassisY + 2.20, 0, length, width, 0.40, PALETTE.warmWhite);
  b.commAwning(length / 2 - 0.9, chassisY + 2.25, 0, 1.8, width, 0.35, PALETTE.warmWhite);

  b.pane(length / 2 + 0.08, chassisY + 0.85, 0, width - 0.35, 1.35, PALETTE.playerRim, PALETTE.darkGlass);
  b.box(length / 2 + 0.02, chassisY + 2.25, 0, 0.25, 1.8, 0.32, PALETTE.darkRoof);
  b.box(length / 2 + 0.15, chassisY + 2.27, 0, 0.02, 1.6, 0.24, PALETTE.trainYellow, 1);

  for (const sign of [-0.95, 0.95]) {
    b.cylinder(length / 2 + 0.08, chassisY + 0.35, sign, 0.12, 0.05, PALETTE.pureWhite, 8);
    b.cylinder(length / 2 + 0.08, chassisY + 0.52, sign, 0.08, 0.05, PALETTE.commYellow, 8);
  }
  b.box(length / 2 + 0.08, chassisY + 0.35, 0, 0.04, 1.1, 0.32, PALETTE.playerRim);
  b.box(length / 2 + 0.11, chassisY + 0.25, 0, 0.02, 0.55, 0.18, PALETTE.warmWhite);

  for (const sign of [-1, 1]) {
    const mz = sign * (width / 2 + 0.35);
    b.beam([length / 2 - 0.2, chassisY + 2.1, sign * (width / 2)], [length / 2 + 0.4, chassisY + 1.8, mz], 0.04, PALETTE.darkRoof);
    b.box(length / 2 + 0.4, chassisY + 1.45, mz, 0.10, 0.18, 0.45, PALETTE.darkRoof);
    b.box(length / 2 + 0.35, chassisY + 1.47, mz, 0.02, 0.14, 0.40, PALETTE.chrome);
  }

  for (const doorX of [2.8, -0.8]) {
    b.box(doorX, chassisY, -width / 2 - 0.02, 1.30, 0.06, 1.95, PALETTE.darkRoof);
    b.pane(doorX, chassisY + 0.35, -width / 2 - 0.03, 1.10, 1.45, PALETTE.darkRoof, PALETTE.glazing);
    b.cylinder(doorX + 0.3, chassisY + 0.4, -width / 2 + 0.15, 0.03, 1.6, PALETTE.trainYellow, 6);
  }

  b.pane(-length / 2 - 0.05, chassisY + 1.25, 0, width - 0.45, 0.95, PALETTE.playerRim, PALETTE.darkGlass);
  b.box(-length / 2 - 0.05, chassisY + 0.45, 0, 0.05, 1.9, 0.65, PALETTE.playerRim);
  for (const sign of [-0.95, 0.95]) {
    b.box(-length / 2 - 0.06, chassisY + 0.65, sign, 0.04, 0.14, 0.18, PALETTE.commRed);
    b.box(-length / 2 - 0.06, chassisY + 0.45, sign, 0.04, 0.14, 0.18, PALETTE.commYellow);
    b.box(-length / 2 - 0.06, chassisY + 0.25, sign, 0.04, 0.14, 0.18, PALETTE.warmWhite);
  }

  b.box(0, chassisY + 2.60, 0, 3.8, 1.9, 0.45, PALETTE.warmWhite);
  b.commAwning(1.6, chassisY + 2.65, 0, 0.6, 1.8, 0.25, PALETTE.warmWhite);
  b.box(0, chassisY + 2.68, 0, 3.2, 1.94, 0.22, PALETTE.darkRoof);

  b.wheelZ(2.9, wheelR, -width / 2 + 0.06, wheelR, 0.30, PALETTE.darkRoof, PALETTE.steel, 14);
  b.wheelZ(2.9, wheelR, width / 2 - 0.06, wheelR, 0.30, PALETTE.darkRoof, PALETTE.steel, 14);
  b.wheelZ(-2.9, wheelR, -width / 2 + 0.06, wheelR, 0.34, PALETTE.darkRoof, PALETTE.steel, 14);
  b.wheelZ(-2.9, wheelR, width / 2 - 0.06, wheelR, 0.34, PALETTE.darkRoof, PALETTE.steel, 14);

  return b;
}

// -------------------------------------------------------------
// 4 Composite Assemblies
// -------------------------------------------------------------

function buildCommercialAvenue() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 48, 56, 0.35, PALETTE.roadMajor);
  b.box(0, 0.35, 0, 47, 55, 0.20, PALETTE.plaza);

  const deptStore = buildDepartmentStore();
  const cinema = buildCinema();
  const cafe = buildYellowCafe();
  const bus = buildTransitFeederBus();
  const planter = buildCommercialPlanter();

  b.addModelAt(deptStore, -12, 0.55, -10, 0);
  b.addModelAt(cinema, -13, 0.55, 16, 0);
  b.addModelAt(cafe, 12, 0.55, 16, Math.PI);
  b.addModelAt(bus, 10, 0.55, -6, 0);

  b.addModelAt(planter, 2, 0.55, 6, 0);
  b.addModelAt(planter, 2, 0.55, -18, 0);
  return b;
}

function buildNightMarketAlley() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 36, 42, 0.35, PALETTE.roadMinor);
  b.box(0, 0.35, 0, 35, 41, 0.15, PALETTE.plaza);

  const boba = buildBubbleTeaShop();
  const bento = buildBentoShop();
  const fryer = buildNightMarketFryer();
  const ramen = buildRamenYatai();
  const fruit = buildNightMarketFruit();
  const game = buildNightMarketGame();

  b.addModelAt(boba, -8, 0.50, -10, 0);
  b.addModelAt(bento, -8, 0.50, 2, 0);
  b.addModelAt(fryer, -8, 0.50, 12, 0);

  b.addModelAt(ramen, 8, 0.50, -10, Math.PI);
  b.addModelAt(fruit, 8, 0.50, 2, Math.PI);
  b.addModelAt(game, 8, 0.50, 12, Math.PI);
  return b;
}

function buildStationTransitHub() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 46, 52, 0.35, PALETTE.roadMajor);
  b.box(0, 0.35, 0, 45, 51, 0.20, PALETTE.plaza);

  const office = buildCornerOffice();
  const bus = buildTransitFeederBus();
  const totem = buildTotemLightbox();
  const planter = buildCommercialPlanter();

  b.addModelAt(office, -12, 0.55, 12, 0);
  b.addModelAt(bus, 10, 0.55, -8, 0);
  b.addModelAt(totem, -2, 0.55, -16, 0);
  b.addModelAt(planter, 6, 0.55, -16, 0);
  return b;
}

function buildNeighborhoodRetailCorner() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 38, 44, 0.35, PALETTE.roadMajor);
  b.box(0, 0.35, 0, 37, 43, 0.18, PALETTE.plaza);

  const grocery = buildCornerGrocery();
  const bakery = buildBakery();
  const pharmacy = buildPharmacy();
  const cafe = buildCafeUmbrellaSet();
  const planter = buildCommercialPlanter();

  b.addModelAt(grocery, -8, 0.53, -8, 0);
  b.addModelAt(bakery, -8, 0.53, 8, 0);
  b.addModelAt(pharmacy, 8, 0.53, 10, Math.PI);
  b.addModelAt(cafe, 8, 0.53, -6, 0);
  b.addModelAt(planter, 8, 0.53, 2, 0);
  return b;
}

// -------------------------------------------------------------
// Exact 40 Catalog Map
// -------------------------------------------------------------

const GENERATORS = {
  // 12 Buildings
  'commercial-departmentStore': buildDepartmentStore,
  'commercial-cinema': buildCinema,
  'commercial-supermarket': buildSupermarket,
  'commercial-cornerOffice': buildCornerOffice,
  'commercial-yellowCafe': buildYellowCafe,
  'commercial-gasStation': buildGasStation,
  'commercial-parkingGarage': buildParkingGarage,
  'commercial-commercialHotel': buildCommercialHotel,
  'commercial-bankBranch': buildBankBranch,
  'commercial-stackedShopHouse': buildStackedShopHouse,
  'commercial-warehouseStore': buildWarehouseStore,
  'commercial-metroEntrance': buildMetroEntrance,

  // 12 Shops & Dining
  'commercial-bubbleTeaShop': buildBubbleTeaShop,
  'commercial-bentoShop': buildBentoShop,
  'commercial-bakery': buildBakery,
  'commercial-pharmacy': buildPharmacy,
  'commercial-cornerGrocery': buildCornerGrocery,
  'commercial-stationeryStore': buildStationeryStore,
  'commercial-ramenYatai': buildRamenYatai,
  'commercial-nightMarketFryer': buildNightMarketFryer,
  'commercial-nightMarketFruit': buildNightMarketFruit,
  'commercial-nightMarketGame': buildNightMarketGame,
  'commercial-vendingBank': buildVendingBank,
  'commercial-mobileFoodCart': buildMobileFoodCart,

  // 12 Facilities & Transit
  'commercial-verticalNeonSign': buildVerticalNeonSign,
  'commercial-horizontalSignboard': buildHorizontalSignboard,
  'commercial-totemLightbox': buildTotemLightbox,
  'commercial-aFrameSign': buildAFrameSign,
  'commercial-commercialBannerPole': buildCommercialBannerPole,
  'commercial-retractableAwning': buildRetractableAwning,
  'commercial-cafeUmbrellaSet': buildCafeUmbrellaSet,
  'commercial-commercialPlanter': buildCommercialPlanter,
  'commercial-commercialRecycling': buildCommercialRecycling,
  'commercial-coolingTower': buildCoolingTower,
  'commercial-fireEscapeStair': buildFireEscapeStair,
  'commercial-transitFeederBus': buildTransitFeederBus,

  // 4 Assemblies
  'commercial-example-commercialAvenue': buildCommercialAvenue,
  'commercial-example-nightMarketAlley': buildNightMarketAlley,
  'commercial-example-stationTransitHub': buildStationTransitHub,
  'commercial-example-neighborhoodRetailCorner': buildNeighborhoodRetailCorner
};

console.log('Generating exact 40 commercial kit models...');
let totalTriangles = 0;

for (const [id, fn] of Object.entries(GENERATORS)) {
  const builder = fn();
  const filePath = resolve(modelsDir, `${id}.m3dmodel`);
  const buf = writeM3DModel(filePath, id, builder.vertices);
  const tris = builder.vertices.length / 3;
  totalTriangles += tris;
  console.log(`Generated ${id}: ${tris} triangles (${buf.length} bytes)`);
}

console.log(`Successfully generated all 40 models! Total triangles: ${totalTriangles}`);
