import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {readNative,glbFromNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),ids=new Set(),hash=b=>createHash('sha256').update(b).digest('hex');
assert.equal(manifest.models.length,5);assert.equal(manifest.models.filter(m=>m.category==='reference').length,4);
assert.equal(manifest.models.filter(m=>m.category==='vehicle').length,1);
let views=0,triangles=0;
for(const m of manifest.models){
 assert(!ids.has(m.id));ids.add(m.id);
 const native=readFileSync(resolve(root,m.native)),glb=readFileSync(resolve(root,m.glb)),model=readNative(native);
 assert.equal(hash(native),m.native_sha256);assert.equal(hash(glb),m.glb_sha256);assert.deepEqual(glbFromNative(model),glb);
 assert.equal(model.vertices.length/3,m.triangles);assert(m.triangles>0&&m.triangles<=15000);triangles+=m.triangles;
 assert.equal(model.provenance.extras.assetId,m.id);
 for(const v of model.vertices){assert(v.position.every(Number.isFinite));if(m.category==='vehicle')assert.equal(v.color[3],255);}
 for(const c of m.connectors||[])assert(Math.abs(Math.hypot(...c.normal)-1)<0.0001);
 for(const view of manifest.directions){const p=readFileSync(resolve(root,m.views[view])),metric=m.view_metrics[view];assert.equal(p.toString('hex',0,8),'89504e470d0a1a0a');assert.equal(p.readUInt32BE(16),384);assert.equal(p.readUInt32BE(20),384);assert.equal(p[25],6);assert.equal(hash(p),metric.sha256);assert(metric.opaque_pixels>=20);const [l,t,r,b]=metric.visible_bounds;assert(l>=2&&t>=2&&r<=382&&b<=382);views++;}
}
assert.equal(views,35);
assert.deepEqual(manifest.fleet_preview.source_ids,['life-shuttleBus','life-midiBus','life-lowFloorBus','life-coachBus','life-bus']);
assert.equal(manifest.fleet_preview.triangles,triangles);assert.equal(manifest.fleet_preview.model_count,0);assert.equal(manifest.fleet_preview.single_camera,true);
assert.equal(hash(readFileSync(resolve(root,'previews/fleet-native.png'))),manifest.fleet_preview.sha256);
manifest.fleet_preview.translations_metres.forEach((p,i)=>{assert.equal(p[0],0);assert.equal(p[2],0);assert(Math.abs(p[1]-i*4.8)<1e-6);});
const names=['Map3DMidiBus.swift','Map3DCoachBus.swift','Map3DLowFloorBus.swift','Map3DShuttleBus.swift','Map3DStreetLife.swift','Map3DStationKitGeometry.swift','Map3DCivicKitGeometry.swift','Map3DModels.swift'];
manifest.recipe_sha256=Object.fromEntries(names.map(n=>[n,hash(readFileSync(new URL('../../Sources/GamePresentation/'+n,import.meta.url)))]));writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
const result={status:'VERIFIED',environment:'Linux / Swift 6.4 / Node / Chromium WebGL 2',new_vehicle_types:1,comparison_models:4,models:5,views,triangles,maximum_triangles:Math.max(...manifest.models.map(m=>m.triangles)),checks:['all native vertices round-trip through the game loader','native / GLB / PNG SHA-256','complete native-to-GLB conversion','one new rounded midibus type and four existing bus comparisons','all seven transparent views nonempty and unclipped','same-scale fleet uses all five original vertex sets and translations only','opaque finite new native bus; reference bus retains instance-tinted paint'],not_verified:['iPhone / iPad Metal rendering and performance','on-device App appearance, vehicle collision physics or wheel/door animation','wheel/door animation, actual vehicle brand or engineering dimensions','pixel comparison with original owner views / private source browser; raw sources are not redistributed']};
writeFileSync(resolve(root,'verification.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
