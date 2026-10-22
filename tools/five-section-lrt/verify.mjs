import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {readNative,glbFromNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),sha=b=>createHash('sha256').update(b).digest('hex');
assert.equal(manifest.models.length,8);
const vertices=new Map();
for(const m of manifest.models){
 const native=readFileSync(resolve(root,m.native)),glb=readFileSync(resolve(root,m.glb)),model=readNative(native);
 assert.equal(sha(native),m.native_sha256);assert.equal(sha(glb),m.glb_sha256);assert.deepEqual(glbFromNative(model),glb);
 assert.equal(model.vertices.length/3,m.triangles);assert(m.triangles>100&&m.triangles<=15000);
 assert.equal(model.provenance.extras.assetId,m.id);assert(model.vertices.every(v=>v.position.every(Number.isFinite)));
 vertices.set(m.id,model.vertices);
 for(const view of manifest.directions){
  const png=readFileSync(resolve(root,m.views[view])),metric=m.view_metrics[view];
  assert.equal(png.readUInt32BE(16),512);assert.equal(png.readUInt32BE(20),512);assert.equal(png[25],6);assert.equal(sha(png),metric.sha256);
  const [l,t,r,b]=metric.visible_bounds;assert(metric.opaque_pixels>30&&l>=2&&t>=2&&r<=510&&b<=510);
 }
 const b=view=>m.view_metrics[view].visible_bounds;
 assert(Math.abs((b('left')[2]-b('left')[0])-(b('top')[2]-b('top')[0]))<=3,m.id+' longitudinal scale');
 assert(Math.abs((b('left')[3]-b('left')[1])-(b('front')[3]-b('front')[1]))<=3,m.id+' vertical scale');
}
const units=manifest.models.filter(m=>m.category==='section'),formation=manifest.models.find(m=>m.category==='formation');
assert.equal(units.length,5);assert.equal(new Set(units.map(m=>m.metres_per_pixel)).size,1);
let index=0;
for(const [j,m] of units.entries())for(const v of vertices.get(m.id)){
 const q=vertices.get(formation.id)[index++],dx=manifest.assembly.centres_x_m[j];
 assert(Math.abs(q.position[0]-v.position[0]-dx)<0.0001);assert(Math.abs(q.position[1]-v.position[1])<0.0001);assert(Math.abs(q.position[2]-v.position[2])<0.0001);assert.deepEqual(q.color,v.color);
}
assert.equal(index,vertices.get(formation.id).length);
assert(Math.abs(formation.maximum[0]-formation.minimum[0]-34)<0.001);
assert(Math.abs(formation.minimum[2])<0.001);
// Measure actual tyre clusters rather than accepting an axle-count constant.
const wheelColors=new Map();
for(const v of vertices.get('green-commuter-leading'))if(v.position[2]<.19&&Math.abs(v.position[1])>1){const k=v.color.join(',');wheelColors.set(k,(wheelColors.get(k)||0)+1);}
const wheelColor=[...wheelColors].sort((a,b)=>b[1]-a[1])[0][0];
const tyre=vertices.get(formation.id).filter(v=>v.color.join(',')===wheelColor&&v.position[2]<.19&&Math.abs(v.position[1])>.9);
const xs=tyre.map(v=>v.position[0]).sort((a,b)=>a-b);let clusters=0,last=-Infinity;
for(const x of xs){if(x-last>.17)clusters++;last=x;}assert.equal(clusters,6,'actual axle geometry');
manifest.recipe_sha256=sha(readFileSync(new URL('../../Sources/GamePresentation/Map3DFiveSectionLRT.swift',import.meta.url)));
writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
const result={status:'VERIFIED',environment:'Linux / Swift6.4 / Chromium WebGL2',new_models:6,comparison_models:2,views:56,
 checks:['native readback / exact native-to-GLB bytes','all five units reappear translated without rotation','actual six axle clusters','rail datum at wheel bottoms','seven-direction RGBA bounds / same metre scales'],
 unverified:['device Metal / performance','animation / physics / operational assignment','engineering dimensions','hidden wheel arrangement: three bogies is a documented assumption','pixel reference overlays: five inline images visually inspected, unavailable as local files']};
writeFileSync(resolve(root,'verification.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
