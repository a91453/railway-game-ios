import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {readNative,glbFromNative} from './package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),ids=new Set();
const geo=JSON.parse(readFileSync(new URL('../../RailwayGameApp/Resources/RealRailways/track_stations.geojson',import.meta.url)));
const expected=new Set(geo.features.map(f=>f.properties.sys+'|'+f.properties.name));
const stations=manifest.models.filter(m=>m.category==='station');
assert.deepEqual(new Set(stations.map(m=>m.system+'|'+m.name)),expected);
assert.equal(stations.length,manifest.station_count);assert.equal(manifest.models.filter(m=>m.category.endsWith('-part')).length,manifest.part_count);
let triangles=0,views=0;
for(const record of manifest.models){
 assert(!ids.has(record.id));ids.add(record.id);
 const native=readFileSync(resolve(root,record.native)),glb=readFileSync(resolve(root,record.glb)),model=readNative(native);
 assert.equal(createHash('sha256').update(native).digest('hex'),record.native_sha256);
 assert.equal(createHash('sha256').update(glb).digest('hex'),record.glb_sha256);
 assert.deepEqual(glbFromNative(model),glb,'GLB preserves every native position, normal, colour and glow flag');
 assert.equal(model.vertices.length/3,record.triangles);assert(record.triangles>0&&record.triangles<=15000);triangles+=record.triangles;
 assert.equal(model.provenance.extras.assetId,record.id);
 for(const vertex of model.vertices){assert(vertex.position.every(Number.isFinite));assert.equal(vertex.color[3],255);}
 for(const v of manifest.directions){
  const png=readFileSync(resolve(root,record.views[v])),metric=record.view_metrics[v];
  assert.equal(png.toString('hex',0,8),'89504e470d0a1a0a');assert.equal(png.readUInt32BE(16),384);assert.equal(png.readUInt32BE(20),384);assert.equal(png[25],6);
  assert.equal(createHash('sha256').update(png).digest('hex'),metric.sha256);assert(metric.opaque_pixels>=20);
  const [l,t,r,b]=metric.visible_bounds;assert(l>=2&&t>=2&&r<=382&&b<=382);views++;
 }
 if(record.category==='station'){assert.equal(record.planned,record.system==='sanying');assert.equal(record.realBuildingHeightM,null);assert.equal(record.railElevationM,null);}
 if(record.connectors)for(const c of record.connectors){assert(c.position.every(Number.isFinite));assert(Math.abs(Math.hypot(...c.normal)-1)<0.0001);}
}
assert.equal(manifest.model_count,manifest.models.length);assert.equal(views,manifest.models.length*7);
const sourceFiles=['Map3DStationKit.swift','Map3DStationKitBuildings.swift','Map3DStationKitCatalog.swift','Map3DStationKitGeometry.swift','Map3DStationKitPartGeometry.swift','Map3DStationKitParts.swift'];
manifest.recipe_sha256=Object.fromEntries(sourceFiles.map(name=>[name,createHash('sha256').update(readFileSync(new URL('../../Sources/GamePresentation/'+name,import.meta.url))).digest('hex')]));
writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
const result={status:'VERIFIED',environment:'Linux / Swift 6.4 / Node / Chromium WebGL 2',models:manifest.models.length,stations:stations.length,parts:manifest.part_count,views,triangles,maximum_triangles:Math.max(...manifest.models.map(m=>m.triangles)),landmarks:stations.filter(m=>m.landmark).length,planned_stations:stations.filter(m=>m.planned).length,checks:['exact coverage of bundled (system, name) station records','native and GLB SHA-256','complete native-to-GLB conversion','opaque finite native vertices','all seven RGBA views nonempty and unclipped','connector normalisation','planned routes and illustrative heights labelled'],not_verified:['iPhone / iPad Metal rendering and performance','live map selection, placement and alignment','surveyed station dimensions, interior layout or operating status beyond the source catalog']};
writeFileSync(resolve(root,'verification.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result));
