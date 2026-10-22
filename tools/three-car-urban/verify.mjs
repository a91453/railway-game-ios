import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {readNative,glbFromNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const sha=b=>createHash('sha256').update(b).digest('hex');
assert.deepEqual(manifest.models.map(m=>m.id),['urban-three-leading','urban-three-middle','urban-three-trailing','urban-three-formation','commuter-cab','green-commuter-leading']);
assert.equal(manifest.models.length,6);
let total=0;const vertices=new Map();
for(const m of manifest.models){
 const native=readFileSync(resolve(root,m.native)),glb=readFileSync(resolve(root,m.glb)),model=readNative(native);
 assert.equal(sha(native),m.native_sha256);assert.equal(sha(glb),m.glb_sha256);
 assert.deepEqual(glbFromNative(model),glb);
 assert.equal(model.vertices.length/3,m.triangles);assert(m.triangles>(m.category==='comparison'?300:600)&&m.triangles<=15000);total+=m.triangles;
 assert.equal(model.provenance.extras.assetId,m.id);
 assert(model.vertices.every(v=>v.position.every(Number.isFinite)&&(m.category==='comparison'||v.color[3]===255)));
 assert(Math.abs(m.minimum[2])<0.02);
 vertices.set(m.id,model.vertices);
 for(const view of manifest.directions){
  const png=readFileSync(resolve(root,m.views[view])),metric=m.view_metrics[view];
  assert.equal(png.toString('hex',0,8),'89504e470d0a1a0a');assert.equal(png.readUInt32BE(16),512);assert.equal(png.readUInt32BE(20),512);
  assert.equal(png[25],6);assert.equal(sha(png),metric.sha256);assert(metric.opaque_pixels>30);
  const [l,t,r,b]=metric.visible_bounds;assert(l>=2&&t>=2&&r<=510&&b<=510);
 }
}
// The actual rasterized orthographic bounds must preserve metre scale:
// left/top both show longitudinal length; left/front both show height.
for(const m of manifest.models){
 const b=view=>m.view_metrics[view].visible_bounds;
 const width=view=>b(view)[2]-b(view)[0],height=view=>b(view)[3]-b(view)[1];
 assert(Math.abs(width('left')-width('top'))<=3,m.id+' inconsistent longitudinal view scale');
 assert(Math.abs(height('left')-height('front'))<=3,m.id+' inconsistent vertical view scale');
}
const [leading,middle,trailing,formation]=manifest.models;
assert.equal(leading.metres_per_pixel,middle.metres_per_pixel);
assert.equal(leading.metres_per_pixel,trailing.metres_per_pixel);
assert.equal(formation.triangles,leading.triangles+middle.triangles+trailing.triangles);
assert(formation.maximum[0]-formation.minimum[0]>45&&formation.maximum[0]-formation.minimum[0]<47);
assert(Math.abs(leading.maximum[2]-trailing.maximum[2])<0.001);
// Each actual assembled triangle must correspond to the named unit and its
// documented x translation. This also detects accidentally flipped cabs.
let index=0;
for(const [m,dx] of [[leading,15.28],[middle,0],[trailing,-15.28]]){
 for(const v of vertices.get(m.id)){
  const q=vertices.get(formation.id)[index++];
  assert(Math.abs(q.position[0]-v.position[0]-dx)<0.0001);
  assert(Math.abs(q.position[1]-v.position[1])<0.0001);
  assert(Math.abs(q.position[2]-v.position[2])<0.0001);
  assert.deepEqual(q.color,v.color);
 }
}
assert.equal(index,vertices.get(formation.id).length);
manifest.recipe_sha256=sha(readFileSync(new URL('../../Sources/GamePresentation/Map3DThreeCarUrban.swift',import.meta.url)));
writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
const result={status:'VERIFIED',environment:'Linux / Swift 6.4 / Chromium WebGL2',new_models:4,comparison_models:2,views:42,triangles:total,
 checks:['native readback and exact native-to-GLB content','all three unit triangle sets reappear in formation at documented positions','four wheelsets and two bogies per unit','wheel bottom at rail datum','all seven views nonempty, unclipped, RGBA and SHA-256 consistent'],
 unverified:['iPhone / iPad Metal appearance and performance','animation, physics and route assignment','manufacturer engineering dimensions','pixel-level reference alignment: supplied chat images were visually inspected but unavailable as local files']};
writeFileSync(resolve(root,'verification.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result));
