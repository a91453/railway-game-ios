import {writeFileSync, mkdirSync} from 'node:fs';
import {resolve, dirname} from 'node:path';

// Palette definitions matching Map3DPalette and GamePresentation constants
export const PALETTE = {
  tileWhite: 0xFFF0EBE0,
  concrete: 0xFFD9D4C8,
  tankStand: 0xFF8A939E,
  playerRim: 0xFF262C57,
  trainAccent: 0xFF1D4F91,
  trainYellow: 0xFFFFC86B,
  templeRidge: 0xFFC93D2B,
  templeRoof: 0xFF9E382B,
  canopy: 0xFF2A7B72,
  glazing: 0xFF456B7D,
  counters1: 0xFFC2884A,
  counters0: 0xFFE0B880,
  roof: 0xFF4A4E5A,
  playerRoof: 0xFF353945,
  darkRoof: 0xFF20232A,
  plaza: 0xFFD8D2C2,
  roadMajor: 0xFF3A4052,
  roadMinor: 0xFF52586B,
  commMint: 0xFF58B98C,
  commBlue: 0xFF1D4F91,
  commYellow: 0xFFFFC86B,
  commRed: 0xFFC93D2B,
  greens: [0xFF2D6E3F, 0xFF3C824E, 0xFF4D995F, 0xFF62B075]
};

function shadeColor(color, factor) {
  const r = Math.min(255, Math.floor((color & 255) * factor));
  const g = Math.min(255, Math.floor(((color >> 8) & 255) * factor));
  const b = Math.min(255, Math.floor(((color >> 16) & 255) * factor));
  const a = (color >> 24) & 255;
  return (a << 24) | (b << 16) | (g << 8) | r;
}

export class MeshBuilder {
  constructor() {
    this.vertices = []; // Array of {x, y, z, nx, ny, nz, color, glows} in native coordinates
  }

  // Builder coordinates: x front, y up, z right
  // Native coordinates: x front, y left (-z), z up (+y)
  toNative(bx, by, bz) {
    return [bx, -bz, by];
  }

  addNativeTriangle(p0, p1, p2, color, glows = 0) {
    const u = [p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]];
    const v = [p2[0] - p0[0], p2[1] - p0[1], p2[2] - p0[2]];
    const nx = u[1] * v[2] - u[2] * v[1];
    const ny = u[2] * v[0] - u[0] * v[2];
    const nz = u[0] * v[1] - u[1] * v[0];
    const len = Math.hypot(nx, ny, nz);
    if (len < 1e-6) return; // Degenerate triangle
    const normal = [nx / len, ny / len, nz / len];

    for (const p of [p0, p1, p2]) {
      this.vertices.push({
        x: p[0],
        y: p[1],
        z: p[2],
        nx: normal[0],
        ny: normal[1],
        nz: normal[2],
        color: (((color & 0x00FFFFFF) | 0xFF000000) >>> 0),
        glows
      });
    }
  }

  addQuadBuilder(q0, q1, q2, q3, color, glows = 0) {
    const n0 = this.toNative(q0[0], q0[1], q0[2]);
    const n1 = this.toNative(q1[0], q1[1], q1[2]);
    const n2 = this.toNative(q2[0], q2[1], q2[2]);
    const n3 = this.toNative(q3[0], q3[1], q3[2]);
    this.addNativeTriangle(n0, n1, n2, color, glows);
    this.addNativeTriangle(n0, n2, n3, color, glows);
  }

  addFaceBuilder(points, inside, color, glows = 0) {
    if (points.length < 3) return;
    const nativePoints = points.map(p => this.toNative(p[0], p[1], p[2]));
    const nativeInside = this.toNative(inside[0], inside[1], inside[2]);

    const u = [nativePoints[1][0] - nativePoints[0][0], nativePoints[1][1] - nativePoints[0][1], nativePoints[1][2] - nativePoints[0][2]];
    const v = [nativePoints[2][0] - nativePoints[0][0], nativePoints[2][1] - nativePoints[0][1], nativePoints[2][2] - nativePoints[0][2]];
    const nx = u[1] * v[2] - u[2] * v[1];
    const ny = u[2] * v[0] - u[0] * v[2];
    const nz = u[0] * v[1] - u[1] * v[0];

    const center = [0, 0, 0];
    for (const p of nativePoints) {
      center[0] += p[0] / nativePoints.length;
      center[1] += p[1] / nativePoints.length;
      center[2] += p[2] / nativePoints.length;
    }
    const dot = nx * (center[0] - nativeInside[0]) + ny * (center[1] - nativeInside[1]) + nz * (center[2] - nativeInside[2]);
    const pts = dot >= 0 ? nativePoints : [...nativePoints].reverse();

    for (let i = 1; i < pts.length - 1; i++) {
      this.addNativeTriangle(pts[0], pts[i], pts[i + 1], color, glows);
    }
  }

  box(x, y, z, length, width, height, color) {
    const f = length / 2, r = width / 2;
    const c0 = [x + f, y, z - r];
    const c1 = [x + f, y, z + r];
    const c2 = [x - f, y, z + r];
    const c3 = [x - f, y, z - r];
    const u0 = [x + f, y + height, z - r];
    const u1 = [x + f, y + height, z + r];
    const u2 = [x - f, y + height, z + r];
    const u3 = [x - f, y + height, z - r];

    // Top cap
    this.addQuadBuilder(u0, u3, u2, u1, color);
    // Underside / floor
    this.addQuadBuilder(c3, c0, c1, c2, shadeColor(color, 0.7));
    // Sides
    this.addQuadBuilder(c1, c0, u0, u1, shadeColor(color, 0.92));
    this.addQuadBuilder(c2, c1, u1, u2, shadeColor(color, 0.80));
    this.addQuadBuilder(c3, c2, u2, u3, shadeColor(color, 0.70));
    this.addQuadBuilder(c0, c3, u3, u0, shadeColor(color, 0.86));
  }

  cylinder(x, y, z, radius, height, color, sides = 12) {
    const bottom = [], top = [];
    for (let i = 0; i < sides; i++) {
      const a = (i * 2 * Math.PI) / sides;
      const dx = Math.cos(a) * radius, dz = Math.sin(a) * radius;
      bottom.push([x + dx, y, z + dz]);
      top.push([x + dx, y + height, z + dz]);
    }
    // Top & bottom caps
    this.addFaceBuilder(top, [x, y + height / 2, z], color);
    this.addFaceBuilder(bottom, [x, y + height / 2, z], shadeColor(color, 0.7));

    // Side wall
    for (let i = 0; i < sides; i++) {
      const next = (i + 1) % sides;
      this.addQuadBuilder(bottom[i], bottom[next], top[next], top[i], shadeColor(color, 0.85));
    }
  }

  pane(x, y, z, width, height) {
    this.box(x, y, z, 0.10, width + 0.16, height + 0.16, PALETTE.tileWhite);
    // Glass pane with backing panel
    this.addQuadBuilder(
      [x + 0.057, y + 0.08, z - width / 2],
      [x + 0.057, y + height + 0.08, z - width / 2],
      [x + 0.057, y + height + 0.08, z + width / 2],
      [x + 0.057, y + 0.08, z + width / 2],
      PALETTE.glazing
    );
  }

  commWindowBand(x, y, z, length, width, floors, bays = 4) {
    for (let floor = 0; floor < floors; floor++) {
      const floorY = y + 0.9 + floor * 3.2;
      for (let i = 0; i < bays; i++) {
        const offset = ((i + 0.5) * width) / bays - width / 2;
        this.pane(x + length / 2, floorY, z + offset, (width / bays) * 0.70, 1.45);
        this.box(x - length / 2 - 0.015, floorY, z + offset, 0.03, (width / bays) * 0.70, 1.45, PALETTE.glazing);
      }
      for (const sign of [-1, 1]) {
        for (let i = 0; i < 2; i++) {
          const offset = ((i + 0.5) * length) / 2 - length / 2;
          this.box(x + offset, floorY, z + sign * (width / 2 + 0.015), length * 0.32, 0.03, 1.45, PALETTE.glazing);
        }
      }
    }
  }

  beam(a, b, thickness, color) {
    const ax = a[0], ay = a[1], az = a[2];
    const bx = b[0], by = b[1], bz = b[2];
    const dx = bx - ax, dy = by - ay, dz = bz - az;
    const len = Math.hypot(dx, dy, dz);
    if (len < 1e-4) return;
    this.box((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2, Math.max(thickness, Math.abs(dx)), Math.max(thickness, Math.abs(dz)), Math.max(thickness, Math.abs(dy)), color);
  }

  commAwning(x, y, z, length, width, rise, color) {
    const p1 = [x - length / 2, y + rise, z - width / 2];
    const p2 = [x + length / 2, y, z - width / 2];
    const p3 = [x + length / 2, y, z + width / 2];
    const p4 = [x - length / 2, y + rise, z + width / 2];
    const d = [0, -0.08, 0];

    this.addQuadBuilder(p1, p2, p3, p4, color);
    this.addQuadBuilder(
      [p4[0] + d[0], p4[1] + d[1], p4[2] + d[2]],
      [p3[0] + d[0], p3[1] + d[1], p3[2] + d[2]],
      [p2[0] + d[0], p2[1] + d[1], p2[2] + d[2]],
      [p1[0] + d[0], p1[1] + d[1], p1[2] + d[2]],
      shadeColor(color, 0.7)
    );
    this.box(x, y - 0.1, z, length, width, 0.12, color);
  }

  commSignboard(x, y, z, length, height, thickness = 0.15, frameColor = PALETTE.tankStand, faceColor = PALETTE.commYellow) {
    this.box(x, y, z, thickness, length, height, frameColor);
    this.box(x + thickness / 2 + 0.01, y + 0.04, z, 0.02, length - 0.12, height - 0.08, faceColor);
  }

  commWheel(x, y, z, radius = 0.48, width = 0.28) {
    this.cylinder(x, y + radius, z, radius, width, PALETTE.darkRoof, 12);
    this.cylinder(x, y + radius, z - 0.02, radius * 0.55, width + 0.04, PALETTE.tankStand, 8);
  }

  gable(x, y, z, length, width, rise, color) {
    const halfL = length / 2, halfW = width / 2;
    const p1 = [x - halfL, y, z - halfW];
    const p2 = [x + halfL, y, z - halfW];
    const p3 = [x + halfL, y, z + halfW];
    const p4 = [x - halfL, y, z + halfW];
    const r1 = [x - halfL, y + rise, z];
    const r2 = [x + halfL, y + rise, z];

    this.addQuadBuilder(p1, p2, r2, r1, color);
    this.addQuadBuilder(p3, p4, r1, r2, color);
    this.addFaceBuilder([p1, r1, p4], [x, y, z], PALETTE.tileWhite);
    this.addFaceBuilder([p2, p3, r2], [x, y, z], PALETTE.tileWhite);
    this.box(x, y - 0.12, z, length + 0.7, width + 0.7, 0.12, color);
  }

  canopy(x, y, z, length, width, rise, color) {
    this.commAwning(x, y, z, length, width, rise, color);
  }

  stairs(x, y, z, run = 4, width = 2.4, rise = 2.4) {
    const count = 10;
    for (let i = 0; i < count; i++) {
      this.box(
        x - run / 2 + ((i + 0.5) * run) / count,
        y,
        z,
        run / count,
        width,
        (rise * (i + 1)) / count,
        PALETTE.concrete
      );
    }
  }

  addModelAt(otherMesh, x, y, z, angle = 0) {
    const cosA = Math.cos(angle), sinA = Math.sin(angle);
    const count = otherMesh.vertices.length;
    for (let i = 0; i < count; i += 3) {
      const tri = [otherMesh.vertices[i], otherMesh.vertices[i + 1], otherMesh.vertices[i + 2]];
      const rotated = tri.map(v => {
        // Native rotation around +z (up)
        const rx = cosA * v.x - sinA * v.y + x;
        const ry = sinA * v.x + cosA * v.y + y;
        const rz = v.z + z;
        return [rx, ry, rz];
      });
      this.addNativeTriangle(rotated[0], rotated[1], rotated[2], tri[0].color, tri[0].glows);
    }
  }
}
