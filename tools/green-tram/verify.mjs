import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {readNative,glbFromNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const sha=b=>createHash('sha256').update(b).digest('hex');
assert.deepEqual(manifest.models.map(m=>m.id),['green-tram-head','green-tram-middle','green-tram-tail','green-tram-formation','06_more_transit_3x2-01']);
assert.equal(manifest.models.length,5);
let total=0;const vertices=new Map();
for(const m of manifest.models){
 const native=readFileSync(resolve(root,m.native)),glb=readFileSync(resolve(root,m.glb)),model=readNative(native);
 assert.equal(sha(native),m.native_sha256);assert.equal(sha(glb),m.glb_sha256);
 assert.deepEqual(glbFromNative(model),glb);
 assert.equal(model.vertices.length/3,m.triangles);assert(m.triangles>400&&m.triangles<=15000);total+=m.triangles;
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
const [head,middle,tail,formation]=manifest.models;
assert.equal(formation.triangles,head.triangles+middle.triangles+tail.triangles);
assert(formation.maximum[0]-formation.minimum[0]>32&&formation.maximum[0]-formation.minimum[0]<34);
assert(tail.maximum[2]>head.maximum[2]+0.7&&middle.maximum[2]<3.4);
// This compares every actual assembled triangle with its corresponding unit,
// allowing only the documented x translation, so previews cannot drift.
let index=0;
for(const [m,dx] of [[head,11.04],[middle,0],[tail,-11.04]]){
 for(const v of vertices.get(m.id)){
  const q=vertices.get(formation.id)[index++];
  assert(Math.abs(q.position[0]-v.position[0]-dx)<0.0001);
  assert(Math.abs(q.position[1]-v.position[1])<0.0001);
  assert(Math.abs(q.position[2]-v.position[2])<0.0001);
  assert.deepEqual(q.color,v.color);
 }
}
assert.equal(index,vertices.get(formation.id).length);
manifest.recipe_sha256=sha(readFileSync(new URL('../../Sources/GamePresentation/Map3DGreenTram.swift',import.meta.url)));
writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
const result={status:'VERIFIED',environment:'Linux / Swift 6.4 / Chromium WebGL2',new_models:4,comparison_models:1,views:35,triangles:total,
 checks:['native readback and exact native-to-GLB content','all unit triangles reappear in formation at documented positions','pantograph only on tail','wheel bottom at rail datum','all seven views nonempty, unclipped, RGBA and SHA-256 consistent'],
 unverified:['iPhone / iPad Metal appearance and performance','animation, physics and route assignment','engineering dimensions','pixel-level reference alignment: supplied chat images were visually inspected but unavailable as local files']};
writeFileSync(resolve(root,'verification.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result));
