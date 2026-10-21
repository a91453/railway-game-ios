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
  // Main auditorium body
  b.box(0, 0, 0, 17, 15, 13.0, PALETTE.warmWhite);
  // Stepped tower massing supporting the Art Deco facade
  b.box(4.5, 0, 0, 8.5, 9.5, 15.5, PALETTE.warmWhite);
  b.box(6.5, 0, 0, 4.5, 5.5, 17.5, PALETTE.warmWhite);

  // Stepped Art Deco front facade
  b.box(8.55, 0, 0, 0.45, 9.0, 15.0, PALETTE.commCyan);
  b.box(8.65, 0, 0, 0.55, 5.0, 16.5, PALETTE.templeRidge);
  b.box(8.75, 0, 0, 0.65, 2.2, 17.5, PALETTE.trainYellow);

  // Entrance marquee canopy with glowing underside
  b.box(10.0, 4.2, 0, 3.2, 11.0, 0.55, PALETTE.darkRoof);
  b.box(10.0, 4.0, 0, 3.0, 10.6, 0.15, PALETTE.warmGlow, 1);
  b.beam([8.8, 8.5, -4.5], [11.2, 4.7, -4.5], 0.08, PALETTE.steel);
  b.beam([8.8, 8.5, 4.5], [11.2, 4.7, 4.5], 0.08, PALETTE.steel);

  // Vertical Cinema Blade Signboard
  b.box(10.2, 7.5, 0, 0.45, 0.85, 7.5, PALETTE.commCrimson);
  b.box(10.45, 7.8, 0, 0.10, 0.65, 6.8, PALETTE.warmGlow, 1);

  // Movie poster lightboxes on facade
  for (const pz of [-3.8, 0, 3.8]) {
    b.box(8.6, 1.2, pz, 0.18, 1.8, 2.4, PALETTE.darkRoof);
    const posterColor = pz < -1 ? PALETTE.commBlue : pz > 1 ? PALETTE.commMint : PALETTE.commRed;
    b.box(8.7, 1.35, pz, 0.05, 1.5, 2.1, posterColor, 1);
  }

  // Brass ticket booth
  b.box(9.2, 0, 0, 1.6, 2.4, 2.6, PALETTE.darkWood);
  b.pane(9.95, 1.1, 0, 1.8, 1.3, PALETTE.warmWood, PALETTE.glazing);
  b.box(0, 13.0, 0, 17.5, 15.5, 0.35, PALETTE.darkRoof);
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

  // Shopping cart corral
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
  const width = 16, depth = 15, height = 18;
  const halfW = width / 2, halfD = depth / 2;

  // 1. Concrete ground plinth
  b.box(0, 0, 0, depth, width, 0.25, PALETTE.concrete);

  // 2. Ground floor entrance lobby (y = 0.25 to 4.25, height 4.0m)
  b.box(0, 0.25, 0, depth - 0.2, width - 0.2, 4.0, PALETTE.warmWhite);
  // Recessed double-height glass lobby curtain wall
  b.pane(halfD - 0.05, 0.45, 0, width - 3.0, 3.6, PALETTE.steel, PALETTE.darkGlass);
  // Sliding automatic glass entrance door
  b.pane(halfD + 0.02, 0.45, 0, 2.8, 2.8, PALETTE.chrome, PALETTE.glazing);
  // Warm interior lobby reception counter & lighting
  b.box(halfD - 2.5, 0.45, 0, 1.2, 3.2, 1.1, PALETTE.warmWood);
  b.box(halfD - 2.5, 1.55, 0, 0.1, 2.8, 0.4, PALETTE.warmGlow, 1);
  // Entrance steel & glass canopy
  b.commAwning(halfD + 1.2, 4.0, 0, 2.4, 6.5, 0.20, PALETTE.steel);
  for (const pz of [-2.8, 2.8]) {
    b.box(halfD + 2.2, 0.25, pz, 0.18, 0.18, 3.75, PALETTE.chrome);
  }

  // 3. Floors 2-5 Modern Curtain Wall (y = 4.25 to 17.0, height 12.75m)
  b.box(0, 4.25, 0, depth, width, 12.75, PALETTE.steel);
  for (let fl = 1; fl <= 4; fl++) {
    const fy = 4.25 + fl * 3.1;
    b.box(0, fy - 0.35, 0, depth + 0.15, width + 0.15, 0.45, PALETTE.warmWhite);
  }
  b.commWindowBand(0, 4.35, 0, depth, width, 4, 5, PALETTE.steel, PALETTE.glazing);

  // 4. Rooftop (y = 17.0)
  b.box(0, 17.0, 0, depth + 0.1, width + 0.1, 1.1, PALETTE.concrete);
  b.box(0, 17.0, 0, depth - 0.8, width - 0.8, 1.2, PALETTE.roof);
  // Elevator penthouse / mechanical room
  b.box(-2.5, 17.0, 2.5, 5.5, 6.0, 3.2, PALETTE.warmWhite);
  b.box(-2.5, 20.2, 2.5, 5.8, 6.3, 0.35, PALETTE.steel);
  // Rooftop cooling tower
  b.box(3.2, 17.0, 3.5, 2.4, 2.4, 1.6, PALETTE.steel);
  b.cylinder(3.2, 18.6, 3.5, 0.85, 0.45, PALETTE.concrete, 10);
  // Stainless steel water tank
  b.waterTank(-3.0, 17.0, -3.5, 1.1, 1.5);
  // Communications tower antenna
  b.cylinder(0, 17.0, 0, 0.12, 6.5, PALETTE.steel, 6);
  b.cylinder(0, 23.5, 0, 0.25, 0.25, PALETTE.trainYellow, 6);

  return b;
}

function buildYellowCafe() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 11, 14, 5.2, PALETTE.warmWhite);
  b.box(0, 0, 0, 11.4, 14.4, 0.35, PALETTE.darkRoof);
  b.gable(0, 5.2, 0, 11.5, 14.5, 3.2, PALETTE.templeRoof);

  b.pane(5.55, 0.45, 2.5, 4.6, 2.8, PALETTE.darkWood, PALETTE.warmGlow);
  b.pane(5.55, 0.45, -2.5, 3.2, 2.8, PALETTE.darkWood, PALETTE.warmGlow);

  b.box(7.0, 0, 0, 2.8, 13.0, 0.15, PALETTE.warmWood);
  b.cylinder(7.0, 0.15, -3.5, 0.65, 0.72, PALETTE.warmWood, 10);
  for (const sz of [-4.2, -2.8]) {
    b.cylinder(7.0, 0.15, sz, 0.24, 0.45, PALETTE.darkWood, 8);
  }

  b.commAwning(6.4, 3.8, 0, 2.0, 12.0, 0.35, PALETTE.trainYellow);
  for (const pz of [-5.5, 5.5]) {
    b.box(7.3, 0.15, pz, 0.2, 0.2, 3.65, PALETTE.darkWood);
  }

  b.box(2.0, 5.8, 0, 2.2, 2.6, 1.8, PALETTE.warmWhite);
  b.gable(2.0, 7.6, 0, 2.4, 2.8, 0.95, PALETTE.templeRoof);
  b.pane(3.15, 6.1, 0, 1.6, 1.2, PALETTE.darkWood, PALETTE.glazing);
  b.box(3.2, 5.9, 0, 0.35, 1.8, 0.25, PALETTE.greens[1]);
  return b;
}

function buildGasStation() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 16, 24, 0.20, PALETTE.roadMajor);
  b.box(0, 5.2, 0, 15.5, 23.5, 0.65, PALETTE.pureWhite);
  b.box(0, 5.3, 0, 15.7, 23.7, 0.25, PALETTE.commBlue);

  for (const sx of [-4.5, 4.5]) {
    for (const sz of [-6.0, 6.0]) {
      b.cylinder(sx, 0.20, sz, 0.38, 5.0, PALETTE.steel, 10);
      b.box(sx, 0.20, sz, 0.95, 0.95, 0.45, PALETTE.tankStand);
    }
  }

  for (const pz of [-6.0, 6.0]) {
    b.box(0, 0.20, pz, 8.5, 1.6, 0.25, PALETTE.concrete);
    for (const px of [-2.5, 2.5]) {
      b.box(px, 0.45, pz, 1.2, 0.65, 1.8, PALETTE.commBlue);
      b.box(px, 1.45, pz, 1.22, 0.67, 0.45, PALETTE.pureWhite);
      b.box(px, 1.55, pz, 1.24, 0.69, 0.25, PALETTE.commYellow, 1);
      b.box(px, 0.45, pz - 0.38, 0.12, 0.12, 1.2, PALETTE.darkRoof);
      b.box(px, 0.45, pz + 0.38, 0.12, 0.12, 1.2, PALETTE.darkRoof);
    }
  }

  b.box(-9.5, 0, 0, 6.0, 9.0, 3.8, PALETTE.warmWhite);
  b.box(-9.5, 0, 0, 6.2, 9.2, 0.20, PALETTE.darkRoof);
  b.pane(-6.45, 0.25, 0, 7.5, 2.8, PALETTE.steel, PALETTE.glazing);
  b.box(-9.5, 3.8, 0, 6.4, 9.4, 0.35, PALETTE.commBlue);
  return b;
}

function buildParkingGarage() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 18, 22, 0.35, PALETTE.roadMajor);
  for (let fl = 0; fl < 4; fl++) {
    const fy = 0.35 + fl * 3.2;
    b.box(0, fy, 0, 17.5, 21.5, 0.35, PALETTE.concrete);
    for (const sx of [-8.0, 8.0]) {
      b.box(sx, fy + 0.35, 0, 0.25, 21.0, 1.05, PALETTE.tankStand);
    }
    for (const sz of [-10.0, 10.0]) {
      b.box(0, fy + 0.35, sz, 17.0, 0.25, 1.05, PALETTE.tankStand);
    }
    for (const cx of [-6.0, 0, 6.0]) {
      for (const cz of [-8.0, 0, 8.0]) {
        b.box(cx, fy + 0.35, cz, 0.65, 0.65, 2.85, PALETTE.concrete);
      }
    }
  }
  b.box(9.2, 0.35, 0, 0.95, 3.2, 2.5, PALETTE.trainYellow);
  b.box(9.6, 2.8, 0, 0.15, 3.8, 0.15, PALETTE.commRed);
  return b;
}

function buildCommercialHotel() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 16, 18, 14, PALETTE.warmWhite);
  b.box(0, 0, 0, 16.4, 18.4, 0.45, PALETTE.darkRoof);

  b.pane(8.05, 0.45, 0, 12.0, 3.2, PALETTE.steel, PALETTE.glazing);
  b.commAwning(9.4, 3.8, 0, 2.6, 7.5, 0.20, PALETTE.playerRim);
  for (const pz of [-3.2, 3.2]) {
    b.box(10.5, 0.45, pz, 0.25, 0.25, 3.35, PALETTE.chrome);
  }

  b.commWindowBand(0, 4.2, 0, 16, 18, 3, 5, PALETTE.darkRoof, PALETTE.glazing);
  b.box(0, 14.0, 0, 16.6, 18.6, 0.45, PALETTE.concrete);
  b.box(0, 14.45, 0, 16.0, 18.0, 0.65, PALETTE.roof);
  b.box(6.2, 14.45, 0, 0.35, 6.5, 1.8, PALETTE.steel);
  b.box(6.4, 14.65, 0, 0.05, 6.0, 1.4, PALETTE.commCyan, 1);
  return b;
}

function buildBankBranch() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 14, 16, 7.2, PALETTE.warmWhite);
  b.box(0, 0, 0, 14.5, 16.5, 0.35, PALETTE.darkRoof);
  b.box(7.3, 0, 0, 2.2, 14.0, 0.75, PALETTE.concrete);

  for (const pz of [-5.5, -2.8, 0, 2.8, 5.5]) {
    b.cylinder(7.4, 0.75, pz, 0.42, 5.6, PALETTE.warmWhite, 12);
  }

  b.box(7.4, 6.35, 0, 1.4, 15.0, 0.85, PALETTE.warmWhite);
  b.gable(7.4, 7.2, 0, 1.4, 15.0, 1.8, PALETTE.warmWhite);
  b.pane(7.05, 0.75, 0, 3.5, 3.2, PALETTE.warmWood, PALETTE.darkGlass);
  b.pane(7.05, 0.75, -4.0, 2.4, 3.2, PALETTE.steel, PALETTE.glazing);
  b.box(7.1, 1.8, -4.0, 0.1, 1.8, 0.8, PALETTE.warmGlow, 1);
  return b;
}

function buildStackedShopHouse() {
  const b = new MeshBuilder();
  // 1F Traditional Taiwanese shophouse arcade
  b.box(0, 0, 0, 12, 7.5, 4.2, PALETTE.warmWhite);
  b.box(0, 0, 0, 12.3, 7.8, 0.35, PALETTE.darkRoof);
  b.pane(6.05, 0.45, 0, 5.5, 3.2, PALETTE.steel, PALETTE.glazing);
  b.box(6.08, 0.45, -2.4, 0.05, 0.85, 3.2, PALETTE.steel);

  // 2F-3F Residence with cantilevered balconies and security grilles
  b.box(0, 4.2, 0, 12, 7.5, 6.4, PALETTE.tileWhite);
  b.box(6.4, 4.2, 0, 1.0, 7.0, 0.35, PALETTE.concrete);
  b.box(6.85, 4.55, 0, 0.1, 7.0, 1.05, PALETTE.steel);
  b.box(6.4, 7.4, 0, 1.0, 7.0, 0.35, PALETTE.concrete);
  b.box(6.85, 7.75, 0, 0.1, 7.0, 1.05, PALETTE.steel);

  b.pane(6.05, 4.55, 0, 5.0, 2.2, PALETTE.playerRim, PALETTE.darkGlass);
  b.pane(6.05, 7.75, 0, 5.0, 2.2, PALETTE.playerRim, PALETTE.darkGlass);
  b.airConditionerUnit(5.8, 5.0, 2.8, 0.85, 0.35, 0.65);

  // 4F Green sheet metal rooftop addition (鐵皮加蓋) with water tank
  b.box(0, 10.6, 0, 11.2, 7.0, 3.2, PALETTE.tatungGreen);
  b.gable(0, 13.8, 0, 11.5, 7.4, 1.2, PALETTE.tatungGreen);
  b.waterTank(-3.2, 10.6, -1.8, 0.85, 1.3);
  return b;
}

function buildWarehouseStore() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 20, 26, 7.5, PALETTE.steel);
  b.box(0, 0, 0, 20.4, 26.4, 0.45, PALETTE.concrete);
  b.box(10.05, 5.5, 0, 0.25, 25.0, 1.6, PALETTE.commBlue);
  b.box(10.2, 5.8, 0, 0.08, 22.0, 0.9, PALETTE.commYellow, 1);

  for (const pz of [-7.5, -2.5, 2.5, 7.5]) {
    b.box(10.05, 0.45, pz, 0.20, 3.5, 4.2, PALETTE.darkRoof);
    for (let i = 0; i < 8; i++) {
      b.box(10.16, 0.55 + i * 0.45, pz, 0.04, 3.3, 0.35, PALETTE.chrome);
    }
  }

  b.box(0, 7.5, 0, 20.5, 26.5, 0.45, PALETTE.darkRoof);
  b.airConditionerUnit(-4.0, 7.95, -6.0, 2.4, 1.4, 1.6);
  b.airConditionerUnit(-4.0, 7.95, 6.0, 2.4, 1.4, 1.6);
  return b;
}

function buildMetroEntrance() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 14, 9, 0.35, PALETTE.roadMajor);
  b.box(0, 0.35, 0, 13.5, 8.5, 0.35, PALETTE.plaza);

  // Metro station pit & descent stairs
  b.box(0, 0.1, 0, 11.0, 6.0, 0.65, PALETTE.darkRoof);
  b.stairs(1.5, 0.1, 0, 7.0, 4.8, -2.5);

  // Modern curved steel & glass entrance canopy
  b.commAwning(0, 0.70, 0, 12.0, 7.2, 3.5, PALETTE.glazing);
  for (const cx of [-5.2, 0, 5.2]) {
    for (const cz of [-3.4, 3.4]) {
      b.box(cx, 0.70, cz, 0.25, 0.25, 3.2, PALETTE.steel);
    }
  }

  // Metro Totem Pole Sign
  b.box(6.2, 0.70, 3.6, 0.45, 0.45, 4.5, PALETTE.playerRim);
  b.box(6.2, 4.8, 3.6, 0.65, 0.65, 0.65, PALETTE.commMint, 1);
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

  // Back wall and menu lightbox
  b.box(-1.3, 0, 0, 0.25, 4.8, 3.4, PALETTE.tileWhite);
  b.box(-1.15, 1.8, 0, 0.05, 4.2, 1.2, PALETTE.darkRoof);
  b.box(-1.12, 1.9, 0, 0.02, 3.9, 1.0, PALETTE.warmGlow, 1);

  // Two sturdy front steel support posts connecting ground to awning
  for (const sz of [-2.3, 2.3]) {
    b.cylinder(1.7, 0, sz, 0.05, 3.1, PALETTE.steel, 8);
  }

  b.stripedAwning(0.6, 3.1, 0, 2.8, 5.0, 0.45, PALETTE.commMint, PALETTE.warmWhite, 6);
  return b;
}

function buildBentoShop() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 2.6, 4.6, 1.0, PALETTE.steel);

  // Hot steam table buffet case with sneeze guard glass
  b.box(0.25, 1.0, 0, 1.4, 4.2, 0.55, PALETTE.glazing);
  const bentoDishes = [PALETTE.counters1, PALETTE.commRed, PALETTE.trainYellow, PALETTE.greens[2], PALETTE.counters0];
  for (let i = 0; i < 5; i++) {
    const pz = -1.4 + i * 0.7;
    b.box(0.25, 1.02, pz, 0.85, 0.55, 0.12, bentoDishes[i]);
  }

  // Traditional Tatung rice cooker (大同電鍋)
  b.cylinder(-0.6, 1.0, -1.5, 0.32, 0.45, PALETTE.tatungGreen, 10);
  b.cylinder(-0.6, 1.45, -1.5, 0.30, 0.15, PALETTE.steel, 8);
  // Stainless steel soup cauldron
  b.cylinder(-0.6, 1.0, 1.4, 0.38, 0.55, PALETTE.steel, 10);
  b.cylinder(-0.6, 1.55, 1.4, 0.35, 0.08, PALETTE.warmWood, 8);

  // Bento box stack
  b.box(-0.6, 1.0, 0, 0.45, 0.65, 0.55, PALETTE.warmWhite);

  // 4 Corner structural steel poles connecting counter to overhead sign & awning
  for (const px of [-1.15, 1.15]) {
    for (const pz of [-2.1, 2.1]) {
      b.box(px, 1.0, pz, 0.06, 0.06, 1.70, PALETTE.steel);
    }
  }

  // Overhead illuminated signboard & canopy
  b.box(1.20, 2.60, 0, 0.12, 4.6, 0.85, PALETTE.commRed);
  b.box(1.28, 2.65, 0, 0.02, 4.2, 0.65, PALETTE.trainYellow, 1);
  b.stripedAwning(0.6, 2.70, 0, 2.4, 4.8, 0.35, PALETTE.commRed, PALETTE.warmWhite, 6);

  // Outdoor dining bench table and stools
  b.box(2.8, 0, 0, 1.2, 2.2, 0.75, PALETTE.steel);
  for (const sz of [-1.4, 1.4]) {
    b.cylinder(2.8, 0, sz, 0.22, 0.45, PALETTE.commRed, 8);
  }
  return b;
}

function buildBakery() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 3.4, 5.0, 3.6, PALETTE.warmWhite);
  b.box(0, 0, 0, 3.6, 5.2, 0.25, PALETTE.darkRoof);
  b.box(0, 3.6, 0, 3.6, 5.2, 0.35, PALETTE.counters1);

  b.pane(1.75, 0.45, 0, 4.4, 2.4, PALETTE.darkWood, PALETTE.glazing);
  b.box(1.3, 0.65, 0, 0.65, 4.0, 0.85, PALETTE.warmWood);
  for (let i = 0; i < 4; i++) {
    b.box(1.3, 1.52, -1.4 + i * 0.9, 0.45, 0.65, 0.25, PALETTE.counters0);
  }

  b.box(1.85, 2.9, 0, 0.15, 4.6, 0.65, PALETTE.commCrimson);
  b.box(1.93, 2.95, 0, 0.02, 4.2, 0.50, PALETTE.warmWhite, 1);
  b.commAwning(2.3, 2.85, 0, 1.6, 4.8, 0.30, PALETTE.commCrimson);
  return b;
}

function buildPharmacy() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 3.4, 5.2, 3.6, PALETTE.warmWhite);
  b.box(0, 0, 0, 3.6, 5.4, 0.25, PALETTE.concrete);
  b.box(0, 3.6, 0, 3.6, 5.4, 0.35, PALETTE.steel);

  // Taiwan NHI Cyan & Orange Signboard with cross
  b.box(1.75, 2.75, 0, 0.22, 5.2, 0.85, PALETTE.commCyan);
  b.box(1.88, 2.85, 0, 0.04, 4.8, 0.65, PALETTE.pureWhite, 1);
  b.box(1.92, 2.95, -1.8, 0.02, 0.55, 0.55, PALETTE.commMint, 1); // Green Cross

  b.pane(1.75, 0.35, 0, 4.6, 2.3, PALETTE.steel, PALETTE.glazing);
  for (const pz of [-1.6, 1.6]) {
    b.box(2.3, 0, pz, 0.65, 0.95, 0.75, PALETTE.chrome);
  }
  return b;
}

function buildCornerGrocery() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 3.4, 5.2, 3.5, PALETTE.warmWhite);
  b.box(0, 0, 0, 3.6, 5.4, 0.25, PALETTE.concrete);
  b.box(0, 3.5, 0, 3.6, 5.4, 0.30, PALETTE.roof);

  b.stripedAwning(2.2, 2.9, 0, 1.8, 5.4, 0.45, PALETTE.commRed, PALETTE.commMint, 6);
  b.pane(1.75, 0.45, 0, 4.6, 2.2, PALETTE.darkWood, PALETTE.warmGlow);

  // Outdoor fruit & vegetable bins
  for (let i = -1; i <= 1; i++) {
    b.box(2.2, 0, i * 1.3, 0.65, 0.95, 0.65, PALETTE.counters1);
    b.cylinder(2.2, 0.65, i * 1.3, 0.35, 0.15, PALETTE.greens[i + 1], 8);
  }
  // Stacked green Taiwan Beer plastic crates
  b.box(2.2, 0, -2.1, 0.55, 0.75, 0.75, PALETTE.tatungGreen);
  b.box(2.2, 0.75, -2.1, 0.55, 0.75, 0.45, PALETTE.tatungGreen);
  return b;
}

function buildStationeryStore() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 3.2, 4.8, 3.4, PALETTE.warmWhite);
  b.box(0, 0, 0, 3.4, 5.0, 0.25, PALETTE.concrete);
  b.box(0, 3.4, 0, 3.4, 5.0, 0.30, PALETTE.darkRoof);

  b.pane(1.65, 0.45, 0.8, 2.8, 2.4, PALETTE.warmWood, PALETTE.glazing);
  b.box(1.3, 0.65, 0.8, 0.4, 2.4, 0.75, PALETTE.counters1);
  b.box(1.8, 0, -1.4, 0.75, 1.4, 1.1, PALETTE.steel);

  // Revolving sidewalk postcard/magazine stand
  b.cylinder(2.1, 0, 1.8, 0.22, 1.45, PALETTE.steel, 8);
  b.cylinder(2.1, 0.6, 1.8, 0.28, 0.75, PALETTE.warmWhite, 8);

  b.box(1.75, 2.85, 0, 0.12, 4.6, 0.55, PALETTE.commBlue);
  b.box(1.82, 2.90, 0, 0.02, 4.2, 0.42, PALETTE.trainYellow, 1);
  return b;
}

function buildRamenYatai() {
  const b = new MeshBuilder();
  // Timber mobile ramen yatai cart
  b.box(0, 0.45, 0, 2.2, 3.6, 0.65, PALETTE.darkWood);
  b.wheelZ(0, 0.45, -1.9, 0.45, 0.12, PALETTE.darkWood, PALETTE.steel, 10);
  b.wheelZ(0, 0.45, 1.9, 0.45, 0.12, PALETTE.darkWood, PALETTE.steel, 10);
  b.cylinderZ(0, 0.45, 0, 0.05, 3.8, PALETTE.steel, 6);

  // Noodle prep counter and steaming broth cauldron
  b.box(0.2, 1.1, 0, 1.4, 3.4, 0.10, PALETTE.warmWood);
  b.cylinder(0.2, 1.2, -0.9, 0.38, 0.45, PALETTE.steel, 10);
  b.cylinder(0.2, 1.65, -0.9, 0.35, 0.05, PALETTE.pureWhite, 8); // broth steam
  b.cylinder(0.2, 1.2, 0.9, 0.32, 0.35, PALETTE.steel, 8);

  // 4 Timber roof posts
  for (const sx of [-0.9, 0.9]) {
    for (const sz of [-1.6, 1.6]) {
      b.box(sx, 1.1, sz, 0.08, 0.08, 1.5, PALETTE.darkWood);
    }
  }

  // Traditional wooden tiled pitched gable roof
  b.gable(0, 2.6, 0, 2.6, 4.0, 0.65, PALETTE.playerRoof);

  // Red paper lanterns hanging from timber eaves
  b.lantern(1.1, 2.2, -1.2, 0.22, 0.45, PALETTE.commRed);
  b.lantern(1.1, 2.2, 1.2, 0.22, 0.45, PALETTE.commRed);

  // 4 Round customer bar stools
  for (let i = 0; i < 4; i++) {
    b.cylinder(1.7, 0, -1.35 + i * 0.9, 0.18, 0.48, PALETTE.darkWood, 8);
  }
  return b;
}

function buildNightMarketFryer() {
  const b = new MeshBuilder();
  b.box(0, 0.20, 0, 2.4, 4.2, 0.75, PALETTE.steel);
  for (const lx of [-0.9, 0.9]) {
    for (const lz of [-1.8, 1.8]) {
      b.box(lx, 0, lz, 0.10, 0.10, 0.20, PALETTE.steel);
      b.cylinder(lx, 0.06, lz, 0.06, 0.04, PALETTE.playerRim, 8);
    }
  }

  // Food showcase counter: glass sneeze guard & stainless steel trays
  b.box(0.25, 0.95, 0, 1.3, 3.8, 0.85, PALETTE.glazing);
  for (let i = 0; i < 5; i++) {
    const pz = -1.4 + i * 0.7;
    const foodC = i % 2 === 0 ? PALETTE.counters1 : PALETTE.teaAmber;
    b.box(0.25, 1.0, pz, 0.85, 0.55, 0.14, foodC);
  }

  // Deep fryer vat with hot oil and wire mesh basket
  b.box(-0.6, 0.95, -1.2, 0.95, 1.2, 0.55, PALETTE.steel);
  b.box(-0.6, 1.50, -1.2, 0.75, 1.0, 0.05, PALETTE.teaAmber);
  b.box(-0.6, 1.55, -1.2, 0.45, 0.65, 0.18, PALETTE.chrome);

  // Overhead stainless steel exhaust hood & ventilation chimney pipe
  b.box(-0.6, 2.10, -1.2, 1.1, 1.4, 0.45, PALETTE.steel);
  b.cylinder(-0.6, 2.55, -1.2, 0.16, 0.95, PALETTE.steel, 8);

  // Seasoning shaker cans
  b.cylinder(0.5, 0.95, 1.3, 0.08, 0.25, PALETTE.chrome, 6);
  b.cylinder(0.5, 0.95, 1.6, 0.08, 0.25, PALETTE.commRed, 6);

  // 4 Corner support poles connecting counter to overhead sign & canopy
  for (const px of [-0.95, 0.95]) {
    for (const pz of [-1.9, 1.9]) {
      b.box(px, 0.95, pz, 0.05, 0.05, 1.65, PALETTE.steel);
    }
  }

  // Overhead illuminated yellow & red signboard & roof
  b.box(1.05, 2.60, 0, 0.12, 4.0, 0.85, PALETTE.commYellow);
  b.box(1.12, 2.65, 0, 0.02, 3.7, 0.65, PALETTE.commRed, 1);
  b.box(0, 2.60, 0, 2.5, 4.3, 0.12, PALETTE.commCrimson);
  return b;
}

function buildNightMarketFruit() {
  const b = new MeshBuilder();
  b.box(0, 0.20, 0, 2.4, 4.0, 0.75, PALETTE.steel);
  for (const lx of [-0.9, 0.9]) {
    for (const lz of [-1.7, 1.7]) {
      b.box(lx, 0, lz, 0.10, 0.10, 0.20, PALETTE.steel);
      b.cylinder(lx, 0.06, lz, 0.06, 0.04, PALETTE.playerRim, 8);
    }
  }

  b.box(0.25, 0.95, 0, 1.3, 3.6, 0.85, PALETTE.glazing);
  b.box(0.25, 0.98, 0, 1.1, 3.4, 0.10, PALETTE.pureWhite); // crushed ice bed

  const fruitColors = [PALETTE.commRed, PALETTE.commMint, PALETTE.commYellow, PALETTE.commOrange];
  for (let i = 0; i < 4; i++) {
    const pz = -1.2 + i * 0.8;
    b.box(0.25, 1.08, pz, 0.75, 0.65, 0.22, fruitColors[i]);
  }

  b.cylinder(-0.6, 0.95, 1.2, 0.18, 0.55, PALETTE.glazing, 8);
  b.box(-0.6, 0.95, 1.2, 0.45, 0.45, 0.25, PALETTE.steel);

  for (const px of [-0.95, 0.95]) {
    for (const pz of [-1.8, 1.8]) {
      b.box(px, 0.95, pz, 0.05, 0.05, 1.65, PALETTE.steel);
    }
  }

  b.box(1.05, 2.60, 0, 0.12, 3.8, 0.85, PALETTE.commMint);
  b.box(1.12, 2.65, 0, 0.02, 3.4, 0.65, PALETTE.warmWhite, 1);
  b.box(0, 2.60, 0, 2.5, 4.1, 0.12, PALETTE.commMint);
  return b;
}

function buildNightMarketGame() {
  const b = new MeshBuilder();
  b.box(0, 0.65, 0, 2.6, 3.6, 0.20, PALETTE.warmWood);
  for (const lx of [-1.1, 1.1]) {
    for (const lz of [-1.6, 1.6]) {
      b.box(lx, 0, lz, 0.12, 0.12, 0.65, PALETTE.warmWood);
    }
  }

  b.commAwning(0.2, 0.85, 0, 1.6, 3.2, 0.45, PALETTE.trainYellow);
  for (let i = 0; i < 6; i++) {
    b.cylinder(0.2, 1.15, -1.2 + i * 0.48, 0.04, 0.08, PALETTE.chrome, 6);
  }

  for (const px of [-1.1, 1.1]) {
    for (const pz of [-1.6, 1.6]) {
      b.box(px, 0.85, pz, 0.08, 0.08, 2.15, PALETTE.warmWood);
    }
  }

  b.box(-0.95, 1.6, 0, 0.35, 3.4, 1.4, PALETTE.warmWood);
  for (let i = 0; i < 3; i++) {
    b.cylinder(-0.75, 2.0, -1.0 + i * 1.0, 0.22, 0.35, PALETTE.flowers[i], 8);
  }

  b.stripedAwning(0, 3.0, 0, 2.8, 3.8, 0.35, PALETTE.commBlue, PALETTE.warmWhite, 6);
  for (const sz of [-0.9, 0.9]) {
    b.cylinder(1.7, 0, sz, 0.20, 0.45, PALETTE.commBlue, 8);
    b.cylinder(1.7, 0.45, sz, 0.24, 0.05, PALETTE.warmWood, 8);
  }
  return b;
}

function buildVendingBank() {
  const b = new MeshBuilder();
  const colors = [PALETTE.commBlue, PALETTE.counters1, PALETTE.commRed];
  for (let i = 0; i < 3; i++) {
    const pz = -1.5 + i * 1.5;
    b.box(0, 0, pz, 1.1, 1.25, 2.4, colors[i]);
    b.box(0.55, 0.4, pz, 0.05, 1.05, 1.2, PALETTE.darkGlass);
    b.box(0.57, 0.45, pz, 0.02, 0.95, 1.1, PALETTE.warmGlow, 1);
    b.box(0.55, 0.15, pz, 0.06, 0.75, 0.22, PALETTE.darkRoof);
  }
  b.box(0, 0, 2.8, 0.85, 0.85, 1.2, PALETTE.commMint);
  b.cylinder(0, 1.2, 2.8, 0.16, 0.04, PALETTE.darkRoof, 8);
  return b;
}

function buildMobileFoodCart() {
  const b = new MeshBuilder();
  b.box(0, 0.35, 0, 2.4, 1.4, 0.75, PALETTE.warmWood);
  // Three wheels with connecting axles
  b.wheelZ(-1.0, 0.38, 0, 0.38, 0.10, PALETTE.darkRoof, PALETTE.chrome, 10);
  b.wheelZ(0.8, 0.38, -0.75, 0.38, 0.10, PALETTE.darkRoof, PALETTE.chrome, 10);
  b.wheelZ(0.8, 0.38, 0.75, 0.38, 0.10, PALETTE.darkRoof, PALETTE.chrome, 10);
  b.cylinderZ(0.8, 0.38, 0, 0.04, 1.5, PALETTE.steel, 6);
  b.cylinderZ(-1.0, 0.38, 0, 0.04, 0.4, PALETTE.steel, 6);

  // Steamer cauldron and cooking counter
  b.box(0.2, 1.1, 0, 1.4, 1.3, 0.10, PALETTE.steel);
  b.cylinder(0.2, 1.2, 0, 0.35, 0.45, PALETTE.steel, 10);

  // 4 Canopy support posts
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
  b.box(0, 1.8, 0, 0.18, 0.45, 4.2, PALETTE.tankStand);
  for (const by of [0.4, 2.0, 3.8]) {
    b.beam([0, by, 0], [0.8, by, 0], 0.05, PALETTE.steel);
  }
  const colors = [PALETTE.commRed, PALETTE.commCyan, PALETTE.commYellow];
  for (let i = 0; i < 3; i++) {
    const sy = 0.5 + i * 1.35;
    b.box(0.9, sy, 0, 0.22, 0.85, 1.2, colors[i]);
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
  const width = 0.65, height = 1.05;
  const spread = 0.28;

  // Four wooden legs extending to ground (y = 0)
  for (const lx of [-spread, spread]) {
    for (const lz of [-width / 2 + 0.04, width / 2 - 0.04]) {
      b.box(lx, 0, lz, 0.05, 0.05, 0.18, PALETTE.warmWood);
    }
  }

  // Front slanted board
  const pF1 = [spread, 0.15, -width / 2];
  const pF2 = [spread, 0.15, width / 2];
  const pF3 = [0, height, width / 2];
  const pF4 = [0, height, -width / 2];
  b.addQuadBuilder(pF1, pF2, pF3, pF4, PALETTE.warmWood);
  b.addQuadBuilder(
    [pF4[0] - 0.03, pF4[1], pF4[2]],
    [pF3[0] - 0.03, pF3[1], pF3[2]],
    [pF2[0] - 0.03, pF2[1], pF2[2]],
    [pF1[0] - 0.03, pF1[1], pF1[2]],
    PALETTE.warmWood
  );

  // Back slanted board
  const pB1 = [-spread, 0.15, width / 2];
  const pB2 = [-spread, 0.15, -width / 2];
  const pB3 = [0, height, -width / 2];
  const pB4 = [0, height, width / 2];
  b.addQuadBuilder(pB1, pB2, pB3, pB4, PALETTE.warmWood);
  b.addQuadBuilder(
    [pB4[0] + 0.03, pB4[1], pB4[2]],
    [pB3[0] + 0.03, pB3[1], pB3[2]],
    [pB2[0] + 0.03, pB2[1], pB2[2]],
    [pB1[0] + 0.03, pB1[1], pB1[2]],
    PALETTE.warmWood
  );

  b.cylinderZ(0, height, 0, 0.03, width, PALETTE.chrome, 8);

  // Inset chalkboard faces
  const bF1 = [spread - 0.01, 0.22, -width / 2 + 0.06];
  const bF2 = [spread - 0.01, 0.22, width / 2 - 0.06];
  const bF3 = [0.01, height - 0.10, width / 2 - 0.06];
  const bF4 = [0.01, height - 0.10, -width / 2 + 0.06];
  b.addQuadBuilder(bF1, bF2, bF3, bF4, PALETTE.darkRoof);

  const bB1 = [-spread + 0.01, 0.22, width / 2 - 0.06];
  const bB2 = [-spread + 0.01, 0.22, -width / 2 + 0.06];
  const bB3 = [-0.01, height - 0.10, -width / 2 + 0.06];
  const bB4 = [-0.01, height - 0.10, width / 2 - 0.06];
  b.addQuadBuilder(bB1, bB2, bB3, bB4, PALETTE.darkRoof);

  b.box(spread * 0.55 + 0.01, 0.55, 0, 0.01, 0.36, 0.40, PALETTE.trainYellow, 1);
  b.box(-spread * 0.55 - 0.01, 0.55, 0, 0.01, 0.36, 0.40, PALETTE.warmGlow, 1);

  b.beam([-spread * 0.65, 0.40, -width / 2 + 0.05], [spread * 0.65, 0.40, -width / 2 + 0.05], 0.02, PALETTE.steel);
  b.beam([-spread * 0.65, 0.40, width / 2 - 0.05], [spread * 0.65, 0.40, width / 2 - 0.05], 0.02, PALETTE.steel);
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

  // 4 Realistic cafe chairs with 4 legs, seat and curved backrest
  for (let i = 0; i < 4; i++) {
    const a = (i * 2 * Math.PI) / 4.0;
    const cx = Math.cos(a) * 1.15, cz = Math.sin(a) * 1.15;
    b.box(cx, 0.42, cz, 0.45, 0.45, 0.06, PALETTE.warmWood);
    for (const lx of [-0.18, 0.18]) {
      for (const lz of [-0.18, 0.18]) {
        b.cylinder(cx + lx, 0, cz + lz, 0.02, 0.42, PALETTE.steel, 6);
      }
    }
    // Backrest
    b.box(cx + Math.cos(a) * 0.18, 0.48, cz + Math.sin(a) * 0.18, 0.05, 0.42, 0.38, PALETTE.steel);
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
  const height = 3.8;
  const colR = 0.06;

  // 1. Four vertical steel support columns from ground (y = 0) to upper landing
  for (const cx of [0.1, 2.3]) {
    for (const cz of [-0.75, 0.75]) {
      b.cylinder(cx, 0, cz, colR, height, PALETTE.steel, 8);
    }
  }

  // 2. Wall mounting anchor brackets
  for (const wy of [0.5, 1.8, 3.6]) {
    for (const wz of [-0.75, 0.75]) {
      b.box(0.05, wy, wz, 0.25, 0.12, 0.12, PALETTE.tankStand);
    }
  }

  // 3. Lower landing at 1F (y = 1.8)
  b.box(1.2, 1.8, 0, 2.2, 1.5, 0.10, PALETTE.steel);
  b.box(2.28, 1.9, 0, 0.04, 1.5, 0.95, PALETTE.steel);
  b.box(1.2, 1.9, -0.73, 2.2, 0.04, 0.95, PALETTE.steel);

  // 4. Upper landing at 2F (y = 3.6)
  b.box(1.2, 3.6, 0, 2.2, 1.5, 0.10, PALETTE.steel);
  b.box(2.28, 3.7, 0, 0.04, 1.5, 0.95, PALETTE.steel);
  b.box(1.2, 3.7, -0.73, 2.2, 0.04, 0.95, PALETTE.steel);
  b.box(1.2, 3.7, 0.73, 2.2, 0.04, 0.95, PALETTE.steel);

  // 5. Flight of stairs from ground to 1F landing
  const steps = 8;
  const runL = 2.0, stairW = 0.65;
  for (let i = 0; i < steps; i++) {
    const t = (i + 0.5) / steps;
    const sy = t * 1.8;
    const sx = 0.2 + t * runL;
    b.box(sx, sy, 0.35, runL / steps + 0.02, stairW, 0.08, PALETTE.steel);
  }
  b.beam([0.2, 0.1, 0.70], [2.2, 1.8, 0.70], 0.05, PALETTE.steel);
  b.beam([0.2, 0.95, 0.70], [2.2, 2.65, 0.70], 0.04, PALETTE.steel);

  // 6. Flight of stairs from 1F landing to 2F landing
  for (let i = 0; i < steps; i++) {
    const t = (i + 0.5) / steps;
    const sy = 1.8 + t * 1.8;
    const sx = 2.2 - t * runL;
    b.box(sx, sy, -0.35, runL / steps + 0.02, stairW, 0.08, PALETTE.steel);
  }
  b.beam([2.2, 1.9, -0.70], [0.2, 3.6, -0.70], 0.05, PALETTE.steel);
  b.beam([2.2, 2.75, -0.70], [0.2, 4.45, -0.70], 0.04, PALETTE.steel);

  return b;
}

function buildTransitFeederBus() {
  const b = new MeshBuilder();
  const length = 10.4, width = 2.5, wheelR = 0.48;
  const halfL = length / 2, halfW = width / 2;

  // 1. Lower chassis underside box (y = 0.22 to 0.75)
  b.box(0, 0.22, 0, length - 0.2, width - 0.12, 0.53, PALETTE.playerRoof);

  // 2. White lower body / skirt panels
  b.box(4.35, 0.22, 0, 1.7, width, 0.56, PALETTE.pureWhite);
  b.box(0, 0.22, 0, 4.6, width, 0.56, PALETTE.pureWhite);
  b.box(-4.35, 0.22, 0, 1.7, width, 0.56, PALETTE.pureWhite);
  // Amber side marker lights
  for (const mx of [-4.2, -1.2, 1.2, 4.2]) {
    for (const sign of [-1, 1]) {
      b.box(mx, 0.36, sign * (halfW + 0.01), 0.12, 0.02, 0.05, PALETTE.commOrange);
    }
  }

  // 3. Green waist ribbon
  b.box(0, 0.78, 0, length, width, 0.40, PALETTE.commBusGreen);

  // 4. Panoramic dark-tinted window band
  b.box(0, 1.18, 0, length, width - 0.04, 1.20, PALETTE.darkGlass);
  for (let i = -3; i <= 3; i++) {
    b.box(i * 1.35, 1.18, halfW, 0.10, 0.05, 1.20, PALETTE.playerRim);
  }
  b.box(3.2, 1.78, halfW + 0.01, 1.4, 0.03, 0.06, PALETTE.steel);

  // 5. Passenger side doors (on right side, z = -halfW)
  for (const dx of [3.3, -0.6]) {
    b.box(dx, 0.28, -halfW, 1.24, 0.08, 2.08, PALETTE.playerRim);
    b.box(dx - 0.30, 0.32, -halfW - 0.01, 0.56, 0.04, 1.98, PALETTE.darkGlass);
    b.box(dx + 0.30, 0.32, -halfW - 0.01, 0.56, 0.04, 1.98, PALETTE.darkGlass);
    b.box(dx, 0.32, -halfW - 0.015, 0.04, 0.05, 1.98, PALETTE.playerRim);
    b.cylinder(dx, 0.35, -halfW + 0.22, 0.025, 1.9, PALETTE.trainYellow, 6);
  }
  for (const px of [1.35, -2.4, -3.8]) {
    b.box(px, 1.18, -halfW, 0.10, 0.05, 1.20, PALETTE.playerRim);
  }

  // 6. Upper roof body
  b.box(0, 2.38, 0, length, width, 0.24, PALETTE.pureWhite);

  // 7. Aerodynamic green roof fairing / battery & AC pod
  b.box(1.1, 2.62, 0, 6.2, width - 0.35, 0.42, PALETTE.commBusGreen);
  b.commAwning(4.45, 2.62, 0, 0.8, width - 0.35, 0.40, PALETTE.commBusGreen);
  b.box(0.5, 3.05, 0, 3.8, width - 0.65, 0.04, PALETTE.playerRoof);
  for (let i = -3; i <= 3; i++) {
    b.box(0.5 + i * 0.45, 3.09, 0, 0.12, width - 0.85, 0.02, PALETTE.darkRoof);
  }

  // 8. Front aerodynamic nose & windshield
  b.box(halfL + 0.08, 0.22, 0, 0.26, width - 0.1, 0.56, PALETTE.pureWhite);
  b.box(halfL + 0.22, 0.28, 0, 0.02, 0.52, 0.18, PALETTE.pureWhite);
  for (const sign of [-1, 1]) {
    const hy = 0.50, hz = sign * (halfW - 0.35);
    b.box(halfL + 0.21, hy, hz, 0.03, 0.38, 0.18, PALETTE.darkRoof);
    b.cylinder(halfL + 0.22, hy, hz - sign * 0.08, 0.065, 0.03, PALETTE.pureWhite, 8);
    b.cylinder(halfL + 0.22, hy, hz + sign * 0.08, 0.045, 0.03, PALETTE.commYellow, 8);
  }
  b.box(halfL + 0.08, 0.78, 0, 0.18, width - 0.1, 0.40, PALETTE.playerRim);
  b.pane(halfL + 0.06, 1.18, 0, width - 0.25, 1.18, PALETTE.playerRim, PALETTE.darkGlass);
  b.box(halfL + 0.08, 2.38, 0, 0.16, 1.8, 0.22, PALETTE.darkRoof);
  b.box(halfL + 0.17, 2.40, 0, 0.02, 1.65, 0.18, PALETTE.trainYellow, 1);
  for (const sign of [-1, 1]) {
    const mz = sign * (halfW + 0.25);
    b.beam([halfL - 0.2, 2.50, sign * halfW], [halfL + 0.35, 2.25, mz], 0.035, PALETTE.darkRoof);
    b.beam([halfL + 0.35, 2.25, mz], [halfL + 0.35, 1.70, mz], 0.035, PALETTE.darkRoof);
    b.box(halfL + 0.35, 1.70, mz, 0.10, 0.14, 0.42, PALETTE.darkRoof);
    b.box(halfL + 0.29, 1.72, mz, 0.02, 0.11, 0.38, PALETTE.chrome);
  }

  // 9. Rear end
  b.box(-halfL - 0.05, 0.22, 0, 0.15, width - 0.1, 0.56, PALETTE.pureWhite);
  b.box(-halfL - 0.05, 0.78, 0, 0.15, width - 0.1, 0.40, PALETTE.commBusGreen);
  b.paneBack(-halfL - 0.05, 1.35, 0, width - 0.4, 0.95, PALETTE.playerRim, PALETTE.darkGlass);
  for (const sign of [-1, 1]) {
    const rz = sign * (halfW - 0.25);
    b.box(-halfL - 0.06, 0.85, rz, 0.02, 0.16, 0.16, PALETTE.commRed);
    b.box(-halfL - 0.06, 0.65, rz, 0.02, 0.16, 0.14, PALETTE.commYellow);
    b.box(-halfL - 0.06, 0.48, rz, 0.02, 0.16, 0.12, PALETTE.pureWhite);
  }
  b.box(-halfL - 0.06, 0.32, 0, 0.02, 0.52, 0.18, PALETTE.pureWhite);

  // 10. Wheels touching ground at y = 0
  const wheelZOffset = halfW - 0.14;
  b.wheelZ(2.9, wheelR, -wheelZOffset, wheelR, 0.28, PALETTE.darkRoof, PALETTE.steel, 14);
  b.wheelZ(2.9, wheelR, wheelZOffset, wheelR, 0.28, PALETTE.darkRoof, PALETTE.steel, 14);
  b.wheelZ(-2.9, wheelR, -wheelZOffset, wheelR, 0.28, PALETTE.darkRoof, PALETTE.steel, 14);
  b.wheelZ(-2.9, wheelR, wheelZOffset, wheelR, 0.28, PALETTE.darkRoof, PALETTE.steel, 14);
  b.cylinderZ(2.9, wheelR, 0, 0.06, width - 0.4, PALETTE.tankStand, 8);
  b.cylinderZ(-2.9, wheelR, 0, 0.06, width - 0.4, PALETTE.tankStand, 8);

  return b;
}

// -------------------------------------------------------------
// 4 Composite Assemblies
// -------------------------------------------------------------

function buildCommercialAvenue() {
  const b = new MeshBuilder();
  // 1. Asphalt roadway at y = 0, height 0.25
  b.box(0, 0, 0, 36, 44, 0.25, PALETTE.roadMajor);
  // White lane markings on road
  for (let i = -4; i <= 4; i++) {
    b.box(6.0, 0.251, i * 4.5, 0.18, 2.5, 0.01, PALETTE.pureWhite);
  }
  // Pedestrian zebra crossing
  for (let z = -6.0; z <= 6.0; z += 1.2) {
    b.box(6.0, 0.251, z, 3.6, 0.55, 0.01, PALETTE.pureWhite);
  }

  // 2. Sidewalk plaza from y = 0.25, height 0.15 (sidewalk surface at y = 0.40)
  b.box(-7.0, 0.25, 0, 22, 44, 0.15, PALETTE.plaza);

  // 3. Buildings on sidewalk (y = 0.40)
  const deptStore = buildDepartmentStore();
  const cinema = buildCinema();
  const cafe = buildYellowCafe();
  const bus = buildTransitFeederBus();
  const planter = buildCommercialPlanter();
  const banner = buildCommercialBannerPole();

  b.addModelAt(deptStore, -8.0, 0.40, -11.0, 0);
  b.addModelAt(cinema, -8.0, 0.40, 11.0, 0);
  b.addModelAt(cafe, 9.5, 0.40, 11.0, Math.PI);

  // 4. Feeder bus driving on road (y = 0.25)
  b.addModelAt(bus, 6.0, 0.25, -8.0, 0);

  // 5. Street furniture on sidewalk curb
  b.addModelAt(planter, 2.5, 0.40, 4.0, 0);
  b.addModelAt(planter, 2.5, 0.40, -16.0, 0);
  b.addModelAt(banner, 2.8, 0.40, 0, 0);
  b.addModelAt(banner, 2.8, 0.40, -12.0, 0);
  return b;
}

function buildNightMarketAlley() {
  const b = new MeshBuilder();
  // Pedestrian stone market paving at y = 0, height 0.25 (surface at y = 0.25)
  b.box(0, 0, 0, 30, 36, 0.25, PALETTE.roadMinor);
  b.box(0, 0.25, 0, 29, 35, 0.10, PALETTE.plaza);

  const boba = buildBubbleTeaShop();
  const bento = buildBentoShop();
  const fryer = buildNightMarketFryer();
  const ramen = buildRamenYatai();
  const fruit = buildNightMarketFruit();
  const game = buildNightMarketGame();

  // Left side stalls (z = -7.5)
  b.addModelAt(boba, -7.5, 0.35, -7.5, 0);
  b.addModelAt(bento, 0, 0.35, -7.5, 0);
  b.addModelAt(fryer, 7.5, 0.35, -7.5, 0);

  // Right side stalls (z = 7.5, facing opposite)
  b.addModelAt(ramen, -7.5, 0.35, 7.5, Math.PI);
  b.addModelAt(fruit, 0, 0.35, 7.5, Math.PI);
  b.addModelAt(game, 7.5, 0.35, 7.5, Math.PI);

  // Center alley dining tables
  const umbrella = buildCafeUmbrellaSet();
  b.addModelAt(umbrella, -3.5, 0.35, 0, 0);
  b.addModelAt(umbrella, 3.5, 0.35, 0, 0);

  // Overhead market string lanterns crisscrossing the alley
  for (const lx of [-6.0, 0, 6.0]) {
    b.beam([lx, 3.2, -7.0], [lx, 3.2, 7.0], 0.02, PALETTE.darkRoof);
    b.lantern(lx, 2.8, -3.0, 0.20, 0.40, PALETTE.commRed);
    b.lantern(lx, 2.8, 0, 0.20, 0.40, PALETTE.commYellow);
    b.lantern(lx, 2.8, 3.0, 0.20, 0.40, PALETTE.commRed);
  }
  return b;
}

function buildStationTransitHub() {
  const b = new MeshBuilder();
  // Road & bus transit bay at y = 0, height 0.25
  b.box(0, 0, 0, 34, 40, 0.25, PALETTE.roadMajor);
  // Station passenger boarding island at y = 0.25, height 0.15 (surface at y = 0.40)
  b.box(-7.0, 0.25, 0, 20, 40, 0.15, PALETTE.plaza);

  const office = buildCornerOffice();
  const bus = buildTransitFeederBus();
  const totem = buildTotemLightbox();
  const vending = buildVendingBank();
  const planter = buildCommercialPlanter();

  // Corner office on station plaza (y = 0.40)
  b.addModelAt(office, -6.0, 0.40, 9.0, 0);

  // Vending machines on plaza
  b.addModelAt(vending, -6.0, 0.40, -10.0, 0);

  // Feeder bus at boarding transit bay (y = 0.25)
  b.addModelAt(bus, 6.0, 0.25, -4.0, 0);

  // Passenger boarding shelter & directory on plaza curb
  b.addModelAt(totem, 1.5, 0.40, -12.0, 0);
  b.addModelAt(planter, 1.5, 0.40, 2.0, 0);
  b.addModelAt(planter, 1.5, 0.40, -6.0, 0);

  // Transit waiting canopy shelter
  b.box(2.0, 0.40, 8.0, 3.2, 5.5, 0.05, PALETTE.steel);
  b.commAwning(2.0, 2.8, 8.0, 3.5, 6.0, 0.35, PALETTE.commCyan);
  for (const cx of [0.5, 3.5]) {
    for (const cz of [5.5, 10.5]) {
      b.cylinder(cx, 0.40, cz, 0.06, 2.4, PALETTE.steel, 8);
    }
  }
  return b;
}

function buildNeighborhoodRetailCorner() {
  const b = new MeshBuilder();
  b.box(0, 0, 0, 32, 34, 0.25, PALETTE.roadMajor);
  b.box(-6.0, 0.25, 0, 20, 34, 0.15, PALETTE.plaza);

  const shophouse = buildStackedShopHouse();
  const grocery = buildCornerGrocery();
  const bakery = buildBakery();
  const umbrella = buildCafeUmbrellaSet();
  const planter = buildCommercialPlanter();

  b.addModelAt(shophouse, -6.0, 0.40, -8.0, 0);
  b.addModelAt(grocery, -6.0, 0.40, 6.0, 0);
  b.addModelAt(bakery, 6.0, 0.40, 6.0, Math.PI);
  b.addModelAt(umbrella, 5.0, 0.40, -6.0, 0);
  b.addModelAt(planter, 1.5, 0.40, 0, 0);
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
