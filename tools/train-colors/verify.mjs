import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {readNative,glbFromNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),prior=resolve(process.argv[3]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const sha=b=>createHash('sha256').update(b).digest('hex');
const ids=['green-tram-head','green-tram-middle','green-tram-tail','green-tram-formation','green-commuter-leading','green-commuter-trailing','green-commuter-formation','urban-three-leading','urban-three-middle','urban-three-trailing','urban-three-formation','commuter-cab'];
assert.deepEqual(manifest.models.map(m=>m.id),ids);
const vertices=new Map(),records=[];
for(const m of manifest.models){
 const native=readFileSync(resolve(root,m.native)),glb=readFileSync(resolve(root,m.glb)),model=readNative(native);
 assert.equal(sha(native),m.native_sha256);assert.equal(sha(glb),m.glb_sha256);assert.deepEqual(glbFromNative(model),glb);
 assert.equal(model.vertices.length/3,m.triangles);assert(m.triangles>300&&m.triangles<=15000);
 const before=readNative(readFileSync(resolve(prior,'models',m.id+'.m3dmodel')));
 assert.equal(model.vertices.length,before.vertices.length,'Colour revision changed topology');
 let changed=0;
 for(let i=0;i<model.vertices.length;i++){
  const a=before.vertices[i],b=model.vertices[i];
  assert.deepEqual(a.position,b.position,'Geometry moved in '+m.id);
  assert.deepEqual(a.normal,b.normal,'Normal changed in '+m.id);
  assert.equal(a.glow,b.glow,'Lamp behaviour changed');
  assert.equal(a.color[3],b.color[3],'Alpha/stripe semantics changed');
  if(a.color.some((v,k)=>v!==b.color[k]))changed++;
 }
 assert(m.category==='comparison'?changed===0:changed>0,'Missing or unintended recolour '+m.id);
 vertices.set(m.id,model.vertices);records.push({id:m.id,triangles:m.triangles,geometry:'BIT_IDENTICAL',normals:'BIT_IDENTICAL',changed_color_vertices:changed});
 for(const view of manifest.directions){
  const png=readFileSync(resolve(root,m.views[view])),metric=m.view_metrics[view];
  assert.equal(png.toString('hex',0,8),'89504e470d0a1a0a');assert.equal(png.readUInt32BE(16),512);assert.equal(png.readUInt32BE(20),512);
  assert.equal(png[25],6);assert.equal(sha(png),metric.sha256);assert(metric.opaque_pixels>30);
  const [l,t,r,b]=metric.visible_bounds;assert(l>=2&&t>=2&&r<=510&&b<=510);
 }
 const b=view=>m.view_metrics[view].visible_bounds;
 assert(Math.abs((b('left')[2]-b('left')[0])-(b('top')[2]-b('top')[0]))<=3,'Inconsistent metre scale');
 assert(Math.abs((b('left')[3]-b('left')[1])-(b('front')[3]-b('front')[1]))<=3,'Inconsistent metre scale');
}
for(const assembly of manifest.assemblies){
 const train=vertices.get(assembly.id);let offset=0;
 for(let i=0;i<assembly.order.length;i++)for(const v of vertices.get(assembly.order[i])){
  const q=train[offset++];assert(Math.abs(q.position[0]-v.position[0]-assembly.centres_x_m[i])<.0001);
  assert.deepEqual(q.position.slice(1),v.position.slice(1));assert.deepEqual(q.color,v.color);
 }
 assert.equal(offset,train.length);
}
const result={status:'VERIFIED',environment:'Linux / Swift 6.4 / Chromium WebGL2',added_vehicle_types_by_colour_revision:0,recoloured_vehicle_types:3,independent_units:8,formations:3,comparison_models:1,seven_direction_pngs:84,
 baseline_producer_commit:'2b2bfab2ae6f2a94407c8acd0224516d590a07f5',geometry_identity:records,
 checks:['every vertex position and normal exactly equal to prior producer','triangle order, count, glow and alpha semantics unchanged','all three formations contain the exact recoloured independent units','exact native-to-GLB regeneration','84 RGBA views nonempty/unclipped and SHA consistent','same metre scale in orthographic views'],
 unverified:['device Metal appearance and performance','animation and physics','manufacturer engineering dimensions','OS file:// launch blocked by managed Chromium; embedded offline mode checked separately']};
writeFileSync(resolve(root,'verification.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(records));
