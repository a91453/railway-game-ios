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
      recipeVersion: 1,
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

// Model generation functions matching Map3DCommercialKit Swift recipes
function buildDepartmentStore() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 18, 22, 14, PALETTE.tileWhite);
  b.commWindowBand(0, 3.5, 0, 18, 22, 3, 6);
  b.pane(9, 0.4, 0, 8, 3.0);
  b.commAwning(9.8, 3.4, 0, 2.2, 10, 0.3, PALETTE.commBlue);
  for (const side of [-4.6, 4.6]) b.box(10.8, 0, side, 0.25, 0.25, 3.4, PALETTE.tankStand);
  b.box(-1, 14, 0, 14, 18, 3.5, PALETTE.concrete);
  b.box(-1, 17.5, 0, 14.4, 18.4, 0.25, PALETTE.roof);
  b.box(0, 17.75, 4, 3, 5, 2.2, PALETTE.tankStand);
  b.commSignboard(5, 17.75, 0, 12, 3.2, 0.3, PALETTE.tankStand, PALETTE.commRed);
  return b;
}

function buildCinema() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 16, 14, 11, PALETTE.counters1);
  b.box(8.05, 0, 0, 0.3, 8, 13.5, PALETTE.concrete);
  b.box(8.05, 0, 0, 0.4, 4, 14.8, PALETTE.trainAccent);
  b.commWindowBand(0, 4.5, 0, 16, 14, 2, 3);
  b.box(9.2, 3.8, 0, 2.6, 10, 0.35, PALETTE.canopy);
  b.box(9.2, 3.55, 0, 2.4, 9.6, 0.15, PALETTE.trainYellow);
  b.beam([8.1, 7.5, -4], [10.2, 4.15, -4], 0.10, PALETTE.tankStand);
  b.beam([8.1, 7.5, 4], [10.2, 4.15, 4], 0.10, PALETTE.tankStand);
  b.box(7.5, 0, 0, 1.4, 2.2, 2.6, PALETTE.tankStand);
  b.pane(8.2, 1.0, 0, 1.8, 1.4);
  b.pane(8.1, 0, -3.2, 2.2, 2.5);
  b.pane(8.1, 0, 3.2, 2.2, 2.5);
  b.box(0, 11, 0, 16.4, 14.4, 0.35, PALETTE.roof);
  return b;
}

function buildSupermarket() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 15, 24, 6.5, PALETTE.concrete);
  b.pane(7.55, 0.4, 2, 12, 4.2);
  b.commWindowBand(0, 1.0, -8, 15, 6, 1, 2);
  b.commAwning(8.4, 4.8, 2, 2.2, 14, 0.25, PALETTE.commMint);
  for (const side of [-6.5, 0, 6.5]) b.box(9.3, 0, 2 + side, 0.2, 0.2, 4.8, PALETTE.tankStand);
  b.box(8.2, 0, -8, 2.8, 3.5, 0.12, PALETTE.concrete);
  b.box(8.2, 0.12, -9.6, 2.6, 0.1, 1.0, PALETTE.tankStand);
  b.box(8.2, 0.12, -6.4, 2.6, 0.1, 1.0, PALETTE.tankStand);
  b.box(6.9, 0.12, -8, 0.1, 3.2, 1.0, PALETTE.tankStand);
  b.box(0, 6.5, 0, 15.5, 24.5, 0.3, PALETTE.roof);
  b.cylinder(-2, 6.8, 4, 1.2, 1.5, PALETTE.tankStand, 8);
  b.cylinder(-2, 6.8, -4, 1.2, 1.5, PALETTE.tankStand, 8);
  return b;
}

function buildCornerOffice() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 16, 16, 15.5, PALETTE.tileWhite);
  b.commWindowBand(0, 3.5, 0, 16, 16, 3, 4);
  b.pane(8.05, 0, 0, 4.5, 3.2);
  b.box(8.8, 3.4, 0, 1.8, 6.0, 0.25, PALETTE.canopy);
  for (const side of [-2.6, 2.6]) b.box(9.5, 0, side, 0.18, 0.18, 3.4, PALETTE.tankStand);
  b.box(8.1, 3.8, 0, 0.25, 12, 1.1, PALETTE.commBlue);
  b.box(-2, 15.5, -2, 6, 6, 3.2, PALETTE.concrete);
  b.box(0, 15.5, 0, 16.4, 16.4, 0.35, PALETTE.roof);
  return b;
}

function buildYellowCafe() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 10, 11, 7.5, PALETTE.counters1);
  b.pane(5.05, 0.6, -1.8, 4.2, 2.4);
  b.pane(5.05, 0, 2.5, 1.8, 2.6);
  b.commWindowBand(0, 4.0, 0, 10, 11, 1, 3);
  b.commAwning(5.8, 3.4, -1.8, 1.8, 5.2, 0.25, PALETTE.commYellow);
  b.box(0, 7.5, 0, 10.5, 11.5, 0.35, PALETTE.roof);
  b.gable(0, 7.85, 0, 9.5, 10.5, 2.6, PALETTE.playerRoof);
  return b;
}

function buildGasStation() {
  const b = new MeshBuilder();
  b.box(-6, 0, 0, 6, 10, 4.2, PALETTE.tileWhite);
  b.pane(-3.05, 0.2, 0, 4.5, 2.8);
  b.commWindowBand(-6, 1.0, 0, 6, 10, 1, 2);
  b.box(-6, 4.2, 0, 6.4, 10.4, 0.25, PALETTE.roof);
  b.box(4, 5.2, 0, 12, 18, 0.6, PALETTE.canopy);
  b.box(4, 5.0, 0, 11.6, 17.6, 0.1, PALETTE.tileWhite);
  for (const cx of [0, 8]) {
    for (const cz of [-5.5, 5.5]) {
      b.cylinder(cx, 0, cz, 0.30, 5.2, PALETTE.tankStand, 12);
    }
  }
  for (const pz of [-4, 4]) {
    b.box(4, 0, pz, 6, 1.8, 0.22, PALETTE.concrete);
    b.box(2.8, 0.22, pz, 1.1, 0.9, 1.6, PALETTE.commRed);
    b.box(5.2, 0.22, pz, 1.1, 0.9, 1.6, PALETTE.commBlue);
    b.cylinder(0.7, 0, pz, 0.12, 0.9, PALETTE.commYellow, 8);
    b.cylinder(7.3, 0, pz, 0.12, 0.9, PALETTE.commYellow, 8);
  }
  b.box(11, 0, -9, 0.4, 2.0, 6.5, PALETTE.commBlue);
  b.box(11, 3.2, -9, 0.5, 1.8, 2.8, PALETTE.trainYellow);
  return b;
}

function buildParkingGarage() {
  const b = new MeshBuilder();
  const length = 16, width = 18;
  for (let tier = 0; tier < 3; tier++) {
    const ty = tier * 3.4;
    b.box(0, ty, 0, length, width, 0.35, PALETTE.concrete);
    for (const sign of [-1, 1]) {
      b.box(0, ty + 0.35, sign * (width / 2 - 0.1), length, 0.18, 0.9, PALETTE.tankStand);
      b.box(sign * (length / 2 - 0.1), ty + 0.35, 0, 0.18, width, 0.9, PALETTE.tankStand);
    }
  }
  for (const cx of [-length / 2 + 0.6, 0, length / 2 - 0.6]) {
    for (const cz of [-width / 2 + 0.6, 0, width / 2 - 0.6]) {
      b.box(cx, 0, cz, 0.8, 0.8, 7.2, PALETTE.concrete);
    }
  }
  b.box(8.2, 0, 2.5, 0.5, 0.5, 1.2, PALETTE.commYellow);
  b.box(8.2, 0.9, 0.5, 0.15, 3.2, 0.15, PALETTE.commRed);
  b.stairs(-2, 0, 7.2, 8, 3.2, 3.4);
  return b;
}

function buildCommercialHotel() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 14, 18, 17, PALETTE.tileWhite);
  b.commWindowBand(0, 4.0, 0, 14, 18, 4, 4);
  b.pane(7.05, 0.3, 0, 10, 3.2);
  b.box(9.2, 3.8, 0, 5.0, 12, 0.4, PALETTE.canopy);
  for (const cz of [-4.8, 4.8]) b.cylinder(11.2, 0, cz, 0.32, 3.8, PALETTE.tankStand, 12);
  b.box(7.15, 6, -7.5, 0.4, 0.9, 9.5, PALETTE.commBlue);
  b.box(0, 17, 0, 14.5, 18.5, 0.35, PALETTE.roof);
  return b;
}

function buildBankBranch() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 14, 16, 9.5, PALETTE.concrete);
  b.commWindowBand(0, 4.2, 0, 14, 16, 1, 4);
  b.box(7.05, 0, 0, 0.6, 12, 8.8, PALETTE.tankStand);
  for (const pz of [-4, -1.5, 1.5, 4]) b.cylinder(7.35, 0, pz, 0.38, 7.2, PALETTE.tileWhite, 12);
  b.pane(7.1, 0, 0, 2.8, 3.4);
  b.box(7.2, 3.5, 0, 0.4, 3.4, 0.6, PALETTE.tankStand);
  b.pane(7.1, 0, 5.2, 2.0, 3.0);
  b.box(6.8, 0.9, 5.2, 0.3, 1.2, 0.9, PALETTE.commBlue);
  b.box(7.2, 7.2, 0, 0.8, 12.8, 1.6, PALETTE.concrete);
  b.box(0, 9.5, 0, 14.4, 16.4, 0.35, PALETTE.roof);
  return b;
}

function buildStackedShopHouse() {
  const b = new MeshBuilder();
  b.box(-1.5, 0, 0, 11, 7.5, 12, PALETTE.counters1);
  b.box(3.5, 0, 0, 2.5, 7.5, 0.18, PALETTE.concrete);
  b.box(4.5, 0, -3.2, 0.5, 0.5, 3.8, PALETTE.concrete);
  b.box(4.5, 0, 3.2, 0.5, 0.5, 3.8, PALETTE.concrete);
  b.pane(2.2, 0, 0, 5.5, 2.8);
  b.box(2.25, 2.9, 0, 0.3, 6.0, 0.6, PALETTE.tankStand);
  b.commWindowBand(-1.5, 4.2, 0, 11, 7.5, 2, 2);
  for (let floor = 1; floor <= 2; floor++) {
    const by = floor * 3.8;
    b.box(4.2, by, 0, 1.4, 7.5, 0.22, PALETTE.concrete);
    b.box(4.8, by + 0.22, 0, 0.12, 7.5, 0.9, PALETTE.tankStand);
  }
  b.box(-1.5, 12, 0, 11.4, 7.9, 0.35, PALETTE.roof);
  b.cylinder(-3, 12.35, 1.5, 0.9, 1.8, PALETTE.tankStand, 12);
  return b;
}

function buildWarehouseStore() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 16, 20, 8.5, PALETTE.concrete);
  b.commWindowBand(0, 4.5, 0, 16, 20, 1, 4);
  b.box(9.2, 0, 0, 2.8, 14, 1.2, PALETTE.concrete);
  for (const side of [-3.5, 3.5]) {
    b.box(8.05, 1.2, side, 0.2, 4.5, 4.2, PALETTE.tankStand);
    b.box(10.6, 0.7, side - 1.8, 0.15, 0.35, 0.6, PALETTE.playerRim);
    b.box(10.6, 0.7, side + 1.8, 0.15, 0.35, 0.6, PALETTE.playerRim);
  }
  b.gable(0, 8.5, 0, 16.5, 20.5, 3.2, PALETTE.commBlue);
  return b;
}

function buildMetroEntrance() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 9, 5.5, 1.2, PALETTE.tankStand);
  b.stairs(0.5, 0, 0, 6.5, 2.8, 2.2);
  b.canopy(0, 2.4, 0, 10.5, 6.2, 1.4, PALETTE.commMint);
  for (const cx of [-4, 4]) {
    for (const cz of [-2.6, 2.6]) {
      b.cylinder(cx, 0, cz, 0.16, 2.8, PALETTE.tankStand, 8);
    }
  }
  b.box(5.2, 0, 3.2, 0.35, 0.8, 3.6, PALETTE.commMint);
  b.box(5.2, 2.6, 3.2, 0.42, 0.7, 0.7, PALETTE.tileWhite);
  return b;
}

// Category 2: 12 Shops
function buildBubbleTeaShop() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 1.4, 3.2, 0.95, PALETTE.tileWhite);
  b.box(0.1, 0.95, 0, 1.6, 3.4, 0.08, PALETTE.counters1);
  b.box(-0.2, 1.03, -0.9, 0.45, 0.45, 0.65, PALETTE.commBlue);
  b.cylinder(-0.2, 1.68, -0.9, 0.16, 0.15, PALETTE.commYellow, 8);
  for (let i = 0; i < 3; i++) {
    const pz = -0.2 + i * 0.5;
    b.cylinder(-0.2, 1.03, pz, 0.18, 0.55, PALETTE.tankStand, 10);
    b.box(0.05, 1.15, pz, 0.12, 0.08, 0.1, PALETTE.commRed);
  }
  b.box(0, 2.3, 0, 0.15, 2.8, 0.65, PALETTE.tankStand);
  b.box(0.08, 2.34, 0, 0.02, 2.65, 0.55, PALETTE.trainAccent);
  return b;
}

function buildBentoShop() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 1.5, 3.0, 0.85, PALETTE.concrete);
  b.box(0.1, 0.85, 0, 1.6, 3.1, 0.08, PALETTE.tankStand);
  b.box(0.45, 0.93, 0, 0.05, 2.8, 0.55, PALETTE.glazing);
  b.box(0.2, 1.48, 0, 0.55, 2.8, 0.05, PALETTE.glazing);
  for (let i = 0; i < 4; i++) {
    const pz = -0.9 + i * 0.6;
    b.box(0, 0.93, pz, 0.55, 0.45, 0.15, PALETTE.counters1);
  }
  b.cylinder(-0.4, 0, 1.1, 0.35, 0.85, PALETTE.tankStand, 10);
  b.cylinder(-0.4, 0.85, 1.1, 0.32, 0.25, PALETTE.commRed, 10);
  return b;
}

function buildBakery() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 1.3, 2.8, 0.80, PALETTE.counters1);
  for (let tier = 0; tier < 3; tier++) {
    const ty = 0.88 + tier * 0.42, tx = 0.15 - tier * 0.12;
    b.box(tx, ty, 0, 0.85, 2.6, 0.05, PALETTE.counters0);
    for (let i = 0; i < 4; i++) {
      b.cylinder(tx, ty + 0.05, -0.9 + i * 0.6, 0.12, 0.10, PALETTE.commYellow, 8);
    }
  }
  b.box(-0.1, 2.2, 0, 1.2, 2.8, 0.15, PALETTE.counters1);
  return b;
}

function buildPharmacy() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 1.2, 2.6, 0.90, PALETTE.tileWhite);
  b.box(0.05, 0.90, 0, 1.3, 2.7, 0.06, PALETTE.concrete);
  b.box(-0.9, 0, 0, 0.45, 2.6, 2.2, PALETTE.tileWhite);
  for (let shelf = 1; shelf <= 4; shelf++) {
    b.box(-0.7, shelf * 0.45, 0, 0.4, 2.5, 0.04, PALETTE.concrete);
    for (let i = 0; i < 5; i++) {
      b.box(-0.7, shelf * 0.45 + 0.04, -0.9 + i * 0.45, 0.25, 0.30, 0.25, PALETTE.commBlue);
    }
  }
  b.box(0.4, 1.1, 1.1, 0.15, 0.55, 0.55, PALETTE.tileWhite);
  b.box(0.48, 1.15, 1.1, 0.04, 0.45, 0.15, PALETTE.commMint);
  b.box(0.48, 1.15, 1.1, 0.04, 0.15, 0.45, PALETTE.commMint);
  return b;
}

function buildCornerGrocery() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 1.4, 2.8, 0.78, PALETTE.counters1);
  for (let i = 0; i < 4; i++) {
    const pz = -0.9 + i * 0.6;
    b.cylinder(0.1, 0.78, pz, 0.18, 0.38, PALETTE.glazing, 10);
    b.cylinder(0.1, 1.16, pz, 0.20, 0.08, PALETTE.commRed, 10);
  }
  b.box(-0.4, 0, -1.8, 0.85, 0.85, 1.9, PALETTE.tileWhite);
  b.pane(0.05, 0.15, -1.8, 0.65, 1.6);
  return b;
}

function buildStationeryStore() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 1.5, 2.6, 0.75, PALETTE.concrete);
  for (let tier = 0; tier < 3; tier++) {
    const ty = 0.80 + tier * 0.35, tx = 0.2 - tier * 0.15;
    b.box(tx, ty, 0, 0.75, 2.4, 0.05, PALETTE.counters1);
    for (let i = 0; i < 3; i++) {
      b.box(tx, ty + 0.05, -0.7 + i * 0.7, 0.45, 0.50, 0.18, PALETTE.commBlue);
    }
  }
  b.cylinder(-0.5, 0, 1.6, 0.05, 1.7, PALETTE.tankStand, 6);
  b.cylinder(-0.5, 0.8, 1.6, 0.30, 0.8, PALETTE.commYellow, 8);
  return b;
}

function buildRamenYatai() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 1.6, 2.4, 0.75, PALETTE.counters1);
  b.box(0.1, 0.75, 0, 1.8, 2.6, 0.08, PALETTE.counters0);
  for (const cx of [-0.7, 0.7]) {
    for (const cz of [-1.1, 1.1]) {
      b.box(cx, 0.75, cz, 0.10, 0.10, 1.5, PALETTE.counters1);
    }
  }
  b.gable(0, 2.25, 0, 2.0, 2.8, 0.55, PALETTE.playerRoof);
  b.box(0.9, 1.95, 0, 0.05, 2.6, 0.30, PALETTE.commRed);
  b.cylinder(-0.2, 0.83, -0.4, 0.25, 0.35, PALETTE.tankStand, 10);
  for (let i = 0; i < 3; i++) {
    const sz = -0.8 + i * 0.8;
    b.cylinder(1.2, 0, sz, 0.22, 0.48, PALETTE.counters1, 8);
    b.cylinder(1.2, 0, sz, 0.06, 0.45, PALETTE.tankStand, 6);
  }
  return b;
}

function buildNightMarketFryer() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 1.2, 2.2, 0.82, PALETTE.tankStand);
  b.box(0.05, 0.82, 0, 1.3, 2.3, 0.06, PALETTE.tankStand);
  b.box(0.4, 0.88, 0, 0.04, 2.1, 0.55, PALETTE.glazing);
  b.box(0.15, 1.43, 0, 0.50, 2.1, 0.04, PALETTE.glazing);
  b.box(-0.1, 0.75, -0.5, 0.55, 0.65, 0.25, PALETTE.playerRim);
  b.box(-0.1, 0.88, 0.4, 0.55, 0.95, 0.12, PALETTE.commYellow);
  b.cylinder(-0.3, 1.5, 0, 0.25, 0.5, PALETTE.tankStand, 8);
  b.cylinder(-0.3, 2.0, 0, 0.12, 0.5, PALETTE.tankStand, 8);
  return b;
}

function buildNightMarketFruit() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 1.2, 2.4, 0.80, PALETTE.tankStand);
  b.box(0.05, 0.80, 0, 1.1, 2.3, 0.15, PALETTE.tileWhite);
  b.box(0.45, 0.95, 0, 0.04, 2.2, 0.45, PALETTE.glazing);
  const fruitColors = [PALETTE.commRed, PALETTE.commYellow, PALETTE.commMint, 0xFFFF8040];
  for (let i = 0; i < 4; i++) {
    b.box(0.05, 0.95, -0.75 + i * 0.5, 0.65, 0.42, 0.12, fruitColors[i]);
  }
  b.beam([-0.4, 0.8, -0.9], [-0.4, 1.9, -0.9], 0.05, PALETTE.tankStand);
  b.beam([-0.4, 1.9, -0.9], [0.1, 1.9, 0], 0.05, PALETTE.tankStand);
  b.cylinder(0.1, 1.82, 0, 0.12, 0.15, PALETTE.commYellow, 8);
  return b;
}

function buildNightMarketGame() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 1.4, 2.4, 0.65, PALETTE.counters1);
  for (let i = 0; i < 4; i++) {
    b.box(0.1, 0.70, -0.75 + i * 0.5, 0.95, 0.42, 0.15, PALETTE.commBlue);
  }
  b.box(-0.6, 0.65, 0, 0.35, 2.4, 1.2, PALETTE.counters0);
  for (let i = 0; i < 3; i++) {
    b.box(-0.55, 1.2, -0.6 + i * 0.6, 0.25, 0.35, 0.35, PALETTE.commRed);
  }
  b.cylinder(0.9, 0, 0, 0.22, 0.35, PALETTE.commMint, 8);
  return b;
}

function buildVendingBank() {
  const b = new MeshBuilder();
  for (let i = 0; i < 3; i++) {
    const pz = -1.1 + i * 1.05;
    const bodyColor = i === 0 ? PALETTE.commRed : i === 1 ? PALETTE.commBlue : PALETTE.commMint;
    b.box(0, 0, pz, 0.95, 0.95, 1.95, bodyColor);
    b.pane(0.48, 0.65, pz, 0.75, 0.95);
    b.box(0.48, 0.20, pz, 0.04, 0.65, 0.25, PALETTE.playerRim);
  }
  b.box(0, 0, 1.6, 0.75, 0.75, 1.05, PALETTE.concrete);
  b.cylinder(0, 1.05, 1.45, 0.12, 0.04, PALETTE.playerRim, 8);
  b.cylinder(0, 1.05, 1.75, 0.12, 0.04, PALETTE.playerRim, 8);
  return b;
}

function buildMobileFoodCart() {
  const b = new MeshBuilder();
  b.box(0, 0.25, 0, 2.8, 1.8, 2.0, PALETTE.tileWhite);
  b.commWheel(0, 0, -1.0, 0.40, 0.22);
  b.commWheel(0, 0, 1.0, 0.40, 0.22);
  b.box(0, 0.75, -0.92, 1.8, 0.05, 0.95, PALETTE.playerRim);
  b.commAwning(0, 1.75, -1.2, 2.0, 0.9, 0.15, PALETTE.commYellow);
  b.beam([1.4, 0.35, 0], [2.2, 0.35, 0], 0.10, PALETTE.tankStand);
  b.cylinder(2.0, 0, 0, 0.08, 0.35, PALETTE.tankStand, 6);
  return b;
}

// Category 3: 12 Facilities & Vehicle
function buildVerticalNeonSign() {
  const b = new MeshBuilder();
  for (const hy of [0.8, 4.2]) b.box(0.25, hy, 0, 0.50, 0.08, 0.08, PALETTE.tankStand);
  b.cylinder(0.50, 0.4, 0, 0.06, 4.2, PALETTE.tankStand, 6);
  for (let i = 0; i < 3; i++) {
    const sy = 0.6 + i * 1.3;
    const boxColor = i === 0 ? PALETTE.commRed : i === 1 ? PALETTE.commYellow : PALETTE.commBlue;
    b.box(0.95, sy, 0, 0.85, 0.22, 1.15, boxColor);
    b.box(0.95, sy + 0.1, 0.12, 0.70, 0.03, 0.95, PALETTE.tileWhite);
    b.box(0.95, sy + 0.1, -0.12, 0.70, 0.03, 0.95, PALETTE.tileWhite);
  }
  return b;
}

function buildHorizontalSignboard() {
  const b = new MeshBuilder();
  b.box(0.12, 0.3, 0, 0.24, 4.2, 1.1, PALETTE.counters1);
  b.box(0.25, 0.35, 0, 0.03, 4.0, 0.95, PALETTE.commYellow);
  for (let i = 0; i < 3; i++) {
    const sz = -1.4 + i * 1.4;
    b.beam([0.05, 1.4, sz], [0.55, 1.6, sz], 0.04, PALETTE.tankStand);
    b.cylinder(0.55, 1.50, sz, 0.08, 0.12, PALETTE.tankStand, 6);
  }
  return b;
}

function buildTotemLightbox() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 0.8, 1.4, 0.18, PALETTE.concrete);
  b.box(0, 0.18, 0, 0.35, 1.2, 3.4, PALETTE.commBlue);
  for (const sign of [-1, 1]) {
    b.box(sign * 0.19, 0.6, 0, 0.03, 0.95, 2.5, PALETTE.tileWhite);
  }
  return b;
}

function buildAFrameSign() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 0.56, 0.75, 1.05, PALETTE.counters1);
  b.box(0, 0.15, 0, 0.60, 0.62, 0.75, PALETTE.playerRim);
  b.beam([-0.16, 0.45, 0], [0.16, 0.45, 0], 0.02, PALETTE.tankStand);
  return b;
}

function buildCommercialBannerPole() {
  const b = new MeshBuilder();
  b.cylinder(0, 0, 0, 0.20, 0.45, PALETTE.concrete, 8);
  b.cylinder(0, 0.45, 0, 0.08, 4.8, PALETTE.tankStand, 8);
  b.cylinder(0, 5.25, 0, 0.35, 0.25, PALETTE.commYellow, 8);
  for (const by of [2.2, 4.4]) {
    b.beam([0, by, -0.9], [0, by, 0.9], 0.04, PALETTE.tankStand);
  }
  for (const sign of [-0.55, 0.55]) {
    b.box(0, 2.2, sign, 0.02, 0.65, 2.2, PALETTE.commBlue);
  }
  return b;
}

function buildRetractableAwning() {
  const b = new MeshBuilder();
  b.box(0.06, 0.8, 0, 0.12, 3.6, 0.18, PALETTE.tankStand);
  for (const az of [-1.5, 1.5]) {
    b.beam([0.08, 0.8, az], [1.1, 0.65, az], 0.05, PALETTE.tankStand);
    b.beam([1.1, 0.65, az], [2.1, 0.5, az], 0.05, PALETTE.tankStand);
  }
  b.commAwning(1.14, 0.52, 0, 2.12, 3.6, 0.36, PALETTE.commYellow);
  b.box(2.2, 0.34, 0, 0.04, 3.6, 0.18, PALETTE.commRed);
  return b;
}

function buildCafeUmbrellaSet() {
  const b = new MeshBuilder();
  b.cylinder(0, 0, 0, 0.35, 0.06, PALETTE.playerRim, 12);
  b.cylinder(0, 0.06, 0, 0.05, 2.3, PALETTE.tankStand, 8);
  b.cylinder(0, 0.70, 0, 0.65, 0.04, PALETTE.tileWhite, 12);
  b.canopy(0, 1.9, 0, 2.6, 2.6, 0.55, PALETTE.commMint);
  for (let i = 0; i < 3; i++) {
    const a = (i * 2 * Math.PI) / 3.0;
    const cx = Math.cos(a) * 0.95, cz = Math.sin(a) * 0.95;
    b.cylinder(cx, 0, cz, 0.22, 0.44, PALETTE.counters1, 8);
    b.cylinder(cx, 0, cz, 0.04, 0.40, PALETTE.tankStand, 6);
    b.cylinder(cx * 1.15, 0.44, cz * 1.15, 0.22, 0.38, PALETTE.counters1, 6);
  }
  return b;
}

function buildCommercialPlanter() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 1.1, 3.2, 0.55, PALETTE.concrete);
  b.box(0, 0.55, 0, 0.95, 3.0, 0.08, PALETTE.playerRoof);
  for (let i = 0; i < 3; i++) {
    b.cylinder(0, 0.60, -0.9 + i * 0.9, 0.42, 0.55, PALETTE.greens[i], 8);
  }
  for (const sign of [-1.4, 1.4]) {
    b.cylinder(-0.45, 0.55, sign, 0.04, 0.55, PALETTE.tankStand, 6);
  }
  b.beam([-0.45, 1.1, -1.4], [-0.45, 1.1, 1.4], 0.06, PALETTE.tankStand);
  return b;
}

function buildCommercialRecycling() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 0.85, 2.4, 0.95, PALETTE.tankStand);
  const binColors = [PALETTE.playerRim, PALETTE.commYellow, PALETTE.commBlue];
  for (let i = 0; i < 3; i++) {
    const pz = -0.75 + i * 0.75;
    b.box(0, 0.95, pz, 0.75, 0.65, 0.08, binColors[i]);
    b.cylinder(0, 1.03, pz, 0.16, 0.04, PALETTE.playerRim, 8);
  }
  return b;
}

function buildCoolingTower() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 2.6, 2.6, 0.25, PALETTE.tankStand);
  b.box(0, 0.25, 0, 2.4, 2.4, 1.8, PALETTE.tileWhite);
  for (const side of [-1.22, 1.22]) {
    b.box(0, 0.45, side, 2.2, 0.04, 1.3, PALETTE.playerRim);
  }
  b.cylinder(0, 2.05, 0, 0.95, 0.55, PALETTE.concrete, 12);
  b.cylinder(0, 2.60, 0, 0.88, 0.06, PALETTE.tankStand, 8);
  return b;
}

function buildFireEscapeStair() {
  const b = new MeshBuilder();
  b.box(1.0, 3.2, 0, 2.0, 1.8, 0.12, PALETTE.tankStand);
  b.box(2.0, 3.32, 0, 0.08, 1.8, 0.9, PALETTE.tankStand);
  b.box(1.0, 3.32, -0.9, 2.0, 0.08, 0.9, PALETTE.tankStand);
  b.stairs(1.0, 0, 1.8, 2.8, 1.1, 3.2);
  for (const hy of [0.5, 3.2]) {
    b.box(0.2, hy, -0.8, 0.4, 0.12, 0.12, PALETTE.tankStand);
    b.box(0.2, hy, 0.8, 0.4, 0.12, 0.12, PALETTE.tankStand);
  }
  return b;
}

function buildTransitFeederBus() {
  const b = new MeshBuilder();
  const length = 10.4, width = 2.5, chassisY = 0.35;

  // Lower white skirt
  b.box(0, chassisY, 0, length, width, 0.75, PALETTE.tileWhite);

  // Upper tinted glass band
  b.box(0, chassisY + 0.75, 0, length, width, 1.45, PALETTE.playerRim);
  for (let i = -3; i <= 3; i++) {
    const px = i * 1.3;
    b.box(px, chassisY + 0.75, -width / 2, 0.12, 0.04, 1.45, PALETTE.commMint);
    b.box(px, chassisY + 0.75, width / 2, 0.12, 0.04, 1.45, PALETTE.commMint);
  }

  // Mint green curved roof structure
  b.box(0, chassisY + 2.2, 0, length, width, 0.45, PALETTE.commMint);
  // Aerodynamic forward slope over windshield
  b.commAwning(length / 2 - 0.9, chassisY + 2.30, 0, 1.8, width, 0.35, PALETTE.commMint);

  // Front panoramic windscreen
  b.pane(length / 2 + 0.02, chassisY + 0.75, 0, width - 0.25, 1.45);
  // Destination marquee visor
  b.box(length / 2 - 0.05, chassisY + 2.22, 0, 0.25, 1.8, 0.32, PALETTE.trainAccent);

  // Low floor dual entrance doors
  for (const doorX of [2.8, -0.8]) {
    b.box(doorX, chassisY, -width / 2 - 0.02, 1.25, 0.05, 1.95, PALETTE.tankStand);
    b.pane(doorX, chassisY + 0.35, -width / 2 - 0.03, 1.05, 1.4);
  }

  // Windshield wipers
  b.beam([length / 2 + 0.04, chassisY + 0.85, -0.4], [length / 2 + 0.04, chassisY + 1.25, 0.1], 0.03, PALETTE.playerRim);
  b.beam([length / 2 + 0.04, chassisY + 0.85, 0.4], [length / 2 + 0.04, chassisY + 1.25, 0.9], 0.03, PALETTE.playerRim);

  // Rear louvers & rear window
  b.pane(-length / 2 - 0.02, chassisY + 1.25, 0, width - 0.4, 0.95);
  b.box(-length / 2 - 0.02, chassisY + 0.45, 0, 0.04, 1.9, 0.65, PALETTE.playerRim);

  // Headlights & taillights
  for (const sign of [-0.95, 0.95]) {
    b.cylinder(length / 2 + 0.02, chassisY + 0.45, sign, 0.12, 0.04, PALETTE.trainYellow, 8);
    b.cylinder(-length / 2 - 0.02, chassisY + 0.45, sign, 0.12, 0.04, PALETTE.commRed, 8);
  }

  // Roof battery / HVAC pod
  b.box(0, chassisY + 2.65, 0, 3.8, 1.9, 0.45, PALETTE.tileWhite);
  b.box(0, chassisY + 2.75, 0, 3.2, 1.6, 0.25, PALETTE.tankStand);

  // 4 Wheels
  b.commWheel(2.9, 0, -width / 2 + 0.05, 0.46, 0.28);
  b.commWheel(2.9, 0, width / 2 - 0.05, 0.46, 0.28);
  b.commWheel(-2.9, 0, -width / 2 + 0.05, 0.48, 0.36);
  b.commWheel(-2.9, 0, width / 2 - 0.05, 0.48, 0.36);
  return b;
}

// Map of part builders
const PART_BUILDERS = {
  departmentStore: {fn: buildDepartmentStore, category: 'building', name: '百貨商場', mount: 'ground'},
  cinema: {fn: buildCinema, category: 'building', name: '復古裝飾風電影院', mount: 'ground'},
  supermarket: {fn: buildSupermarket, category: 'building', name: '生鮮超市', mount: 'ground'},
  cornerOffice: {fn: buildCornerOffice, category: 'building', name: '街角商務辦公樓', mount: 'ground'},
  yellowCafe: {fn: buildYellowCafe, category: 'building', name: '暖黃磚瓦咖啡館', mount: 'ground'},
  gasStation: {fn: buildGasStation, category: 'building', name: '公路加油站', mount: 'ground'},
  parkingGarage: {fn: buildParkingGarage, category: 'building', name: '多層立體停車場', mount: 'ground'},
  commercialHotel: {fn: buildCommercialHotel, category: 'building', name: '商務飯店', mount: 'ground'},
  bankBranch: {fn: buildBankBranch, category: 'building', name: '銀行分行', mount: 'ground'},
  stackedShopHouse: {fn: buildStackedShopHouse, category: 'building', name: '商住複合透天樓', mount: 'ground'},
  warehouseStore: {fn: buildWarehouseStore, category: 'building', name: '批發物流商場', mount: 'ground'},
  metroEntrance: {fn: buildMetroEntrance, category: 'building', name: '捷運地下街出入口', mount: 'ground'},

  bubbleTeaShop: {fn: buildBubbleTeaShop, category: 'shop', name: '騎樓手搖飲店', mount: 'ground'},
  bentoShop: {fn: buildBentoShop, category: 'shop', name: '台式便當小吃店', mount: 'ground'},
  bakery: {fn: buildBakery, category: 'shop', name: '傳統烘焙麵包坊', mount: 'ground'},
  pharmacy: {fn: buildPharmacy, category: 'shop', name: '健保西藥房', mount: 'ground'},
  cornerGrocery: {fn: buildCornerGrocery, category: 'shop', name: '傳統柑仔店/雜貨店', mount: 'ground'},
  stationeryStore: {fn: buildStationeryStore, category: 'shop', name: '文具書局', mount: 'ground'},
  ramenYatai: {fn: buildRamenYatai, category: 'shop', name: '拉麵熱食屋台', mount: 'ground'},
  nightMarketFryer: {fn: buildNightMarketFryer, category: 'shop', name: '夜市炸物鹽酥雞攤', mount: 'ground'},
  nightMarketFruit: {fn: buildNightMarketFruit, category: 'shop', name: '夜市現切水果攤', mount: 'ground'},
  nightMarketGame: {fn: buildNightMarketGame, category: 'shop', name: '夜市打彈珠遊戲攤', mount: 'ground'},
  vendingBank: {fn: buildVendingBank, category: 'shop', name: '自動販賣機組合', mount: 'ground'},
  mobileFoodCart: {fn: buildMobileFoodCart, category: 'shop', name: '外帶餐車', mount: 'ground'},

  verticalNeonSign: {fn: buildVerticalNeonSign, category: 'facility', name: '垂直霓虹/燈箱招牌', mount: 'wall'},
  horizontalSignboard: {fn: buildHorizontalSignboard, category: 'facility', name: '橫式店面招牌', mount: 'wall'},
  totemLightbox: {fn: buildTotemLightbox, category: 'facility', name: '雙面獨立燈箱立牌', mount: 'ground'},
  aFrameSign: {fn: buildAFrameSign, category: 'facility', name: 'A字黑板菜單立牌', mount: 'ground'},
  commercialBannerPole: {fn: buildCommercialBannerPole, category: 'facility', name: '商業路燈羅馬旗', mount: 'ground'},
  retractableAwning: {fn: buildRetractableAwning, category: 'facility', name: '騎樓帆布伸縮雨棚', mount: 'wall'},
  cafeUmbrellaSet: {fn: buildCafeUmbrellaSet, category: 'facility', name: '露天咖啡陽傘座組', mount: 'ground'},
  commercialPlanter: {fn: buildCommercialPlanter, category: 'facility', name: '商圈花箱護欄組', mount: 'ground'},
  commercialRecycling: {fn: buildCommercialRecycling, category: 'facility', name: '商圈分類資源回收箱', mount: 'ground'},
  coolingTower: {fn: buildCoolingTower, category: 'facility', name: '商辦屋頂水冷卻塔', mount: 'ground'},
  fireEscapeStair: {fn: buildFireEscapeStair, category: 'facility', name: '外掛逃生鋼梯', mount: 'wall'},
  transitFeederBus: {fn: buildTransitFeederBus, category: 'facility', name: '市區接駁公車', mount: 'ground'}
};

console.log('Generating 36 commercial parts...');
const builtMeshes = {};
const records = [];

for (const [key, info] of Object.entries(PART_BUILDERS)) {
  const mesh = info.fn();
  builtMeshes[key] = mesh;
  const id = 'commercial-' + key;
  const fileName = 'models/' + id + '.m3dmodel';
  const filePath = resolve(outputDir, fileName);
  writeM3DModel(filePath, id, mesh.vertices, 'remixed-native-game-asset');

  let minX = Infinity, minY = Infinity, minZ = Infinity;
  let maxX = -Infinity, maxY = -Infinity, maxZ = -Infinity;
  for (const v of mesh.vertices) {
    minX = Math.min(minX, v.x); minY = Math.min(minY, v.y); minZ = Math.min(minZ, v.z);
    maxX = Math.max(maxX, v.x); maxY = Math.max(maxY, v.y); maxZ = Math.max(maxZ, v.z);
  }

  const normal = info.mount === 'wall' ? [-1, 0, 0] : [0, 0, -1];
  const connectors = [{name: 'mount', position: [0, 0, 0], normal}];
  if (key === 'bubbleTeaShop') connectors.push({name: 'counter', position: [0, 0, 0.95], normal: [0, 0, 1]});
  if (key === 'bentoShop') connectors.push({name: 'counter', position: [0, 0, 0.85], normal: [0, 0, 1]});
  if (key === 'bakery') connectors.push({name: 'shelf', position: [0, 0, 0.80], normal: [0, 0, 1]});
  if (key === 'pharmacy') connectors.push({name: 'counter', position: [0, 0, 0.90], normal: [0, 0, 1]});
  if (key === 'cafeUmbrellaSet') connectors.push({name: 'tableTop', position: [0, 0, 0.74], normal: [0, 0, 1]});
  if (key === 'transitFeederBus') {
    connectors.push({name: 'frontDoor', position: [2.8, -1.25, 0.35], normal: [0, -1, 0]});
    connectors.push({name: 'rearDoor', position: [-0.8, -1.25, 0.35], normal: [0, -1, 0]});
  }

  records.push({
    id,
    name: info.name,
    category: info.category,
    mount: info.mount,
    fidelity: 'remixed-native-game-asset',
    native: fileName,
    triangles: mesh.vertices.length / 3,
    minimum: [minX, minY, minZ],
    maximum: [maxX, maxY, maxZ],
    connectors
  });
}

// 4 Assemblies
console.log('Generating 4 commercial assemblies...');
function buildCommercialAvenue() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 36, 44, 0.12, PALETTE.plaza);
  b.box(4, 0.12, 0, 8, 44, 0.02, PALETTE.roadMajor);
  b.addModelAt(builtMeshes.departmentStore, -9, -12, 0.12, 0);
  b.addModelAt(builtMeshes.cinema, -8, 10, 0.12, 0);
  b.addModelAt(builtMeshes.yellowCafe, 12, -10, 0.12, Math.PI);
  b.addModelAt(builtMeshes.cafeUmbrellaSet, 12, -3, 0.12, 0);
  b.addModelAt(builtMeshes.commercialPlanter, 0, -6, 0.12, 0);
  b.addModelAt(builtMeshes.commercialPlanter, 0, 6, 0.12, 0);
  b.addModelAt(builtMeshes.commercialBannerPole, 0, -14, 0.12, 0);
  b.addModelAt(builtMeshes.commercialBannerPole, 0, 14, 0.12, 0);
  b.addModelAt(builtMeshes.transitFeederBus, 4, 2, 0.14, Math.PI / 2);
  return b;
}

function buildNightMarketAlley() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 26, 32, 0.12, PALETTE.plaza);
  b.addModelAt(builtMeshes.ramenYatai, -5, -8, 0.12, 0);
  b.addModelAt(builtMeshes.nightMarketFryer, -5, 0, 0.12, 0);
  b.addModelAt(builtMeshes.nightMarketFruit, -5, 8, 0.12, 0);
  b.addModelAt(builtMeshes.nightMarketGame, 5, -6, 0.12, Math.PI);
  b.addModelAt(builtMeshes.mobileFoodCart, 5, 6, 0.12, Math.PI);
  b.addModelAt(builtMeshes.commercialRecycling, 0, 12, 0.12, 0);
  b.addModelAt(builtMeshes.aFrameSign, -1, -12, 0.12, 0);
  b.addModelAt(builtMeshes.totemLightbox, 1, -12, 0.12, 0);
  return b;
}

function buildStationTransitHub() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 34, 38, 0.12, PALETTE.plaza);
  b.box(8, 0.12, 0, 7, 38, 0.02, PALETTE.roadMinor);
  b.addModelAt(builtMeshes.metroEntrance, -2, -10, 0.12, 0);
  b.addModelAt(builtMeshes.cornerOffice, -9, 8, 0.12, 0);
  b.addModelAt(builtMeshes.bankBranch, 12, 10, 0.12, Math.PI);
  b.addModelAt(builtMeshes.vendingBank, -2, -2, 0.12, 0);
  b.addModelAt(builtMeshes.totemLightbox, 4.2, -12, 0.12, 0);
  b.addModelAt(builtMeshes.transitFeederBus, 8, 0, 0.14, Math.PI / 2);
  return b;
}

function buildNeighborhoodRetailCorner() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 30, 32, 0.12, PALETTE.plaza);
  b.box(0, 0.12, 0, 6, 32, 0.02, PALETTE.roadMinor);
  b.addModelAt(builtMeshes.supermarket, -8, -6, 0.12, 0);
  b.addModelAt(builtMeshes.stackedShopHouse, -7, 10, 0.12, 0);
  b.addModelAt(builtMeshes.bakery, 7, -8, 0.12, Math.PI);
  b.addModelAt(builtMeshes.pharmacy, 7, 0, 0.12, Math.PI);
  b.addModelAt(builtMeshes.bubbleTeaShop, 7, 8, 0.12, Math.PI);
  b.addModelAt(builtMeshes.aFrameSign, 4, -5, 0.12, 0);
  b.addModelAt(builtMeshes.cafeUmbrellaSet, 4, 11, 0.12, 0);
  b.addModelAt(builtMeshes.commercialRecycling, -4, 3, 0.12, 0);
  return b;
}

const EXAMPLES = [
  {id: 'commercial-example-commercialAvenue', name: '繁華商業大道', fn: buildCommercialAvenue},
  {id: 'commercial-example-nightMarketAlley', name: '台灣夜市商圈', fn: buildNightMarketAlley},
  {id: 'commercial-example-stationTransitHub', name: '站前商業轉運站', fn: buildStationTransitHub},
  {id: 'commercial-example-neighborhoodRetailCorner', name: '社區街角生活商圈', fn: buildNeighborhoodRetailCorner}
];

for (const ex of EXAMPLES) {
  const mesh = ex.fn();
  const fileName = 'models/' + ex.id + '.m3dmodel';
  const filePath = resolve(outputDir, fileName);
  writeM3DModel(filePath, ex.id, mesh.vertices, 'illustrative-assembly');

  let minX = Infinity, minY = Infinity, minZ = Infinity;
  let maxX = -Infinity, maxY = -Infinity, maxZ = -Infinity;
  for (const v of mesh.vertices) {
    minX = Math.min(minX, v.x); minY = Math.min(minY, v.y); minZ = Math.min(minZ, v.z);
    maxX = Math.max(maxX, v.x); maxY = Math.max(maxY, v.y); maxZ = Math.max(maxZ, v.z);
  }

  records.push({
    id: ex.id,
    name: ex.name,
    category: 'example',
    fidelity: 'illustrative-assembly',
    native: fileName,
    triangles: mesh.vertices.length / 3,
    minimum: [minX, minY, minZ],
    maximum: [maxX, maxY, maxZ]
  });
}

const manifest = {
  schema_version: 1,
  generator: 'Map3DCommercialKit',
  recipe_version: 1,
  model_count: records.length,
  part_count: 36,
  example_count: 4,
  native_coordinates: 'metres; +x front, +y left, +z up',
  gltf_coordinates: 'metres; +x front, +y up, -z left',
  directions: ['top', 'bottom', 'left', 'right', 'front', 'back', 'isometric'],
  models: records,
  notes: 'Static commercial game models, recomposed from private reference factories and original geometry; illustrative retail buildings, night market stalls, street furniture and feeder transit bus.'
};

writeFileSync(resolve(outputDir, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(`Generated manifest with ${records.length} models (${manifest.part_count} parts, ${manifest.example_count} examples).`);
