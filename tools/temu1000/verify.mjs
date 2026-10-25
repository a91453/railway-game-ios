import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {readNative,glbFromNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const sha=b=>createHash('sha256').update(b).digest('hex');
const ids=['temu1000-leading','temu1000-middle','temu1000-pantograph','temu1000-trailing','temu1000-formation','commuter-cab'];
assert.deepEqual(manifest.models.map(m=>m.id),ids);
const models=new Map();
for(const m of manifest.models){
 const bytes=readFileSync(resolve(root,m.native)),glb=readFileSync(resolve(root,m.glb)),native=readNative(bytes);
 assert.equal(sha(bytes),m.native_sha256);assert.equal(sha(glb),m.glb_sha256);
 assert.deepEqual(glbFromNative(native),glb);
 assert.equal(native.vertices.length/3,m.triangles);assert(m.triangles<=15000);
 assert(native.vertices.every(v=>v.position.every(Number.isFinite)&&v.normal.every(Number.isFinite)));
 if(m.category!=='comparison')assert(Math.abs(m.minimum[2])<0.012);
 for(const view of manifest.directions){const png=readFileSync(resolve(root,m.views[view])),metric=m.view_metrics[view];assert.equal(png.toString('hex',0,8),'89504e470d0a1a0a');assert.equal(sha(png),metric.sha256);const [l,t,r,b]=metric.visible_bounds;assert(l>=2&&t>=2&&r<=510&&b<=510);}
 models.set(m.id,native.vertices);
}
const formation=models.get('temu1000-formation');let cursor=0;
for(const place of manifest.assembly.placements){
 const part=models.get('temu1000-'+place.unit);
 for(const v of part){const q=formation[cursor++];assert(Math.abs(q.position[0]-v.position[0]-place.x_m)<0.0002);assert(Math.abs(q.position[1]-v.position[1])<0.0002);assert(Math.abs(q.position[2]-v.position[2])<0.0002);assert.deepEqual(q.color,v.color);}
}
assert.equal(cursor,formation.length);
assert.equal(manifest.assembly.placements.length,8);
assert.equal(manifest.assembly.placements.filter(p=>p.unit==='pantograph').length,2);
const middle=models.get('temu1000-middle'),head=models.get('temu1000-leading');
assert(head.length>middle.length);
assert(manifest.models[0].maximum[2]>3.7);
assert(manifest.models[2].maximum[2]>4.4);
manifest.recipe_sha256=sha(readFileSync(new URL('../../Sources/GamePresentation/Map3DTEMU1000.swift',import.meta.url)));
writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
writeFileSync(resolve(root,'verification.json'),JSON.stringify({status:'VERIFIED',platform:'Linux Swift 6.4 Chromium WebGL2',checks:['native readback and matching GLB','all eight final units match formation after translation','42 transparent views uncut and hashed','rail datum and pantograph bounds'],unverified:['iOS Metal','animation','complete collision and device performance','engineering dimensions']},null,2)+'\n');
console.log('VERIFIED native/GLB/assembly/PNG metrics');
