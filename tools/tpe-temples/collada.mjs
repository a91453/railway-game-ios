// A small reader for the COLLADA 1.4 files SketchUp 8 writes into the
// Taipei religious buildings' KMZ (decision 725): the scene's nodes with
// their matrices, instanced geometries and nodes, `triangles` (and
// `polylist` of triangles), each corner's texture coordinate, and each
// material's texture or colour. Lines are skipped. No dependency.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

// Elements as { name, attrs, children, text }.
export function parseXml(source) {
  const root = { name: '#root', attrs: {}, children: [], text: '' };
  const stack = [root];
  const tag = /<(\/?)([A-Za-z_][\w:.-]*)((?:\s+[\w:.-]+\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(\/?)>|<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<!\[CDATA\[([\s\S]*?)\]\]>/g;
  let last = 0, match;
  while ((match = tag.exec(source))) {
    const top = stack[stack.length - 1];
    if (match.index > last) top.text += source.slice(last, match.index);
    last = tag.lastIndex;
    if (match[5] !== undefined) { top.text += match[5]; continue; }
    if (!match[2]) continue;
    if (match[1]) {
      if (top.name !== match[2]) throw new Error(`XML: </${match[2]}> closes <${top.name}>`);
      stack.pop();
      continue;
    }
    const attrs = {};
    for (const a of match[3].matchAll(/([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) attrs[a[1]] = a[2] ?? a[3];
    const element = { name: match[2], attrs, children: [], text: '' };
    top.children.push(element);
    if (!match[4]) stack.push(element);
  }
  if (stack.length !== 1) throw new Error('XML: unclosed elements');
  return root;
}

const child = (e, name) => e?.children.find(c => c.name === name);
const children = (e, name) => e?.children.filter(c => c.name === name) ?? [];
function* walk(e) { yield e; for (const c of e.children) yield* walk(c); }
const numbers = text => text.trim() === '' ? [] : text.trim().split(/\s+/).map(Number);
const ref = url => url.replace(/^#/, '');

// 4x4 row-major matrices.
const identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
export function multiply(a, b) {
  const out = new Array(16).fill(0);
  for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) for (let k = 0; k < 4; k++) out[r * 4 + c] += a[r * 4 + k] * b[k * 4 + c];
  return out;
}
const apply = (m, [x, y, z]) => [m[0] * x + m[1] * y + m[2] * z + m[3], m[4] * x + m[5] * y + m[6] * z + m[7], m[8] * x + m[9] * y + m[10] * z + m[11]];

function nodeMatrix(node) {
  let m = identity;
  for (const c of node.children) {
    if (c.name === 'matrix') m = multiply(m, numbers(c.text));
    else if (c.name === 'translate') { const [x, y, z] = numbers(c.text); m = multiply(m, [1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z, 0, 0, 0, 1]); }
    else if (c.name === 'scale') { const [x, y, z] = numbers(c.text); m = multiply(m, [x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1]); }
    else if (c.name === 'rotate') {
      const [x, y, z, deg] = numbers(c.text), a = deg * Math.PI / 180, s = Math.sin(a), co = Math.cos(a), t = 1 - co;
      m = multiply(m, [t * x * x + co, t * x * y - s * z, t * x * z + s * y, 0, t * x * y + s * z, t * y * y + co, t * y * z - s * x, 0,
        t * x * z - s * y, t * y * z + s * x, t * z * z + co, 0, 0, 0, 0, 1]);
    }
  }
  return m;
}

// The `.dae` at `path`: its triangles in metres, z up, each with its three
// corners (`points`), texture coordinates (`uvs`, or null) and material
// (`material`: { image: file path or null, color: [r, g, b, a] 0..1 }).
export function readCollada(path) {
  const doc = parseXml(readFileSync(path, 'utf8'));
  const collada = child(doc, 'COLLADA');
  if (!collada) throw new Error(`${path}: not COLLADA`);
  const asset = child(collada, 'asset');
  const metre = Number(child(asset, 'unit')?.attrs.meter ?? 1);
  const up = child(asset, 'up_axis')?.text.trim() ?? 'Y_UP';
  if (up !== 'Z_UP') throw new Error(`${path}: only Z_UP is read (it is ${up})`);
  const ids = new Map();
  for (const e of walk(collada)) if (e.attrs.id) ids.set(e.attrs.id, e);

  const images = new Map();
  for (const image of children(child(collada, 'library_images'), 'image')) {
    images.set(image.attrs.id, join(dirname(path), decodeURIComponent(child(image, 'init_from').text.trim())));
  }
  const materials = new Map();
  function material(id) {
    if (materials.has(id)) return materials.get(id);
    const effect = ids.get(ref(child(ids.get(id), 'instance_effect').attrs.url));
    const profile = child(effect, 'profile_COMMON');
    const params = new Map(children(profile, 'newparam').map(p => [p.attrs.sid, p]));
    let image = null, color = [0.8, 0.8, 0.8, 1];
    for (const e of walk(profile)) {
      if (e.name !== 'diffuse') continue;
      const texture = child(e, 'texture'), c = child(e, 'color');
      if (c) color = numbers(c.text);
      if (texture) {
        const sampler = params.get(texture.attrs.texture);
        const surface = sampler && params.get(child(child(sampler, 'sampler2D'), 'source').text.trim());
        const imageId = surface ? child(child(surface, 'surface'), 'init_from').text.trim() : texture.attrs.texture;
        image = images.get(imageId) ?? null;
      }
    }
    for (const e of walk(profile)) if (e.name === 'transparency') { const t = numbers(e.text)[0]; if (t !== undefined && t < 0.5) color = [...color.slice(0, 3), t]; }
    const made = { id, name: ids.get(id).attrs.name ?? id, image, color };
    materials.set(id, made);
    return made;
  }

  const sourceCache = new Map();
  function source(id) {
    if (!sourceCache.has(id)) {
      const e = ids.get(id);
      const accessor = child(child(e, 'technique_common'), 'accessor');
      sourceCache.set(id, { data: numbers(child(e, 'float_array').text), stride: Number(accessor.attrs.stride ?? 1) });
    }
    return sourceCache.get(id);
  }

  const out = [];
  function geometry(geometryElement, matrix, bindings) {
    const mesh = child(geometryElement, 'mesh');
    if (!mesh) return;
    const vertices = child(mesh, 'vertices');
    const positionInput = children(vertices, 'input').find(i => i.attrs.semantic === 'POSITION');
    const positions = source(ref(positionInput.attrs.source));
    for (const prim of mesh.children) {
      if (prim.name !== 'triangles' && prim.name !== 'polylist') continue;
      const inputs = children(prim, 'input');
      const stride = Math.max(...inputs.map(i => Number(i.attrs.offset))) + 1;
      const vertexOffset = Number(inputs.find(i => i.attrs.semantic === 'VERTEX').attrs.offset);
      const texInput = inputs.find(i => i.attrs.semantic === 'TEXCOORD');
      const uvSource = texInput && source(ref(texInput.attrs.source));
      const p = numbers(child(prim, 'p').text);
      if (prim.name === 'polylist' && numbers(child(prim, 'vcount').text).some(n => n !== 3)) throw new Error(`${path}: polylist with non-triangles`);
      const symbol = prim.attrs.material;
      const target = symbol ? bindings.get(symbol) : null;
      const mat = target ? material(target) : { id: null, name: 'default', image: null, color: [0.8, 0.8, 0.8, 1] };
      for (let i = 0; i + 3 * stride <= p.length; i += 3 * stride) {
        const points = [], uvs = [];
        for (let k = 0; k < 3; k++) {
          const v = p[i + k * stride + vertexOffset];
          const local = positions.data.slice(v * positions.stride, v * positions.stride + 3);
          points.push(apply(matrix, local).map(n => n * metre));
          if (uvSource) {
            const t = p[i + k * stride + Number(texInput.attrs.offset)];
            uvs.push(uvSource.data.slice(t * uvSource.stride, t * uvSource.stride + 2));
          }
        }
        out.push({ points, uvs: uvSource ? uvs : null, material: mat });
      }
    }
  }
  function visit(node, parent) {
    const matrix = multiply(parent, nodeMatrix(node));
    for (const c of node.children) {
      if (c.name === 'instance_geometry') {
        const bindings = new Map();
        for (const e of walk(c)) if (e.name === 'instance_material') bindings.set(e.attrs.symbol, ref(e.attrs.target));
        geometry(ids.get(ref(c.attrs.url)), matrix, bindings);
      } else if (c.name === 'instance_node') {
        visit(ids.get(ref(c.attrs.url)), matrix);
      } else if (c.name === 'node') visit(c, matrix);
    }
  }
  const sceneUrl = child(child(collada, 'scene'), 'instance_visual_scene').attrs.url;
  for (const node of children(ids.get(ref(sceneUrl)), 'node')) visit(node, identity);
  return { triangles: out, materials: [...materials.values()], unitMetres: metre, authoringTool: child(child(asset, 'contributor'), 'authoring_tool')?.text.trim() ?? null };
}

// The KML's model placement: latitude, longitude and heading (degrees
// clockwise from north).
export function readKml(path) {
  const text = readFileSync(path, 'utf8');
  const model = text.slice(text.indexOf('<Model'));
  const get = name => { const m = model.match(new RegExp(`<${name}>\\s*([-0-9.eE+]+)\\s*</${name}>`)); if (!m) throw new Error(`${path}: no ${name}`); return Number(m[1]); };
  return { latitude: get('latitude'), longitude: get('longitude'), heading: get('heading') };
}
