import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {readNative,glbFromNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const sha=b=>createHash('sha256').update(b).digest('hex');
const ids=['temu2000-leading','temu2000-tema','temu2000-tep','temu2000-temb','temu2000-trailing','temu2000-formation','temu1000-leading'];
assert.deepEqual(manifest.models.map(m=>m.id),ids);
const models=new Map();
for(const m of manifest.models){
 const bytes=readFileSync(resolve(root,m.native)),glb=readFileSync(resolve(root,m.glb)),native=readNative(bytes);
 assert.equal(sha(bytes),m.native_sha256);assert.equal(sha(glb),m.glb_sha256);
 assert.deepEqual(glbFromNative(native),glb);
 assert.equal(native.vertices.length/3,m.triangles);assert(m.triangles<=15000);
 assert(native.vertices.every(v=>v.position.every(Number.isFinite)&&v.normal.every(Number.isFinite)));
 assert(native.vertices.every(v=>Math.abs(Math.hypot(...v.normal)-1)<0.001),'native triangle normals must be unit length');
 if(m.category!=='comparison')assert(Math.abs(m.minimum[2])<0.012);
 for(const view of manifest.directions){const png=readFileSync(resolve(root,m.views[view])),metric=m.view_metrics[view];assert.equal(png.toString('hex',0,8),'89504e470d0a1a0a');assert.equal(sha(png),metric.sha256);const [l,t,r,b]=metric.visible_bounds;assert(l>=2&&t>=2&&r<=510&&b<=510);}
 models.set(m.id,native.vertices);
}
const formation=models.get('temu2000-formation');let cursor=0;
for(const place of manifest.assembly.placements){
 const part=models.get('temu2000-'+place.unit);
 const radians=place.rotation_deg*Math.PI/180,c=Math.cos(radians),s=Math.sin(radians);
 for(const v of part){
  const q=formation[cursor++],expected=[c*v.position[0]+s*v.position[1]+place.x_m,-s*v.position[0]+c*v.position[1],v.position[2]];
  const normal=[c*v.normal[0]+s*v.normal[1],-s*v.normal[0]+c*v.normal[1],v.normal[2]];
  assert(q.position.every((value,k)=>Math.abs(value-expected[k])<0.0002),'assembly placement/rotation position');
  assert(q.normal.every((value,k)=>Math.abs(value-normal[k])<0.0003),'assembly rotation normal');
  assert.deepEqual(q.color,v.color);
 }
}
assert.equal(cursor,formation.length);
assert.equal(manifest.assembly.placements.length,8);
assert.deepEqual(manifest.assembly.placements.map(p=>p.unit),['trailing','tema','tep','temb','temb','tep','tema','leading']);
assert.equal(manifest.assembly.placements.filter(p=>p.unit==='tep').length,2);
assert.deepEqual(manifest.assembly.placements.map(p=>Math.round(p.rotation_deg)),[0,0,0,0,0,180,0,0]);
assert(Math.abs(manifest.assembly.coupled_length_m-168.39)<0.001);
const intermediate=models.get('temu2000-tema'),head=models.get('temu2000-leading');
assert(head.length>intermediate.length);
assert(manifest.models[0].maximum[2]>3.5);
assert(manifest.models[2].maximum[2]>manifest.models[1].maximum[2]+0.2);
manifest.recipe_sha256=sha(readFileSync(new URL('../../Sources/GamePresentation/Map3DTEMU2000.swift',import.meta.url)));
writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
writeFileSync(resolve(root,'verification.json'),JSON.stringify({status:'VERIFIED',platform:'Linux Swift 6.4 Chromium WebGL2',checks:['native readback, nondegenerate unit normals and matching GLB','all eight final units match formation after manifest translations and rotation, including triangle normals','49 transparent views uncut and hashed','rail datum and raised TEP equipment bounds'],unverified:['iOS Metal','animation','complete collision and device performance','proportion-estimated dimensions']},null,2)+'\n');
console.log('VERIFIED native/GLB/assembly/PNG metrics');
