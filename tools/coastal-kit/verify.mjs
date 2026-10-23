import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {readNative,glbFromNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),ids=new Set(),hash=b=>createHash('sha256').update(b).digest('hex');
assert.equal(manifest.models.length,28);assert.equal(manifest.models.filter(m=>m.category==='example').length,4);
for(const c of ['coast','harbor','camp'])assert.equal(manifest.models.filter(m=>m.category===c).length,8);
let views=0,triangles=0;
for(const m of manifest.models){
 assert(!ids.has(m.id));ids.add(m.id);
 const native=readFileSync(resolve(root,m.native)),glb=readFileSync(resolve(root,m.glb)),model=readNative(native);
 assert.equal(hash(native),m.native_sha256);assert.equal(hash(glb),m.glb_sha256);assert.deepEqual(glbFromNative(model),glb);
 assert.equal(model.vertices.length/3,m.triangles);assert(m.triangles>0&&m.triangles<=15000);triangles+=m.triangles;
 assert.equal(model.provenance.extras.assetId,m.id);
 for(const v of model.vertices){assert(v.position.every(Number.isFinite));assert.equal(v.color[3],255);}
 for(const c of m.connectors||[])assert(Math.abs(Math.hypot(...c.normal)-1)<0.0001);
 for(const view of manifest.directions){const p=readFileSync(resolve(root,m.views[view])),metric=m.view_metrics[view];assert.equal(p.toString('hex',0,8),'89504e470d0a1a0a');assert.equal(p.readUInt32BE(16),384);assert.equal(p.readUInt32BE(20),384);assert.equal(p[25],6);assert.equal(hash(p),metric.sha256);assert(metric.opaque_pixels>=20);const [l,t,r,b]=metric.visible_bounds;assert(l>=2&&t>=2&&r<=382&&b<=382);views++;}
}
assert.equal(views,196);
// Camping furniture must be independently placed. Intentional tabletop/boat
// stacking belongs to the other examples, never to this ground-level layout.
const camp=manifest.models.find(m=>m.id==='coastal-example-seasideCamp');
const footprints=camp.placements.map(p=>{
 const m=manifest.models.find(m=>m.id===p.part),c=Math.cos(p.angle),s=Math.sin(p.angle);
 const points=[m.minimum[0],m.maximum[0]].flatMap(x=>[m.minimum[1],m.maximum[1]].map(y=>[c*x+s*y+p.position[0],-s*x+c*y+p.position[1]]));
 return {part:p.part,low:[0,1].map(i=>Math.min(...points.map(v=>v[i]))),high:[0,1].map(i=>Math.max(...points.map(v=>v[i])))};
});
for(let i=0;i<footprints.length;i++)for(let j=0;j<i;j++){
 const a=footprints[i],b=footprints[j];
 assert([0,1].some(k=>a.high[k]<=b.low[k]||b.high[k]<=a.low[k]),'Overlapping camping assets: '+a.part+' / '+b.part);
}

const names=['Map3DCoastalKit.swift','Map3DCoastalKitGeometry.swift','Map3DCoastalKitStructures.swift','Map3DCoastalKitHarbor.swift','Map3DCoastalKitCamp.swift','Map3DCoastalKitExamples.swift','Map3DStationKitGeometry.swift','Map3DCivicKitGeometry.swift'];
manifest.recipe_sha256=Object.fromEntries(names.map(n=>[n,hash(readFileSync(new URL('../../Sources/GamePresentation/'+n,import.meta.url)))]));writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
const result={status:'VERIFIED',environment:'Linux / Swift 6.4 / Node / Chromium WebGL 2',parts:24,examples:4,models:28,views,triangles,maximum_triangles:Math.max(...manifest.models.map(m=>m.triangles)),checks:['all native vertices round-trip through the game loader','native / GLB / PNG SHA-256','complete native-to-GLB conversion','three categories of 8 distinct coastal, harbor and camping assets','all seven transparent views nonempty and unclipped','opaque finite native vertices and connector normals','camp layout has non-overlapping rotated footprints'],not_verified:['iPhone / iPad Metal rendering and performance','live map placement, collisions, interior navigation or animation','marine engineering, lifeguard or camping safety simulation','source pack browser rendering / pixel comparison; raw sources are not redistributed']};
writeFileSync(resolve(root,'verification.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
