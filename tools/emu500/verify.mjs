import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readNative,glbFromNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),m=JSON.parse(readFileSync(resolve(root,'manifest.json'))),parts=new Map();
const sha=b=>createHash('sha256').update(b).digest('hex');
for(const a of m.models){
 const bytes=readFileSync(resolve(root,a.native)),g=readFileSync(resolve(root,a.glb)),n=readNative(bytes);
 assert.equal(sha(bytes),a.native_sha256);assert.deepEqual(glbFromNative(n),g);assert.equal(n.vertices.length/3,a.triangles);
 assert(a.triangles<=15000);assert(n.vertices.every(v=>v.position.every(Number.isFinite)&&Math.abs(Math.hypot(...v.normal)-1)<0.001));
 if(a.category!=='comparison')assert(Math.abs(a.minimum[2])<0.001);
 for(const v of m.directions){const metric=a.view_metrics[v];assert.equal(sha(readFileSync(resolve(root,a.views[v]))),metric.sha256);const [l,t,r,b]=metric.visible_bounds;assert(l>=2&&t>=2&&r<=510&&b<=510);}
 parts.set(a.id,n.vertices);
}
const train=parts.get('emu500-formation');let cursor=0;
for(const p of m.assembly.placements){
 const c=Math.cos(p.rotation_deg*Math.PI/180),s=Math.sin(p.rotation_deg*Math.PI/180);
 for(const v of parts.get('emu500-'+p.unit)){
  const q=train[cursor++],a=[c*v.position[0]+s*v.position[1]+p.x_m,-s*v.position[0]+c*v.position[1],v.position[2]];
  assert(q.position.every((x,k)=>Math.abs(x-a[k])<0.0002));assert.deepEqual(q.color,v.color);
 }
}
assert.equal(cursor,train.length);
assert.deepEqual(m.assembly.placements.map(p=>p.unit),['emc','ep','et','em']);
assert.deepEqual(m.assembly.placements.map(p=>Math.round(p.rotation_deg)),[0,0,0,180]);
writeFileSync(resolve(root,'verification.json'),JSON.stringify({status:'VERIFIED',checks:['native readback in Swift exporter','GLB exact conversion, finite unit normals','all assembly vertices and colors','PNG SHA and margins'],unverified:['device Metal','performance','animation','complete collision']},null,2));
console.log('VERIFIED native, GLB, assembly and PNG metrics');
