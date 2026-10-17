import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import * as SkeletonUtils from 'three/addons/utils/SkeletonUtils.js';

// ============================================================================
// 1. URL Params & Mode / Camera Presets
// ============================================================================
const params = new URLSearchParams(window.location.search);
let currentMode = (params.get('mode') || 'B').toUpperCase();
if (!['A', 'B', 'C'].includes(currentMode)) currentMode = 'B';

let currentView = (params.get('view') || 'overview').toLowerCase();
if (!['overview', 'close', 'mid'].includes(currentView)) currentView = 'overview';

const MODE_META = {
  A: {
    title: 'A｜照 Kenney 原樣（晴）',
    desc: '保留 Kenney 原始色票、玩具車體比例、迷你人物比例與平面屋頂招牌（對照基準）',
    weather: 'sunny',
    taiwanStyle: false,
  },
  B: {
    title: 'B｜配成台灣版（晴・UI_THEME 調色盤）',
    desc: '1.7m 真人比例、台灣車型尺寸、騎樓／雨遮／直立招牌、3 棟透天厝（頂樓鐵皮＋水塔）',
    weather: 'sunny',
    taiwanStyle: true,
  },
  C: {
    title: 'C｜台灣版＋午後雷陣雨（weather.js rain）',
    desc: '台灣版場景套用 weather.js 午後雷陣雨參數（sun×0.56、fogMix 0.24、濕亮柏油、雨絲幕）',
    weather: 'rain',
    taiwanStyle: true,
  },
};

const VIEW_META = {
  overview: {
    badge: '同一視角全景 (A/B/C 對照)',
    pos: [3.4, 11.2, 31.8],
    target: [3.4, 2.2, -5.2],
    fov: 42,
  },
  close: {
    badge: '拉近特寫 (人物臉部＋車輛細節)',
    pos: [-1.1, 1.95, 5.35],
    target: [-1.1, 1.05, 0.15],
    fov: 36,
  },
  mid: {
    badge: '中距離視角 (遊戲 3D 地圖拉近高度)',
    pos: [3.4, 23.5, 29.2],
    target: [3.4, 1.2, -5.2],
    fov: 42,
  },
};

// ============================================================================
// 2. Palette (from docs/UI_THEME.md & Map3DScene.swift / F 台灣版＋)
// ============================================================================
const TAIWAN_PALETTE = {
  ground: 0xd9dfef,
  plaza: 0xd9d4c8,
  sidewalk: 0xc9cedf,
  arcadeFloor: 0xc2b9ab,
  road: 0x4e5682,
  roadWet: 0x384062,
  laneYellow: 0xf2c94c,
  laneWhite: 0xeef1f6,
  platformTop: 0xc8ccd6,
  platformEdge: 0xe6e8ef,
  stationBlue: '#1D4F91',
  treeCrowns: [0x6fa85a, 0x5e9a78, 0x78b262],
  treeTrunk: 0x8a6a4f,
  windowGlass: 0x26313d,
  tireRubber: 0x2b2e34,
  shopWalls: [0xf5ece6, 0xefe6dc, 0xe8eef2, 0xf2ead8, 0xece8f0],
  rowHouseTiles: [0xf2e2d6, 0xe8d8b8, 0xc9d3d6],
  tinRoofs: [0x5e9a78, 0x4e78a8, 0x6f8e7c],
  windowHoods: [0x4e78a8, 0x5e9a78, 0xc65a4e, 0x7a93a6, 0x4e78a8],
  waterTankSteel: 0xc8cdd2,
  waterTankBlue: 0x3b7dd8,
  crates: [0xe86a7a, 0xf2d24b, 0x5e9a78],
  cars: {
    taxi: { body: 0xf2c230, name: '計程車 Taxi (taxi.glb)' },
    sedan: { body: 0xf2f3f1, name: '白色房車 Sedan (sedan.glb)' },
    suv: { body: 0xc3c8cf, name: '銀灰休旅 SUV (suv.glb)' },
    van: { body: 0x3b6fb6, name: '藍色廂型車 Van (van.glb)' },
  },
  pedestrians: [
    { file: 'character-female-b.glb', shirt: 0xe8574a, pants: 0x262c57, skin: 0xedc4a0, hair: 0x2c2a30 },
    { file: 'character-male-a.glb',   shirt: 0x3b7dd8, pants: 0x3e4a66, skin: 0xe8c9a8, hair: 0x2c2a30 },
    { file: 'character-female-c.glb', shirt: 0xffc86b, pants: 0x4e5a6e, skin: 0xedc4a0, hair: 0x5a4232 },
    { file: 'character-male-b.glb',   shirt: 0x12a08f, pants: 0x262c57, skin: 0xe8c9a8, hair: 0x2c2a30 },
    { file: 'character-female-e.glb', shirt: 0xf2f2ee, pants: 0x6b5a4a, skin: 0xedc4a0, hair: 0x2c2a30 },
    { file: 'character-male-d.glb',   shirt: 0x8e6cc9, pants: 0x3e4a66, skin: 0xe8c9a8, hair: 0x5a4232 },
    { file: 'character-female-b.glb', shirt: 0x6fa85a, pants: 0x262c57, skin: 0xedc4a0, hair: 0x5a4232 },
  ],
};

// Shop definitions directly from Railway/town-scene-reference-clean/source/levels/station.js
const STATION_SHOPS = [
  { file: 'building-d.glb', name: '站前便當', sub: '池上・鐵路便當', bg: '#5a3a1e', fg: '#ffe7b0', awning: 0xd9822b, x: -4.2 },
  { file: 'building-a.glb', name: '伴手禮',   sub: '太陽餅・鳳梨酥', bg: '#7a1f1f', fg: '#fff1d6', awning: 0xb83a2e, x: -0.4 },
  { file: 'building-c.glb', name: '車站咖啡', sub: '手沖・冰釀咖啡', bg: '#3b2a20', fg: '#ffdca8', awning: 0x6e473b, x: 3.4 },
  { file: 'building-h.glb', name: '便利商店', sub: '24H 便利超商',   bg: '#f7f7f4', fg: '#1d6fd6', awning: 0x2c6fc4, x: 7.2 },
  { file: 'building-b.glb', name: '麵包坊',   sub: '現烤蔥花・吐司', bg: '#f4e8ef', fg: '#8a4b00', awning: 0xf2c14e, x: 11.0 },
];

const ROW_HOUSES = [
  { file: 'building-f.glb', x: 15.0, tileColor: 0xf2e2d6, roofColor: 0x5e9a78, shutterColor: 0x7d8492 },
  { file: 'building-g.glb', x: 18.4, tileColor: 0xe8d8b8, roofColor: 0x4e78a8, shutterColor: 0x6c7582 },
  { file: 'building-f.glb', x: 21.8, tileColor: 0xc9d3d6, roofColor: 0x6f8e7c, shutterColor: 0x7d8492 },
];

// ============================================================================
// 3. Weather Presets (exact values from source/weather.js)
// ============================================================================
const WEATHER_PRESETS = {
  sunny: {
    label: '晴 (weather.js sunny)',
    daySunScale: 1,
    nightSunScale: 1,
    dayHemiScale: 1,
    nightHemiScale: 1,
    skyTint: 0xffffff,
    skyMix: 0,
    hemiTint: 0xffffff,
    hemiMix: 0,
    groundTint: 0xffffff,
    groundMix: 0,
    fogTint: 0xffffff,
    fogMix: 0,
    fogNear: 1,
    fogFar: 1,
    rain: 0,
    snow: 0,
  },
  rain: {
    label: '午後雷陣雨 (weather.js rain)',
    daySunScale: 0.56,
    nightSunScale: 0.94,
    dayHemiScale: 0.92,
    nightHemiScale: 1,
    skyTint: 0x66778a,
    skyMix: 0.24,
    hemiTint: 0x8392a3,
    hemiMix: 0.1,
    groundTint: 0x68737f,
    groundMix: 0.12,
    fogTint: 0x586777,
    fogMix: 0.24,
    fogNear: 0.84,
    fogFar: 0.76,
    rain: 1,
    snow: 0,
  },
};

// ============================================================================
// 4. Three.js Renderer, Scene, Camera, Lights
// ============================================================================
const canvas = document.getElementById('webgl');
const fxCanvas = document.getElementById('weather-fx');
const fxCtx = fxCanvas.getContext('2d');

const renderer = new THREE.WebGLRenderer({
  canvas,
  antialias: true,
  preserveDrawingBuffer: true,
});
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(42, window.innerWidth / window.innerHeight, 0.15, 220);
const controls = new OrbitControls(camera, canvas);
controls.enableDamping = true;
controls.dampingFactor = 0.08;

const hemiLight = new THREE.HemisphereLight(0xcfe2ff, 0x4a4234, 1.0);
scene.add(hemiLight);

const sunLight = new THREE.DirectionalLight(0xfff2de, 3.0);
sunLight.position.set(22, 34, 24);
sunLight.castShadow = true;
sunLight.shadow.mapSize.set(2048, 2048);
sunLight.shadow.camera.near = 2;
sunLight.shadow.camera.far = 110;
const d = 34;
sunLight.shadow.camera.left = -d;
sunLight.shadow.camera.right = d;
sunLight.shadow.camera.top = d;
sunLight.shadow.camera.bottom = -d;
sunLight.shadow.bias = -0.0004;
scene.add(sunLight);

const fillLight = new THREE.DirectionalLight(0xdceaff, 0.55);
fillLight.position.set(-18, 14, 16);
scene.add(fillLight);

const fog = new THREE.Fog(0x9fc6ea, 55, 140);
scene.fog = fog;

// ============================================================================
// 5. Asset Loader & Cache
// ============================================================================
const loader = new GLTFLoader();
const gltfCache = new Map();

function loadGLB(relPath) {
  if (!gltfCache.has(relPath)) {
    const url = `/models/town/${relPath}`;
    gltfCache.set(
      relPath,
      new Promise((resolve, reject) => {
        loader.load(url, resolve, undefined, reject);
      })
    );
  }
  return gltfCache.get(relPath);
}

function countTriangles(root) {
  let tris = 0;
  root.traverse((obj) => {
    if (obj.isMesh && obj.geometry) {
      const geom = obj.geometry;
      if (geom.index) {
        tris += geom.index.count / 3;
      } else if (geom.attributes.position) {
        tris += geom.attributes.position.count / 3;
      }
    }
  });
  return Math.round(tris);
}

// ============================================================================
// 6. Texture / Material Recoloring Helpers
// ============================================================================
const tmpColor = new THREE.Color();
const tmpHSL = { h: 0, s: 0, l: 0 };

function hexToCss(hexNum, deltaL = 0) {
  tmpColor.setHex(hexNum).getHSL(tmpHSL);
  const l = Math.min(1, Math.max(0, tmpHSL.l + deltaL));
  tmpColor.setHSL(tmpHSL.h, tmpHSL.s, l);
  return `#${tmpColor.getHexString()}`;
}

function paintSwatch8x4(ctx, col, row, hexNum) {
  const x = col * 64;
  const y = row * 128;
  const g1 = ctx.createLinearGradient(0, y, 0, y + 128);
  g1.addColorStop(0, hexToCss(hexNum, 0.05));
  g1.addColorStop(1, hexToCss(hexNum, -0.04));
  ctx.fillStyle = g1;
  ctx.fillRect(x, y, 32, 128);

  const g2 = ctx.createLinearGradient(0, y, 0, y + 128);
  g2.addColorStop(0, hexToCss(hexNum, 0.0));
  g2.addColorStop(1, hexToCss(hexNum, -0.10));
  ctx.fillStyle = g2;
  ctx.fillRect(x + 32, y, 32, 128);
}

/**
 * Recolors a Kenney mini-character using our UI_THEME / Map3DPalette colors,
 * keeping [0,3] & [4,3] dark for eyes/brows while painting skin swatches [0,2], [5,3], [6,3], [7,3]
 * with warm skin tones so every character's eyes, brows, and smile are clearly visible!
 */
function recolorCharacter(charRoot, outfit) {
  let srcImage = null;
  charRoot.traverse((n) => {
    if (n.isMesh && n.material?.map?.image && !srcImage) {
      srcImage = n.material.map.image;
    }
  });
  if (!srcImage) return;

  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 512;
  const ctx = c.getContext('2d');
  ctx.drawImage(srcImage, 0, 0, 512, 512);

  // Row 2: Clothing swatches (shirts / tops / hair accents)
  for (const col of [1, 2, 3, 4, 5, 6, 7]) {
    paintSwatch8x4(ctx, col, 2, outfit.shirt);
  }
  // Row 3:
  // [0,3] & [4,3] are used for eyes/eyebrows/glasses on head-mesh -> keep deep charcoal #1d1f26
  paintSwatch8x4(ctx, 0, 3, 0x1d1f26);
  paintSwatch8x4(ctx, 4, 3, 0x222530);
  // [1,3], [2,3], [3,3] are pants/trousers & dark hair
  paintSwatch8x4(ctx, 1, 3, outfit.pants);
  paintSwatch8x4(ctx, 2, 3, outfit.pants);
  paintSwatch8x4(ctx, 3, 3, outfit.hair);
  // Skin swatches in mini-characters colormap: [0,2], [5,3], [6,3], [7,3]
  paintSwatch8x4(ctx, 0, 2, outfit.skin);
  paintSwatch8x4(ctx, 5, 3, outfit.skin);
  paintSwatch8x4(ctx, 6, 3, outfit.skin);
  paintSwatch8x4(ctx, 7, 3, outfit.skin);

  const tex = new THREE.CanvasTexture(c);
  tex.flipY = false;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.needsUpdate = true;

  charRoot.traverse((n) => {
    if (n.isMesh) {
      n.material = n.material.clone();
      n.material.map = tex;
      n.material.roughness = 0.76;
      n.material.metalness = 0.04;
      n.castShadow = true;
      n.receiveShadow = true;
    }
  });
}

/**
 * Recolors a Kenney car-kit vehicle to our UI_THEME / Map3DPalette colors
 * while keeping headlights, taillights, turn signals, and wheel rims intact.
 */
function recolorCar(carRoot, bodyHex, glassHex = TAIWAN_PALETTE.windowGlass, tireHex = TAIWAN_PALETTE.tireRubber) {
  let srcImage = null;
  carRoot.traverse((n) => {
    if (n.isMesh && n.material?.map?.image && !srcImage) {
      srcImage = n.material.map.image;
    }
  });
  if (!srcImage) return;

  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 512;
  const ctx = c.getContext('2d');
  ctx.drawImage(srcImage, 0, 0, 512, 512);

  // Row 1 (cols 3..7): car body paint swatches
  for (const col of [3, 4, 5, 6, 7]) {
    paintSwatch8x4(ctx, col, 1, bodyHex);
  }
  // Row 2 (cols 1..2): tire rubber
  paintSwatch8x4(ctx, 1, 2, tireHex);
  paintSwatch8x4(ctx, 2, 2, tireHex);
  // Row 2 (cols 3..4): window glass
  paintSwatch8x4(ctx, 3, 2, glassHex);
  paintSwatch8x4(ctx, 4, 2, glassHex);

  const tex = new THREE.CanvasTexture(c);
  tex.flipY = false;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.needsUpdate = true;

  carRoot.traverse((n) => {
    if (n.isMesh) {
      n.material = n.material.clone();
      n.material.map = tex;
      n.material.roughness = 0.44;
      n.material.metalness = 0.12;
      n.castShadow = true;
      n.receiveShadow = true;
    }
  });
}

/**
 * Recolors a Kenney nature tree from neon teal (#29c9ab) to our UI_THEME / Map3DPalette foliage & trunk.
 */
function recolorTree(treeRoot, crownHex, trunkHex = TAIWAN_PALETTE.treeTrunk) {
  treeRoot.traverse((n) => {
    if (n.isMesh && n.material) {
      const mats = Array.isArray(n.material) ? n.material : [n.material];
      const newMats = mats.map((m) => {
        const cloned = m.clone();
        if (m.name === 'leafsGreen' || (m.color && m.color.g > m.color.r)) {
          cloned.color.setHex(crownHex);
          cloned.roughness = 0.85;
          cloned.metalness = 0.02;
        } else {
          cloned.color.setHex(trunkHex);
          cloned.roughness = 0.9;
          cloned.metalness = 0.02;
        }
        return cloned;
      });
      n.material = Array.isArray(n.material) ? newMats : newMats[0];
      n.castShadow = true;
      n.receiveShadow = true;
    }
  });
}

/**
 * Recolors a Kenney commercial building's variation-a colormap to softer Taiwanese plaster/tile tones.
 */
function recolorBuilding(bldgRoot, wallHex, trimHex = 0xd6cfc7, windowHex = TAIWAN_PALETTE.windowGlass) {
  let srcImage = null;
  bldgRoot.traverse((n) => {
    if (n.isMesh && n.material?.map?.image && !srcImage) {
      srcImage = n.material.map.image;
    }
  });
  if (!srcImage) return;

  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 512;
  const ctx = c.getContext('2d');
  ctx.drawImage(srcImage, 0, 0, 512, 512);

  const imgData = ctx.getImageData(0, 0, 512, 512);
  const d = imgData.data;
  const wallRGB = new THREE.Color(wallHex);
  const winRGB = new THREE.Color(windowHex);
  const trimRGB = new THREE.Color(trimHex);

  for (let i = 0; i < d.length; i += 4) {
    const r = d[i] / 255;
    const g = d[i + 1] / 255;
    const b = d[i + 2] / 255;
    const luma = 0.299 * r + 0.587 * g + 0.114 * b;
    if (b > r + 0.08 && b > 0.35) {
      d[i] = Math.round((winRGB.r * 0.75 + r * 0.25) * 255);
      d[i + 1] = Math.round((winRGB.g * 0.75 + g * 0.25) * 255);
      d[i + 2] = Math.round((winRGB.b * 0.75 + b * 0.25) * 255);
    } else if (luma > 0.52) {
      d[i] = Math.round((wallRGB.r * 0.72 + luma * 0.28) * 255);
      d[i + 1] = Math.round((wallRGB.g * 0.72 + luma * 0.28) * 255);
      d[i + 2] = Math.round((wallRGB.b * 0.72 + luma * 0.28) * 255);
    } else {
      d[i] = Math.round((trimRGB.r * 0.55 + r * 0.45) * 255);
      d[i + 1] = Math.round((trimRGB.g * 0.55 + g * 0.45) * 255);
      d[i + 2] = Math.round((trimRGB.b * 0.55 + b * 0.45) * 255);
    }
  }
  ctx.putImageData(imgData, 0, 0);

  const tex = new THREE.CanvasTexture(c);
  tex.flipY = false;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.needsUpdate = true;

  bldgRoot.traverse((n) => {
    if (n.isMesh) {
      n.material = n.material.clone();
      n.material.map = tex;
      n.material.roughness = 0.84;
      n.material.metalness = 0.04;
      n.castShadow = true;
      n.receiveShadow = true;
    }
  });
}

// ============================================================================
// 7. Signboards, Taiwan 騎樓 / 雨遮 / 直立招牌 / 透天厝 / 機車 Builders
// ============================================================================
function makeHorizontalSignTexture(title, sub, bg, fg, borderHex = '#e6c27a') {
  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 160;
  const ctx = c.getContext('2d');
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, 512, 160);
  ctx.strokeStyle = borderHex;
  ctx.lineWidth = 8;
  ctx.strokeRect(8, 8, 496, 144);

  ctx.fillStyle = fg;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.font = '900 68px "PingFang TC", "Microsoft JhengHei", "Noto Sans TC", sans-serif';
  ctx.fillText(title, 256, sub ? 64 : 82);
  if (sub) {
    ctx.font = '700 30px "PingFang TC", "Microsoft JhengHei", "Noto Sans TC", sans-serif';
    ctx.globalAlpha = 0.9;
    ctx.fillText(sub, 256, 122);
  }
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function makeVerticalSignTexture(title, bg, fg, accentColor = '#f2c94c') {
  const c = document.createElement('canvas');
  c.width = 160;
  c.height = 560;
  const ctx = c.getContext('2d');
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, 160, 560);

  ctx.fillStyle = accentColor;
  ctx.fillRect(0, 0, 160, 22);
  ctx.fillRect(0, 538, 160, 22);

  ctx.strokeStyle = fg;
  ctx.lineWidth = 6;
  ctx.strokeRect(10, 10, 140, 540);

  ctx.fillStyle = fg;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  const chars = [...title];
  const n = chars.length;
  const fontSize = n <= 3 ? 82 : 68;
  ctx.font = `900 ${fontSize}px "PingFang TC", "Microsoft JhengHei", "Noto Sans TC", sans-serif`;
  const startY = 85;
  const spanY = 390;
  chars.forEach((ch, idx) => {
    const y = n === 1 ? 280 : startY + (spanY / (n - 1)) * idx;
    ctx.fillText(ch, 80, y);
  });

  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function makeStripedAwningTexture(hexNum) {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 256;
  const ctx = c.getContext('2d');
  const mainCss = hexToCss(hexNum, 0);
  const darkCss = hexToCss(hexNum, -0.08);
  const creamCss = '#fbf6ec';
  const stripes = 8;
  const sw = 256 / stripes;
  for (let i = 0; i < stripes; i++) {
    ctx.fillStyle = i % 2 === 0 ? mainCss : creamCss;
    ctx.fillRect(i * sw, 0, sw, 256);
  }
  ctx.fillStyle = darkCss;
  ctx.fillRect(0, 228, 256, 28);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

function createVerticalSignboard(shop, isRain) {
  const group = new THREE.Group();
  const tex = makeVerticalSignTexture(shop.name, shop.bg, shop.fg);
  const sideMat = new THREE.MeshStandardMaterial({ color: 0x2a2d35, roughness: 0.7 });
  const faceMat = new THREE.MeshStandardMaterial({
    map: tex,
    roughness: 0.35,
    emissive: isRain ? new THREE.Color(shop.bg) : new THREE.Color(0x000000),
    emissiveMap: isRain ? tex : null,
    emissiveIntensity: isRain ? 0.65 : 0.0,
  });

  // BoxGeometry(0.68, 2.75, 0.24) so the vertical text faces +Z (front) and +/-X cleanly!
  const signMesh = new THREE.Mesh(
    new THREE.BoxGeometry(0.68, 2.75, 0.24),
    [sideMat, sideMat, sideMat, sideMat, faceMat, faceMat]
  );
  signMesh.castShadow = true;
  group.add(signMesh);

  // Mounting brackets to building wall (-Z)
  const bracketMat = new THREE.MeshStandardMaterial({ color: 0x353942, roughness: 0.6, metalness: 0.5 });
  for (const by of [-0.9, 0.9]) {
    const bar = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.06, 0.55), bracketMat);
    bar.position.set(0, by, -0.35);
    group.add(bar);
  }
  return group;
}

function createHorizontalSignboard(title, sub, bg, fg, width = 3.4, height = 0.85, isRain = false) {
  const tex = makeHorizontalSignTexture(title, sub, bg, fg);
  const sideMat = new THREE.MeshStandardMaterial({ color: 0x2b2d38, roughness: 0.75 });
  const faceMat = new THREE.MeshStandardMaterial({
    map: tex,
    roughness: 0.4,
    emissive: isRain ? new THREE.Color(0xffffff) : new THREE.Color(0x000000),
    emissiveMap: isRain ? tex : null,
    emissiveIntensity: isRain ? 0.45 : 0.0,
  });
  const mesh = new THREE.Mesh(
    new THREE.BoxGeometry(width, height, 0.16),
    [sideMat, sideMat, sideMat, sideMat, faceMat, sideMat]
  );
  mesh.castShadow = true;
  return mesh;
}

/**
 * Creates a low-poly procedural Taiwanese scooter (機車, 188 tris) to demonstrate
 * how the missing scooter asset in Kenney car-kit can be filled within mobile budget.
 */
function createTaiwanScooter(bodyColor = 0x3b7dd8) {
  const g = new THREE.Group();
  const bodyMat = new THREE.MeshStandardMaterial({ color: bodyColor, roughness: 0.42, metalness: 0.15 });
  const darkMat = new THREE.MeshStandardMaterial({ color: 0x262930, roughness: 0.8 });
  const tireMat = new THREE.MeshStandardMaterial({ color: TAIWAN_PALETTE.tireRubber, roughness: 0.85 });
  const lightMat = new THREE.MeshStandardMaterial({ color: 0xfff4cc, emissive: 0xffd27d, emissiveIntensity: 0.35 });
  const plateMat = new THREE.MeshStandardMaterial({ color: 0xf5f5f2, roughness: 0.5 });

  const wheelGeo = new THREE.CylinderGeometry(0.22, 0.22, 0.11, 10);
  wheelGeo.rotateZ(Math.PI / 2);
  const frontWheel = new THREE.Mesh(wheelGeo, tireMat);
  frontWheel.position.set(0, 0.22, 0.58);
  const rearWheel = new THREE.Mesh(wheelGeo, tireMat);
  rearWheel.position.set(0, 0.22, -0.52);
  g.add(frontWheel, rearWheel);

  const floorboard = new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.14, 0.85), darkMat);
  floorboard.position.set(0, 0.28, 0.02);
  const rearBody = new THREE.Mesh(new THREE.BoxGeometry(0.46, 0.38, 0.72), bodyMat);
  rearBody.position.set(0, 0.52, -0.32);
  const seat = new THREE.Mesh(new THREE.BoxGeometry(0.38, 0.12, 0.66), darkMat);
  seat.position.set(0, 0.74, -0.28);

  const frontShield = new THREE.Mesh(new THREE.BoxGeometry(0.44, 0.68, 0.22), bodyMat);
  frontShield.position.set(0, 0.64, 0.42);
  frontShield.rotation.x = -0.18;

  const handleBar = new THREE.Mesh(new THREE.BoxGeometry(0.66, 0.08, 0.12), bodyMat);
  handleBar.position.set(0, 0.98, 0.35);
  const headLight = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.12, 0.06), lightMat);
  headLight.position.set(0, 0.98, 0.42);

  const mirrorL = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.12, 0.04), darkMat);
  mirrorL.position.set(0.28, 1.08, 0.35);
  const mirrorR = mirrorL.clone();
  mirrorR.position.x = -0.28;
  const plate = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.14, 0.02), plateMat);
  plate.position.set(0, 0.42, -0.70);

  g.add(floorboard, rearBody, seat, frontShield, handleBar, headLight, mirrorL, mirrorR, plate);
  g.traverse((o) => {
    if (o.isMesh) {
      o.castShadow = true;
      o.receiveShadow = true;
    }
  });
  return g;
}

// ============================================================================
// 8. Scene Assembly
// ============================================================================
let sceneRoot = null;
let lastStats = null;

async function buildTownScene(modeKey) {
  const mode = MODE_META[modeKey];
  const isTaiwan = mode.taiwanStyle;
  const isRain = mode.weather === 'rain';

  if (sceneRoot) {
    scene.remove(sceneRoot);
  }
  sceneRoot = new THREE.Group();
  scene.add(sceneRoot);

  const groups = {
    environment: new THREE.Group(),
    buildings: new THREE.Group(),
    trees: new THREE.Group(),
    vehicles: new THREE.Group(),
    scooters: new THREE.Group(),
    people: new THREE.Group(),
  };
  Object.values(groups).forEach((g) => sceneRoot.add(g));

  // --------------------------------------------------------------------------
  // A. Ground, Road, Sidewalk, Station Plaza, Platform & Track
  // --------------------------------------------------------------------------
  const groundMat = new THREE.MeshStandardMaterial({
    color: isTaiwan ? TAIWAN_PALETTE.ground : 0x586249,
    roughness: 0.95,
  });
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(160, 160), groundMat);
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  groups.environment.add(ground);

  // Station-front two-lane road (z = -0.3 to +5.7, width = 6.0m)
  const roadMat = new THREE.MeshStandardMaterial({
    color: isTaiwan ? (isRain ? TAIWAN_PALETTE.roadWet : TAIWAN_PALETTE.road) : 0x2c3038,
    roughness: isRain ? 0.22 : 0.86,
    metalness: isRain ? 0.25 : 0.04,
  });
  const road = new THREE.Mesh(new THREE.BoxGeometry(64, 0.08, 6.2), roadMat);
  road.position.set(4, 0.04, 2.7);
  road.receiveShadow = true;
  groups.environment.add(road);

  // North sidewalk & station plaza (in front of station and shops)
  const sidewalkMat = new THREE.MeshStandardMaterial({
    color: isTaiwan ? TAIWAN_PALETTE.sidewalk : 0x8b9098,
    roughness: isRain ? 0.48 : 0.88,
  });
  const northSidewalk = new THREE.Mesh(new THREE.BoxGeometry(64, 0.16, 4.2), sidewalkMat);
  northSidewalk.position.set(4, 0.08, -2.5);
  northSidewalk.receiveShadow = true;
  groups.environment.add(northSidewalk);

  const southSidewalk = new THREE.Mesh(new THREE.BoxGeometry(64, 0.16, 2.6), sidewalkMat);
  southSidewalk.position.set(4, 0.08, 7.1);
  southSidewalk.receiveShadow = true;
  groups.environment.add(southSidewalk);

  // Station Forecourt Plaza (站前廣場) on the left in front of 晴川站
  const plazaMat = new THREE.MeshStandardMaterial({
    color: isTaiwan ? TAIWAN_PALETTE.plaza : 0x9aa0a6,
    roughness: isRain ? 0.42 : 0.82,
  });
  const plaza = new THREE.Mesh(new THREE.BoxGeometry(13.0, 0.18, 6.6), plazaMat);
  plaza.position.set(-12.2, 0.09, -4.6);
  plaza.receiveShadow = true;
  groups.environment.add(plaza);

  if (isTaiwan) {
    // Double yellow center line (#F2C94C) on the station-front road
    const yellowMat = new THREE.MeshBasicMaterial({ color: TAIWAN_PALETTE.laneYellow });
    for (const dz of [-0.11, 0.11]) {
      const line = new THREE.Mesh(new THREE.BoxGeometry(60, 0.02, 0.09), yellowMat);
      line.position.set(4, 0.09, 2.7 + dz);
      groups.environment.add(line);
    }
    // White edge lines & pedestrian crosswalk (斑馬線) in front of station plaza
    const whiteMat = new THREE.MeshBasicMaterial({ color: TAIWAN_PALETTE.laneWhite });
    for (let i = 0; i < 7; i++) {
      const stripe = new THREE.Mesh(new THREE.BoxGeometry(1.8, 0.02, 0.42), whiteMat);
      stripe.position.set(-7.6, 0.09, 0.1 + i * 0.82);
      groups.environment.add(stripe);
    }
    // Roadside scooter parking boxes (機車停車格) in front of shops
    for (let i = 0; i < 3; i++) {
      const boxOutline = new THREE.Mesh(new THREE.BoxGeometry(0.95, 0.02, 1.85), whiteMat);
      boxOutline.position.set(5.4 + i * 1.15, 0.085, 0.55);
      const boxInner = new THREE.Mesh(new THREE.BoxGeometry(0.83, 0.022, 1.73), roadMat);
      boxInner.position.set(5.4 + i * 1.15, 0.087, 0.55);
      groups.environment.add(boxOutline, boxInner);
    }
  }

  // Side Platform (月台一側) behind the station at z = -11.3
  const platMat = new THREE.MeshStandardMaterial({
    color: isTaiwan ? TAIWAN_PALETTE.platformTop : 0x7c828d,
    roughness: 0.8,
  });
  const platform = new THREE.Mesh(new THREE.BoxGeometry(36, 1.0, 2.8), platMat);
  platform.position.set(-4.5, 0.5, -11.3);
  platform.castShadow = true;
  platform.receiveShadow = true;
  groups.environment.add(platform);

  // Tactile yellow safety line along the platform edge
  const safetyMat = new THREE.MeshBasicMaterial({ color: TAIWAN_PALETTE.laneYellow });
  const safetyLine = new THREE.Mesh(new THREE.BoxGeometry(35.6, 0.03, 0.18), safetyMat);
  safetyLine.position.set(-4.5, 1.01, -12.45);
  groups.environment.add(safetyLine);

  // Platform canopy & pillars
  const canopyMat = new THREE.MeshStandardMaterial({ color: 0x434c5e, roughness: 0.6, metalness: 0.3 });
  const canopyRoof = new THREE.Mesh(new THREE.BoxGeometry(22, 0.16, 2.5), canopyMat);
  canopyRoof.position.set(-8.5, 3.6, -11.3);
  canopyRoof.castShadow = true;
  groups.environment.add(canopyRoof);
  for (let px = -17.5; px <= 0.5; px += 4.5) {
    const post = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.09, 2.6, 8), canopyMat);
    post.position.set(px, 2.3, -11.3);
    groups.environment.add(post);
  }

  // Taiwan Railway Platform Station Nameboard (月台站名牌: 晴川)
  const platSign = createHorizontalSignboard(
    '晴 川  Chingchuan',
    '往 彰化・臺中  ◀   ▶  往 苗栗・新竹',
    isTaiwan ? TAIWAN_PALETTE.stationBlue : '#1b3835',
    '#FFFFFF',
    3.2,
    0.92,
    isRain
  );
  platSign.position.set(-3.8, 2.45, -11.1);
  groups.environment.add(platSign);

  // Track & Commuter Train along z = -14.1
  const railGltf = await loadGLB('train-kit/railroad-straight.glb');
  for (let i = 0; i < 8; i++) {
    const seg = railGltf.scene.clone(true);
    seg.scale.set(4.5, 3.2, 4.5);
    seg.rotation.y = Math.PI / 2;
    seg.position.set(-21 + i * 5.2, 0.02, -14.1);
    groups.environment.add(seg);
  }

  const trainAGltf = await loadGLB('train-kit/train-electric-square-a.glb');
  const trainBGltf = await loadGLB('train-kit/train-electric-square-b.glb');
  const trainCars = [
    { gltf: trainAGltf, x: -13.5, rotY: Math.PI / 2 },
    { gltf: trainBGltf, x: -6.2,  rotY: Math.PI / 2 },
    { gltf: trainAGltf, x: 1.1,   rotY: -Math.PI / 2 },
  ];
  for (const tc of trainCars) {
    const car = tc.gltf.scene.clone(true);
    car.scale.set(3.4, 3.4, 3.4);
    car.rotation.y = tc.rotY;
    car.position.set(tc.x, 0.25, -14.1);
    car.traverse((o) => {
      if (o.isMesh) {
        o.castShadow = true;
        o.receiveShadow = true;
      }
    });
    groups.environment.add(car);
  }

  // Streetlights (roads/light-square.glb)
  const lightGltf = await loadGLB('roads/light-square.glb');
  for (const lx of [-15.0, -7.0, 1.2, 9.2, 17.5]) {
    const lamp = lightGltf.scene.clone(true);
    lamp.scale.set(4.2, 4.5, 4.2);
    lamp.position.set(lx, 0.16, -0.75);
    groups.environment.add(lamp);
  }

  // --------------------------------------------------------------------------
  // B. Station Building (晴川站, commercial/building-k.glb)
  // --------------------------------------------------------------------------
  const stationGltf = await loadGLB('commercial/building-k.glb');
  const station = stationGltf.scene.clone(true);
  station.scale.set(4.9, 5.2, 5.5);
  station.position.set(-12.2, 0.16, -7.2);
  if (isTaiwan) {
    recolorBuilding(station, 0xefe7dc, 0x8d7b68, TAIWAN_PALETTE.windowGlass);
  } else {
    station.traverse((o) => {
      if (o.isMesh) {
        o.castShadow = true;
        o.receiveShadow = true;
      }
    });
  }
  groups.buildings.add(station);

  // Station Signboard (晴川站 from station.js: bg '#1b3835', fg '#f5ead2')
  const stationSign = createHorizontalSignboard(
    '晴 川 站',
    'TRA CHINGCHUAN STATION',
    '#1b3835',
    '#f5ead2',
    5.2,
    1.25,
    isRain
  );
  stationSign.position.set(-12.2, 8.2, -4.9);
  groups.buildings.add(stationSign);

  // Station Entrance Canopy
  const stCanopy = new THREE.Mesh(
    new THREE.BoxGeometry(6.4, 0.24, 2.2),
    new THREE.MeshStandardMaterial({ color: 0x2c4a45, roughness: 0.6 })
  );
  stCanopy.position.set(-12.2, 3.35, -3.9);
  stCanopy.castShadow = true;
  groups.buildings.add(stCanopy);

  // --------------------------------------------------------------------------
  // C. Row of 5 Shops (station.js names & colors + Taiwan 騎樓 / 雨遮 / 直立招牌)
  // --------------------------------------------------------------------------
  for (let i = 0; i < STATION_SHOPS.length; i++) {
    const s = STATION_SHOPS[i];
    const bGltf = await loadGLB(`commercial/${s.file}`);
    const bldg = bGltf.scene.clone(true);

    bldg.scale.set(4.45, 7.6, 5.2);
    bldg.position.set(s.x, 0.16, -6.5);

    if (isTaiwan) {
      recolorBuilding(bldg, TAIWAN_PALETTE.shopWalls[i % TAIWAN_PALETTE.shopWalls.length]);
    } else {
      bldg.traverse((o) => {
        if (o.isMesh) {
          o.castShadow = true;
          o.receiveShadow = true;
        }
      });
    }
    groups.buildings.add(bldg);

    if (!isTaiwan) {
      const roofSign = createHorizontalSignboard(s.name, '', s.bg, s.fg, 3.2, 0.82, false);
      roofSign.position.set(s.x, 10.45, -4.6);
      const flatAwning = new THREE.Mesh(
        new THREE.BoxGeometry(3.4, 0.22, 1.1),
        new THREE.MeshStandardMaterial({ color: s.awning, roughness: 0.7 })
      );
      flatAwning.position.set(s.x, 3.1, -3.7);
      groups.buildings.add(roofSign, flatAwning);
    } else {
      const pillarMat = new THREE.MeshStandardMaterial({
        color: TAIWAN_PALETTE.shopWalls[i % TAIWAN_PALETTE.shopWalls.length],
        roughness: 0.85,
      });

      // 1) 騎樓 (Arcade columns & recessed ground-floor shopfront)
      for (const dx of [-1.68, 1.68]) {
        const pillar = new THREE.Mesh(new THREE.BoxGeometry(0.35, 3.35, 0.35), pillarMat);
        pillar.position.set(s.x + dx, 1.83, -3.15);
        pillar.castShadow = true;
        pillar.receiveShadow = true;
        groups.buildings.add(pillar);
      }
      const arcadeBeam = new THREE.Mesh(new THREE.BoxGeometry(3.76, 0.42, 1.35), pillarMat);
      arcadeBeam.position.set(s.x, 3.45, -3.62);
      groups.buildings.add(arcadeBeam);

      const arcadeFloor = new THREE.Mesh(
        new THREE.BoxGeometry(3.76, 0.04, 1.45),
        new THREE.MeshStandardMaterial({ color: TAIWAN_PALETTE.arcadeFloor, roughness: 0.75 })
      );
      arcadeFloor.position.set(s.x, 0.17, -3.65);
      groups.buildings.add(arcadeFloor);

      // Ground-floor shop counter & colorful Taiwan market crates under 騎樓
      const counter = new THREE.Mesh(
        new THREE.BoxGeometry(1.75, 0.92, 0.55),
        new THREE.MeshStandardMaterial({ color: 0x7c5836, roughness: 0.8 })
      );
      counter.position.set(s.x - 0.35, 0.62, -3.95);
      const crate = new THREE.Mesh(
        new THREE.BoxGeometry(0.46, 0.38, 0.42),
        new THREE.MeshStandardMaterial({ color: TAIWAN_PALETTE.crates[i % 3], roughness: 0.7 })
      );
      crate.position.set(s.x + 1.0, 0.36, -3.85);
      groups.buildings.add(counter, crate);

      // Horizontal shop fascia sign right above the 騎樓 opening
      const fasciaSign = createHorizontalSignboard(s.name, s.sub, s.bg, s.fg, 3.45, 0.78, isRain);
      fasciaSign.position.set(s.x, 3.82, -2.92);
      groups.buildings.add(fasciaSign);

      // 2) 雨遮 (Sloped striped shopfront awning + upper-floor corrugated window rain hoods)
      const awningTex = makeStripedAwningTexture(s.awning);
      const awningMat = new THREE.MeshStandardMaterial({ map: awningTex, roughness: 0.65 });
      const slopedAwning = new THREE.Mesh(new THREE.BoxGeometry(3.58, 0.12, 1.35), awningMat);
      slopedAwning.position.set(s.x, 3.18, -2.42);
      slopedAwning.rotation.x = 0.32;
      slopedAwning.castShadow = true;
      groups.buildings.add(slopedAwning);

      // Upper-floor corrugated window rain hoods (台灣鐵皮窗遮) on 2F & 3F
      const hoodMat = new THREE.MeshStandardMaterial({
        color: TAIWAN_PALETTE.windowHoods[i % TAIWAN_PALETTE.windowHoods.length],
        roughness: 0.55,
        metalness: 0.25,
      });
      for (const wy of [6.1, 8.3]) {
        const hood = new THREE.Mesh(new THREE.BoxGeometry(2.7, 0.1, 0.58), hoodMat);
        hood.position.set(s.x, wy, -3.95);
        hood.rotation.x = 0.26;
        groups.buildings.add(hood);
      }

      // 3) 直立招牌 (Vertical projecting signboard on 2F/3F facade)
      const vertSign = createVerticalSignboard(s, isRain);
      vertSign.position.set(s.x - 1.55, 6.85, -3.35);
      groups.buildings.add(vertSign);
    }
  }

  // --------------------------------------------------------------------------
  // D. 3 棟透天厝 (Taiwanese Row Houses / Shophouses on the right)
  // --------------------------------------------------------------------------
  for (let i = 0; i < ROW_HOUSES.length; i++) {
    const rh = ROW_HOUSES[i];
    const rhGltf = await loadGLB(`commercial/${rh.file}`);
    const house = rhGltf.scene.clone(true);
    house.scale.set(3.75, 6.5, 5.2);
    house.position.set(rh.x, 0.16, -6.5);

    if (isTaiwan) {
      recolorBuilding(house, rh.tileColor, 0x9b9288, TAIWAN_PALETTE.windowGlass);
    } else {
      house.traverse((o) => {
        if (o.isMesh) {
          o.castShadow = true;
          o.receiveShadow = true;
        }
      });
    }
    groups.buildings.add(house);

    if (isTaiwan) {
      const wallMat = new THREE.MeshStandardMaterial({ color: rh.tileColor, roughness: 0.82 });
      for (const dx of [-1.52, 1.52]) {
        const col = new THREE.Mesh(new THREE.BoxGeometry(0.34, 3.35, 0.38), wallMat);
        col.position.set(rh.x + dx, 1.83, -3.15);
        col.castShadow = true;
        groups.buildings.add(col);
      }
      const shutter = new THREE.Mesh(
        new THREE.BoxGeometry(2.65, 2.85, 0.12),
        new THREE.MeshStandardMaterial({ color: rh.shutterColor, roughness: 0.55, metalness: 0.35 })
      );
      shutter.position.set(rh.x, 1.58, -4.1);
      groups.buildings.add(shutter);

      const cageMat = new THREE.MeshStandardMaterial({ color: 0x4a525d, roughness: 0.5, metalness: 0.45 });
      for (const wy of [5.2, 7.6]) {
        const cage = new THREE.Mesh(new THREE.BoxGeometry(2.2, 1.05, 0.35), cageMat);
        cage.position.set(rh.x, wy, -4.02);
        groups.buildings.add(cage);
      }

      // Rooftop corrugated tin add-on (頂樓鐵皮加蓋)
      const tinShed = new THREE.Mesh(
        new THREE.BoxGeometry(3.05, 1.65, 3.6),
        new THREE.MeshStandardMaterial({ color: rh.roofColor, roughness: 0.55, metalness: 0.25 })
      );
      tinShed.position.set(rh.x, 11.9, -6.4);
      tinShed.castShadow = true;
      groups.buildings.add(tinShed);

      const tinRoof = new THREE.Mesh(
        new THREE.BoxGeometry(3.35, 0.14, 4.0),
        new THREE.MeshStandardMaterial({ color: rh.roofColor, roughness: 0.48, metalness: 0.3 })
      );
      tinRoof.position.set(rh.x, 12.8, -6.4);
      groups.buildings.add(tinRoof);

      // Cylindrical stainless/blue rooftop water tower (台灣頂樓不鏽鋼／藍色水塔)
      const tankColor = i === 1 ? TAIWAN_PALETTE.waterTankBlue : TAIWAN_PALETTE.waterTankSteel;
      const tankMat = new THREE.MeshStandardMaterial({
        color: tankColor,
        roughness: 0.32,
        metalness: i === 1 ? 0.15 : 0.65,
      });
      const waterTank = new THREE.Mesh(new THREE.CylinderGeometry(0.48, 0.48, 1.25, 12), tankMat);
      waterTank.position.set(rh.x + 0.8, 13.5, -5.2);
      waterTank.castShadow = true;
      groups.buildings.add(waterTank);
    }
  }

  // --------------------------------------------------------------------------
  // E. Street Trees (7 棵行道樹: tree_default, tree_oak, tree_simple)
  // --------------------------------------------------------------------------
  // Note: kept clear of x = -2.8 .. 0.0 so the close-up camera has an unobstructed view!
  const treePlacements = [
    { file: 'nature/tree_oak.glb',     x: -16.0, z: -0.9, h: 4.8, crownIdx: 0 },
    { file: 'nature/tree_default.glb', x: -9.5,  z: -0.9, h: 4.5, crownIdx: 1 },
    { file: 'nature/tree_oak.glb',     x: -5.8,  z: -0.9, h: 4.6, crownIdx: 2 },
    { file: 'nature/tree_simple.glb',  x: 4.6,   z: -0.9, h: 4.3, crownIdx: 0 },
    { file: 'nature/tree_default.glb', x: 12.8,  z: -0.9, h: 4.6, crownIdx: 1 },
    { file: 'nature/tree_oak.glb',     x: 20.2,  z: -0.9, h: 4.8, crownIdx: 2 },
    { file: 'nature/tree_default.glb', x: 10.5,  z: 6.6,  h: 4.5, crownIdx: 0 },
  ];

  for (const tp of treePlacements) {
    const tGltf = await loadGLB(tp.file);
    const tree = tGltf.scene.clone(true);
    const box = new THREE.Box3().setFromObject(tree);
    const nativeH = Math.max(0.1, box.max.y - box.min.y);
    const s = isTaiwan ? tp.h / nativeH : 2.5;
    tree.scale.set(s, s, s);
    tree.position.set(tp.x, 0.16 - box.min.y * s, tp.z);

    if (isTaiwan) {
      recolorTree(tree, TAIWAN_PALETTE.treeCrowns[tp.crownIdx]);
    } else {
      tree.traverse((o) => {
        if (o.isMesh) {
          o.castShadow = true;
          o.receiveShadow = true;
        }
      });
    }
    groups.trees.add(tree);
  }

  // --------------------------------------------------------------------------
  // F. Vehicles (4 台 car-kit GLB 汽車 + B/C 模式 3 台台灣機車補位)
  // --------------------------------------------------------------------------
  const carSpecs = [
    {
      file: 'car-kit/taxi.glb',
      key: 'taxi',
      x: -3.55,
      z: 0.95,
      rotY: Math.PI / 3,
      twDims: [1.78, 1.52, 4.45],
      nativeDims: [1.5, 1.65, 2.75],
    },
    {
      file: 'car-kit/sedan.glb',
      key: 'sedan',
      x: 1.15,
      z: 0.95,
      rotY: -Math.PI / 3,
      twDims: [1.78, 1.44, 4.45],
      nativeDims: [1.5, 1.45, 2.55],
    },
    {
      file: 'car-kit/suv.glb',
      key: 'suv',
      x: 6.2,
      z: 4.15,
      rotY: -Math.PI / 2,
      twDims: [1.86, 1.68, 4.60],
      nativeDims: [1.5, 1.40, 2.55],
    },
    {
      file: 'car-kit/van.glb',
      key: 'van',
      x: 13.8,
      z: 1.25,
      rotY: Math.PI / 2,
      twDims: [1.82, 1.88, 4.60],
      nativeDims: [1.5, 1.45, 2.75],
    },
  ];

  for (const cs of carSpecs) {
    const cGltf = await loadGLB(cs.file);
    const car = cGltf.scene.clone(true);
    if (isTaiwan) {
      const sx = cs.twDims[0] / cs.nativeDims[0];
      const sy = cs.twDims[1] / cs.nativeDims[1];
      const sz = cs.twDims[2] / cs.nativeDims[2];
      car.scale.set(sx, sy, sz);
      car.position.set(cs.x, 0.08 + 0.30 * sy, cs.z);
      recolorCar(car, TAIWAN_PALETTE.cars[cs.key].body);
    } else {
      const s = 1.25;
      car.scale.set(s, s, s);
      car.position.set(cs.x, 0.08 + 0.30 * s, cs.z);
      car.traverse((o) => {
        if (o.isMesh) {
          o.castShadow = true;
          o.receiveShadow = true;
        }
      });
    }
    car.rotation.y = cs.rotY;
    groups.vehicles.add(car);
  }

  // Add 3 parked Taiwanese scooters in Modes B & C (demonstrating the scooter gap in Kenney car-kit)
  if (isTaiwan) {
    const scooterColors = [0x3b7dd8, 0xe8574a, 0xf2f2ee];
    for (let i = 0; i < 3; i++) {
      const scooter = createTaiwanScooter(scooterColors[i]);
      scooter.position.set(5.4 + i * 1.15, 0.08, 0.55);
      scooter.rotation.y = 0.08 * (i - 1);
      groups.scooters.add(scooter);
    }
  }

  // --------------------------------------------------------------------------
  // G. Pedestrians (7 個行人, 1.70m tall in Taiwan mode, UI_THEME wardrobe)
  // --------------------------------------------------------------------------
  // IMPORTANT: Use SkeletonUtils.clone(pGltf.scene) so SkinnedMesh bones rebind properly!
  // Native character height in mini-characters is 0.70m -> scaleY = 1.70 / 0.70 = 2.43 for 1.70m real-world height!
  const pedPlacements = [
    { idx: 0, x: -2.15, z: -0.55, rotY: 0.18 },
    { idx: 1, x: -1.10, z: -0.45, rotY: 0.0 },
    { idx: 2, x: -0.05, z: -0.55, rotY: -0.18 },
    { idx: 3, x: -7.50, z: 1.55,  rotY: 0.15 },
    { idx: 4, x: 3.10,  z: -1.35, rotY: -0.25 },
    { idx: 5, x: 7.40,  z: -1.35, rotY: 0.20 },
    { idx: 6, x: 11.50, z: -1.35, rotY: -0.15 },
  ];

  for (const pp of pedPlacements) {
    const outfit = TAIWAN_PALETTE.pedestrians[pp.idx];
    const pGltf = await loadGLB(`mini-characters/${outfit.file}`);
    const person = SkeletonUtils.clone(pGltf.scene);

    // Skinned character height at scale=1 is ~1.0m -> scaleY = 1.70 gives 1.70m real-world human height
    // (slightly taller than the 1.48m taxi & 1.44m sedan).
    const scaleY = isTaiwan ? 1.70 : 1.45;
    const scaleXZ = isTaiwan ? 1.42 : 1.45;

    if (isTaiwan) {
      recolorCharacter(person, outfit);
    } else {
      person.traverse((o) => {
        if (o.isMesh) {
          o.castShadow = true;
          o.receiveShadow = true;
        }
      });
    }

    person.scale.set(scaleXZ, scaleY, scaleXZ);
    person.position.set(pp.x, 0.16, pp.z);
    person.rotation.y = pp.rotY;
    groups.people.add(person);
  }

  // --------------------------------------------------------------------------
  // H. Apply Weather (weather.js sunny vs rain)
  // --------------------------------------------------------------------------
  applyWeather(mode.weather);

  // --------------------------------------------------------------------------
  // I. Compute Exact Triangle Breakdown & Update HUD
  // --------------------------------------------------------------------------
  const totalTris = countTriangles(sceneRoot);
  const peoplePerItem = groups.people.children.map((c) => countTriangles(c));
  const vehiclePerItem = groups.vehicles.children.map((c) => countTriangles(c));
  const scooterPerItem = groups.scooters.children.map((c) => countTriangles(c));
  const treePerItem = groups.trees.children.map((c) => countTriangles(c));
  const bldgTris = countTriangles(groups.buildings);
  const envTris = countTriangles(groups.environment);

  const sum = (arr) => arr.reduce((a, b) => a + b, 0);
  lastStats = {
    mode: modeKey,
    modeTitle: mode.title,
    view: currentView,
    viewBadge: VIEW_META[currentView].badge,
    weather: mode.weather,
    totalTriangles: totalTris,
    people: {
      count: peoplePerItem.length,
      perModelTriangles: peoplePerItem,
      minTriangles: Math.min(...peoplePerItem),
      maxTriangles: Math.max(...peoplePerItem),
      totalTriangles: sum(peoplePerItem),
      budgetTarget: 500,
      exceedsBudget: Math.max(...peoplePerItem) > 500,
    },
    vehicles: {
      count: vehiclePerItem.length,
      perModelTriangles: vehiclePerItem,
      minTriangles: Math.min(...vehiclePerItem),
      maxTriangles: Math.max(...vehiclePerItem),
      totalTriangles: sum(vehiclePerItem),
      budgetTarget: 1500,
      exceedsBudget: Math.max(...vehiclePerItem) > 1500,
    },
    scooters: {
      count: scooterPerItem.length,
      perModelTriangles: scooterPerItem,
      totalTriangles: sum(scooterPerItem),
      note: '參考包 car-kit 無機車 GLB；B/C 以程式化幾何補位 (188 tris/台)',
    },
    trees: {
      count: treePerItem.length,
      perModelTriangles: treePerItem,
      minTriangles: Math.min(...treePerItem),
      maxTriangles: Math.max(...treePerItem),
      totalTriangles: sum(treePerItem),
    },
    buildingsTriangles: bldgTris,
    environmentTriangles: envTris,
  };

  updateHUD(lastStats);
  return lastStats;
}

// ============================================================================
// 9. Weather Lighting & 2D Rain Curtain (from source/weather.js)
// ============================================================================
let activeWeatherKey = 'sunny';
const rainDrops = [];
const RAIN_COUNT = 480;
const RAIN_SLANT = 0.12;

function initRainDrops(w, h) {
  rainDrops.length = 0;
  let seed = 20261017;
  const rand = () => {
    seed = (seed * 1664525 + 1013904223) >>> 0;
    return seed / 0xffffffff;
  };
  for (let i = 0; i < RAIN_COUNT; i++) {
    rainDrops.push({
      x: rand() * w,
      y: rand() * h,
      len: 15 + rand() * 15,
      alpha: 0.24 + rand() * 0.22,
    });
  }
}

function applyWeather(weatherKey) {
  activeWeatherKey = weatherKey;
  const preset = WEATHER_PRESETS[weatherKey] || WEATHER_PRESETS.sunny;

  const baseSky = new THREE.Color(0x9fc6ea);
  const baseHemiSky = new THREE.Color(0xcfe2ff);
  const baseHemiGround = new THREE.Color(0x4a4234);
  const baseSun = new THREE.Color(0xfff2de);

  const skyColor = baseSky.clone().lerp(new THREE.Color(preset.skyTint), preset.skyMix);
  const hemiSkyColor = baseHemiSky.clone().lerp(new THREE.Color(preset.hemiTint), preset.hemiMix);
  const hemiGroundColor = baseHemiGround.clone().lerp(new THREE.Color(preset.groundTint), preset.groundMix);
  const fogColor = skyColor.clone().lerp(new THREE.Color(preset.fogTint), preset.fogMix);

  renderer.setClearColor(skyColor);
  scene.background = skyColor;

  sunLight.color.copy(baseSun);
  sunLight.intensity = 3.0 * preset.daySunScale;

  hemiLight.color.copy(hemiSkyColor);
  hemiLight.groundColor.copy(hemiGroundColor);
  hemiLight.intensity = 1.0 * preset.dayHemiScale;

  fog.color.copy(fogColor);
  fog.near = 55 * preset.fogNear;
  fog.far = 140 * preset.fogFar;

  drawWeatherOverlay();
}

function drawWeatherOverlay() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const w = window.innerWidth;
  const h = window.innerHeight;
  if (fxCanvas.width !== w * dpr || fxCanvas.height !== h * dpr) {
    fxCanvas.width = w * dpr;
    fxCanvas.height = h * dpr;
    initRainDrops(w, h);
  }
  fxCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
  fxCtx.clearRect(0, 0, w, h);

  const preset = WEATHER_PRESETS[activeWeatherKey];
  if (!preset || preset.rain <= 0) return;

  fxCtx.lineCap = 'round';
  fxCtx.lineWidth = 1.3;
  for (const r of rainDrops) {
    fxCtx.strokeStyle = `rgba(210, 226, 240, ${r.alpha.toFixed(2)})`;
    fxCtx.beginPath();
    fxCtx.moveTo(r.x, r.y);
    fxCtx.lineTo(r.x + r.len * RAIN_SLANT * 2.2, r.y + r.len);
    fxCtx.stroke();
  }
}

// ============================================================================
// 10. HUD & Camera Controls
// ============================================================================
function applyCameraView(viewKey) {
  currentView = viewKey;
  const v = VIEW_META[viewKey] || VIEW_META.overview;
  camera.fov = v.fov;
  camera.updateProjectionMatrix();
  camera.position.set(...v.pos);
  controls.target.set(...v.target);
  controls.update();

  document.getElementById('hud-view-title').textContent = v.badge;
  document.querySelectorAll('[data-view]').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.view === viewKey);
  });
}

function updateHUD(stats) {
  document.getElementById('hud-mode-title').textContent = stats.modeTitle;
  document.getElementById('hud-view-title').textContent = stats.viewBadge;
  document.getElementById('hud-desc').textContent = MODE_META[stats.mode].desc;
  document.getElementById('hud-total-tris').textContent = `${stats.totalTriangles.toLocaleString()} tris`;

  const p = stats.people;
  const v = stats.vehicles;
  const t = stats.trees;
  const sc = stats.scooters;

  const tbody = document.getElementById('hud-tbody');
  tbody.innerHTML = `
    <tr>
      <td><strong>行人 People</strong> (${p.count} 人)</td>
      <td>${p.minTriangles}–${p.maxTriangles} tris/人</td>
      <td>${p.totalTriangles.toLocaleString()} tris</td>
      <td class="status-over">⚠️ 超過目標 ≤500 (+38%～+51%)</td>
    </tr>
    <tr>
      <td><strong>汽車 Cars</strong> (${v.count} 台 GLB)</td>
      <td>${v.minTriangles.toLocaleString()}–${v.maxTriangles.toLocaleString()} tris/台</td>
      <td>${v.totalTriangles.toLocaleString()} tris</td>
      <td class="status-over">⚠️ 超過目標 ≤1,500 (+35%～+65%)</td>
    </tr>
    <tr>
      <td><strong>機車 Scooters</strong> (${sc.count} 台補位)</td>
      <td>${sc.count > 0 ? '188 tris/台' : '0 (無 GLB)'}</td>
      <td>${sc.totalTriangles.toLocaleString()} tris</td>
      <td class="status-ok">${sc.count > 0 ? '✅ 程式化補位 (≤1,500)' : '⚠️ 參考包缺機車 GLB'}</td>
    </tr>
    <tr>
      <td><strong>行道樹 Trees</strong> (${t.count} 棵 GLB)</td>
      <td>${t.minTriangles}–${t.maxTriangles} tris/棵</td>
      <td>${t.totalTriangles.toLocaleString()} tris</td>
      <td class="status-ok">✅ 符合手機預算</td>
    </tr>
    <tr>
      <td><strong>站房＋店面＋透天厝＋軌道</strong></td>
      <td>9 棟建築＋列車</td>
      <td>${(stats.buildingsTriangles + stats.environmentTriangles).toLocaleString()} tris</td>
      <td style="color:#B8C0D4">天氣：${WEATHER_PRESETS[stats.weather].label}</td>
    </tr>
  `;

  document.getElementById('hud-gap-note').innerHTML =
    `<strong>模型缺口與預算結論：</strong>Kenney 參考包 <code>mini-characters</code> 單人 690–756 tris（超標）、<code>car-kit</code> 單車 2,032–2,474 tris（超標），且<strong>缺少台灣機車與市區公車 GLB</strong>。`;

  document.querySelectorAll('[data-mode]').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.mode === stats.mode);
  });
}

// Bind UI buttons
document.querySelectorAll('[data-mode]').forEach((btn) => {
  btn.addEventListener('click', async () => {
    currentMode = btn.dataset.mode;
    await buildTownScene(currentMode);
    renderFrame();
  });
});

document.querySelectorAll('[data-view]').forEach((btn) => {
  btn.addEventListener('click', () => {
    applyCameraView(btn.dataset.view);
    if (lastStats) {
      lastStats.view = currentView;
      lastStats.viewBadge = VIEW_META[currentView].badge;
    }
    renderFrame();
  });
});

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
  drawWeatherOverlay();
  renderFrame();
});

function renderFrame() {
  controls.update();
  renderer.render(scene, camera);
  drawWeatherOverlay();
}

function animate() {
  requestAnimationFrame(animate);
  if (activeWeatherKey === 'rain') {
    const w = window.innerWidth;
    const h = window.innerHeight;
    for (const r of rainDrops) {
      r.y += 3.6;
      r.x += 3.6 * RAIN_SLANT;
      if (r.y > h) {
        r.y = -20;
        r.x = (r.x + w) % w;
      }
    }
  }
  renderFrame();
}

// Expose programmatic API for Playwright/CDP screenshot runner
window.setPreviewState = async (modeKey, viewKey) => {
  currentMode = modeKey.toUpperCase();
  applyCameraView(viewKey.toLowerCase());
  const stats = await buildTownScene(currentMode);
  initRainDrops(window.innerWidth, window.innerHeight);
  renderFrame();
  return stats;
};
window.getStats = () => lastStats;

// Initial boot
(async () => {
  applyCameraView(currentView);
  await buildTownScene(currentMode);
  renderFrame();
  window.__TOWN_PREVIEW_READY__ = true;
  animate();
})();
