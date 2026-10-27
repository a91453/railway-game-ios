import {assemblyNative} from '../emu900-native/scene.js';
// WebGL preview of M3DM models lit as the game lights a model (decision 370's
// soft light, `map3dLit(..., soft: true)` in Map3DShaders.metal), with the
// light the game's `Map3DLighting` gives at the hour (manifest.json
// "lighting"). Adapted from tools/station-kit/renderer.js (same project).
//
// Assumed, not measured: the train runs east (model +x = world +x, model +y
// left = world -z, model z up = world y), so the sun's world direction is
// turned into the model's space once; no fog, no sun shadow, no
// `map3dFinish` grade. WebGL is a preview, not the Metal renderer's look or
// cost on an iPhone.
//
// Hooks for later work: `options.time` ('day' | 'night') picks the lighting
// block; `options.features` is handed to the fragment shader as flags, so a
// later pull request (night lamps, baked occlusion, glass reflection) can
// draw a before/after with the same tool. Bit 0 (`--features 1`, decision
// 450): the trains' glass and stainless (the M3DM flags' bits 1 and 2) mirror
// the sky and catch the sun as `map3dShade` draws them (the sky from the
// fog's colour to the zenith; no shade in `u`, so a shut-in face mirrors as
// much as an open one).
export const directions = {top: [0, 0, 1], bottom: [0, 0, -1], left: [0, 1, 0], right: [0, -1, 0], front: [1, 0, 0], back: [-1, 0, 0], isometric: [1, -1, 0.8]};
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const unit = a => { const n = Math.hypot(...a); return a.map(x => x / n); };

export class NativeRenderer {
  constructor(canvas, lighting) {
    this.canvas = canvas; this.lighting = lighting;
    const gl = canvas.getContext('webgl2', {alpha: true, antialias: true, preserveDrawingBuffer: true});
    if (!gl) throw Error('WebGL 2 is not available.');
    this.gl = gl;
    const vertex = `#version 300 es
    layout(location=0) in vec3 position; layout(location=1) in vec3 normal; layout(location=2) in vec4 color; layout(location=3) in float glow; layout(location=4) in float material;
    uniform vec3 centre, right, up, direction; uniform float radius, aspect, depth;
    out vec3 n; out vec4 c; out float g; out float k;
    void main(){ vec3 p = position - centre; gl_Position = vec4(dot(p, right) / (radius * aspect), dot(p, up) / radius, -dot(p, direction) / depth, 1.0); n = normal; c = color; g = glow; k = material; }`;
    const fragment = `#version 300 es
    precision highp float; in vec3 n; in vec4 c; in float g; in float k; out vec4 outColor;
    uniform vec3 sunModel, sunLight, skyLight, lampGlow, lineColour, toEye, horizon, zenith, glint; uniform float lights, sunShown; uniform int features; uniform bool silhouette;
    vec3 seen(vec3 w){ return w.z >= 0.0 ? mix(horizon, zenith, sqrt(w.z)) : horizon * (1.0 - 0.45 * smoothstep(0.0, 0.4, -w.z)); }
    void main(){
      vec3 base = c.a < 0.5 ? lineColour : c.rgb;
      vec3 nn = normalize(n);
      float sun = max(dot(nn, sunModel), 0.0);
      float sky = 0.85 - 0.05 * lights;
      vec3 light = vec3(sky + 0.02 * max(nn.z, 0.0) + 0.15 * sun) * mix(vec3(0.94, 0.96, 1.0), vec3(1.0, 0.99, 0.97), sun);
      light *= (skyLight + sunLight * 0.5) / vec3(0.925, 0.871, 0.806);
      vec3 glow = g * base * lampGlow;
      vec4 mirrored = vec4(0.0);
      if ((features & 1) != 0 && k > 0.5) {
        vec3 r = reflect(-toEye, nn); float cs = max(dot(toEye, nn), 0.0), s = max(dot(r, sunModel), 0.0);
        float sunny = step(0.0, dot(nn, sunModel)) * sunShown;
        if (k > 1.5) {
          mirrored = vec4(seen(r) * base * 1.2, 0.22 + 0.4 * pow(1.0 - cs, 5.0));
          glow += glint * base * ((pow(s, 40.0) * 0.25 + pow(s, 6.0) * 0.05) * sunny);
        } else {
          float lit = g > 0.5 ? 1.0 - 0.85 * lights : 1.0;
          mirrored = vec4(seen(r), 0.9 * (0.1 + 0.9 * pow(1.0 - cs, 4.0)) * lit);
          glow += glint * ((pow(s, 1400.0) * 3.0 + pow(s, 90.0) * 0.35 + pow(s, 7.0) * 0.1) * sunny * lit);
        }
      }
      outColor = vec4(silhouette ? base : min(mix(base * light, mirrored.rgb, mirrored.a) + glow, 1.0), 1.0);
    }`;
    const shader = (type, source) => { const s = gl.createShader(type); gl.shaderSource(s, source); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw Error(gl.getShaderInfoLog(s)); return s; };
    const p = gl.createProgram(), vs = shader(gl.VERTEX_SHADER, vertex), fs = shader(gl.FRAGMENT_SHADER, fragment);
    gl.attachShader(p, vs); gl.attachShader(p, fs); gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw Error(gl.getProgramInfoLog(p));
    this.program = p; this.buffer = gl.createBuffer(); this.vao = gl.createVertexArray();
    gl.bindVertexArray(this.vao); gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
    for (const [index, size, offset] of [[0, 3, 0], [1, 3, 12], [2, 4, 24], [3, 1, 40], [4, 1, 44]]) { gl.enableVertexAttribArray(index); gl.vertexAttribPointer(index, size, gl.FLOAT, false, 48, offset); }
    this.uniforms = Object.fromEntries(['centre', 'right', 'up', 'direction', 'radius', 'aspect', 'depth', 'sunModel', 'sunLight', 'skyLight', 'lampGlow', 'lineColour', 'lights', 'features', 'silhouette',
      'toEye', 'horizon', 'zenith', 'glint', 'sunShown'].map(n => [n, gl.getUniformLocation(p, n)]));
  }
  load(buffer, material = 'color') {
    this.silhouette = material === 'silhouette';
    buffer = assemblyNative(buffer);
    const d = new DataView(buffer), magic = String.fromCharCode(...new Uint8Array(buffer, 0, 4));
    if (magic !== 'M3DM' || d.getUint16(4, true) !== 1 || d.getUint16(6, true) !== 0) throw Error('not a native model');
    const count = d.getUint32(8, true), length = d.getUint32(12, true), start = 16 + Math.ceil(length / 4) * 4;
    if (count < 1 || start + count * 52 !== buffer.byteLength) throw Error('native model size mismatch');
    const data = new Float32Array(count * 3 * 12), low = [Infinity, Infinity, Infinity], high = [-Infinity, -Infinity, -Infinity];
    for (let i = 0; i < count; i++) {
      const at = start + i * 52, flags = d.getUint32(at, true), points = [];
      for (let j = 0; j < 3; j++) { const k = at + 4 + j * 16; points.push([d.getFloat32(k, true), d.getFloat32(k + 4, true), d.getFloat32(k + 8, true)]); }
      const u = points[1].map((x, k) => x - points[0][k]), v = points[2].map((x, k) => x - points[0][k]), normal = unit(cross(u, v));
      for (let j = 0; j < 3; j++) {
        const k = (i * 3 + j) * 12, color = d.getUint32(at + 4 + j * 16 + 12, true);
        data.set(points[j], k); data.set(normal, k + 3);
        data.set([color & 255, (color >>> 8) & 255, (color >>> 16) & 255].map(x => x / 255), k + 6); data[k + 9] = (color >>> 24) / 255; data[k + 10] = material === 'color' ? flags & 1 : 0;
        data[k + 11] = material !== 'color' ? 0 : (flags & 2) ? 1 : (flags & 4) ? 2 : 0;
        if(material === 'clay') data.set([0.827,0.831,0.855,1],k+6);
        if(material === 'silhouette') data.set([0.149,0.173,0.341,1],k+6);
        for (let c = 0; c < 3; c++) { low[c] = Math.min(low[c], points[j][c]); high[c] = Math.max(high[c], points[j][c]); }
      }
    }
    this.count = count * 3; this.bounds = {low, high};
    this.centre = low.map((x, i) => (x + high[i]) / 2); this.extent = low.map((x, i) => (high[i] - x) / 2);
    const gl = this.gl; gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer); gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
    return count;
  }
  render(view = 'isometric', {width = 768, height = 540, zoom = 1, vector, time = 'day', lineColour = [0.184, 0.427, 0.71], features = 0} = {}) {
    if (!this.count) return;
    const gl = this.gl, light = this.lighting[time];
    const direction = unit(vector || directions[view] || directions.isometric), reference = Math.abs(direction[2]) > 0.99 ? [0, 1, 0] : [0, 0, 1];
    const right = unit(cross(reference, direction)), up = unit(cross(direction, right)), aspect = width / height;
    const projected = axis => this.extent.reduce((s, v, i) => s + Math.abs(axis[i]) * v, 0);
    const radius = Math.max(projected(up), projected(right) / aspect, 0.1) * 1.14 / zoom, depth = Math.max(...this.extent) * 3 + 1;
    this.canvas.width = width; this.canvas.height = height; gl.viewport(0, 0, width, height);
    gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.enable(gl.DEPTH_TEST); gl.enable(gl.CULL_FACE); gl.cullFace(gl.BACK); gl.frontFace(gl.CCW);
    gl.useProgram(this.program); gl.bindVertexArray(this.vao);
    const u = this.uniforms;
    for (const [name, value] of Object.entries({centre: this.centre, right, up, direction})) gl.uniform3fv(u[name], value);
    for (const [name, value] of Object.entries({radius, aspect, depth})) gl.uniform1f(u[name], value);
    const [sx, sy, sz] = light.sunDirection;  // world (east, up, south) -> model (front, left, up)
    gl.uniform3fv(u.sunModel, unit([sx, -sz, sy]));
    gl.uniform3fv(u.sunLight, light.sunLight); gl.uniform3fv(u.skyLight, light.skyLight); gl.uniform3fv(u.lampGlow, light.lampGlow);
    gl.uniform3fv(u.lineColour, lineColour); gl.uniform1f(u.lights, light.lights); gl.uniform1i(u.features, features); gl.uniform1i(u.silhouette,this.silhouette ? 1 : 0);
    // Decision 450: the eye's way and the sky the glass mirrors, in the model's space (+z up).
    gl.uniform3fv(u.toEye, direction); gl.uniform3fv(u.horizon, light.fogColour || [0.8, 0.85, 0.9]); gl.uniform3fv(u.zenith, light.zenith || [0.4, 0.6, 0.9]);
    gl.uniform3fv(u.glint, light.glint || [1, 1, 1]); gl.uniform1f(u.sunShown, light.sunShown ?? 1);
    gl.drawArrays(gl.TRIANGLES, 0, this.count); gl.finish();
    if (gl.getError() !== gl.NO_ERROR) throw Error('WebGL draw failed');
  }
  png() { return this.canvas.toDataURL('image/png'); }
}
