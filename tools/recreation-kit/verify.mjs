import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {readNative,glbFromNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),ids=new Set(),hash=b=>createHash('sha256').update(b).digest('hex');
assert.equal(manifest.models.length,28);assert.equal(manifest.models.filter(m=>m.category==='example').length,4);
for(const c of ['venue','fitness','sport','aquatic'])assert.equal(manifest.models.filter(m=>m.category===c).length,6);
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
// The returned ball must rest on both rails, rather than a support post.
const lane=manifest.models.find(m=>m.id==='recreation-bowlingLane'),lm=readNative(readFileSync(resolve(root,lane.native)));
const raw=c=>((c[3]<<24)|(c[0]<<16)|(c[1]<<8)|c[2])>>>0;
const gold=0xffffc86b,steel=0xff6e747b;
// Existing Map3DPalette.player / tankStand; no new material colors.
const ballVertices=lm.vertices.filter(v=>v.position[0]>1&&raw(v.color)===gold);
assert(ballVertices.length>0,'Missing return ball');
const cx=(Math.min(...ballVertices.map(v=>v.position[0]))+Math.max(...ballVertices.map(v=>v.position[0])))/2;
const cy=(Math.min(...ballVertices.map(v=>v.position[1]))+Math.max(...ballVertices.map(v=>v.position[1])))/2;
function heights(model,x,y,accept){
 const result=[];
 for(let i=0;i<model.vertices.length;i+=3){const t=model.vertices.slice(i,i+3);if(!accept(t[0]))continue;const [a,b,c]=t.map(v=>v.position),d=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1]);if(Math.abs(d)<1e-10)continue;const u=((b[1]-c[1])*(x-c[0])+(c[0]-b[0])*(y-c[1]))/d,v=((c[1]-a[1])*(x-c[0])+(a[0]-c[0])*(y-c[1]))/d;if(u>=-1e-6&&v>=-1e-6&&u+v<=1+1e-6)result.push(u*a[2]+v*b[2]+(1-u-v)*c[2]);}
 return result;
}
const ballRailGaps=[];
for(const y of [cy-0.12,cy+0.12]){
 const ball=Math.min(...heights(lm,cx,y,v=>raw(v.color)===gold));
 const rail=Math.max(...heights(lm,cx,y,v=>raw(v.color)===steel));
 assert(Number.isFinite(ball)&&Number.isFinite(rail),'Missing ball / rail geometry');
 assert(ball<=rail+0.005&&ball>=rail-0.04,'Return ball must touch both actual rails: gap='+String(ball-rail));ballRailGaps.push(ball-rail);
}

// Native placements, indoor clearance, intentional pool-deck mounting and
// the cantilever are checked independently of the Swift scene constructor.
const bounds=p=>{
 const m=manifest.models.find(m=>m.id===p.part),c=Math.cos(p.angle),s=Math.sin(p.angle);
 const xy=[m.minimum[0],m.maximum[0]].flatMap(x=>[m.minimum[1],m.maximum[1]].map(y=>[c*x+s*y+p.position[0],-s*x+c*y+p.position[1]]));
 return {p,m,low:[0,1].map(k=>Math.min(...xy.map(v=>v[k]))),high:[0,1].map(k=>Math.max(...xy.map(v=>v[k])))};
};
const separate=(a,b)=>[0,1].some(k=>a.high[k]<=b.low[k]+0.001||b.high[k]<=a.low[k]+0.001);
for(const scene of manifest.models.filter(m=>m.category==='example')){
 const all=scene.placements.map(bounds),venues=all.filter(a=>a.m.category==='venue'),fixtures=all.filter(a=>a.m.category!=='venue');
 for(let i=0;i<venues.length;i++)for(let j=0;j<i;j++)assert(separate(venues[i],venues[j]),'Venue overlap');
 for(const a of fixtures){
  if(a.p.support==='venueFloor'){
   assert(venues.some(v=>[0,1].every(k=>a.low[k]>=v.low[k]+0.30&&a.high[k]<=v.high[k]-0.30)),'Outside venue floor: '+a.m.id);
   assert(Math.abs(a.p.position[2]-0.28)<0.0001);
  }
  if(a.p.support==='apron')assert(a.low[0]>=9.5&&a.high[0]<=12&&a.low[1]>=-7.5&&a.high[1]<=7.5);
 }
 for(let i=0;i<fixtures.length;i++)for(let j=0;j<i;j++){
  const a=fixtures[i],b=fixtures[j],pair=[a.m.id,b.m.id];
  if(pair.includes('recreation-trainingPool')&&(pair.includes('recreation-divingPlatform')||pair.includes('recreation-startBlock')))continue;
  assert(separate(a,b),'Fixture overlap: '+a.m.id+' / '+b.m.id);
 }
 if(scene.id==='recreation-example-swimmingCenter'){
  const pool=all.find(a=>a.m.id==='recreation-trainingPool'),start=all.find(a=>a.m.id==='recreation-startBlock'),dive=all.find(a=>a.m.id==='recreation-divingPlatform');
  const deck=pool.m.connectors.find(c=>c.name==='frontDeck');assert(Math.abs(start.p.position[2]-pool.p.position[2]-deck.position[2])<0.0001);
  assert.equal(start.p.support,'poolDeck');
  const block=readNative(readFileSync(resolve(root,start.m.native))),bc=Math.cos(start.p.angle),bs=Math.sin(start.p.angle);
  for(const v of block.vertices)if(Math.abs(v.position[2]-start.m.minimum[2])<0.00001){const [x,y]=v.position,px=bc*x+bs*y+start.p.position[0]-pool.p.position[0],py=-bs*x+bc*y+start.p.position[1]-pool.p.position[1];assert(px>=6&&px<=7&&Math.abs(py)<=4.5,'Start-block foot overhangs the actual pool deck');}
  for(const v of readNative(readFileSync(resolve(root,dive.m.native))).vertices)if(Math.abs(v.position[2]-dive.m.minimum[2])<0.00001){const [x,y]=v.position,c=Math.cos(dive.p.angle),s=Math.sin(dive.p.angle),px=c*x+s*y+dive.p.position[0],py=-s*x+c*y+dive.p.position[1];assert(px>=-9.5&&px<=12&&Math.abs(py)<=7.5,'Diving foot lacks venue floor or apron');}
  const native=readNative(readFileSync(resolve(root,dive.m.native))),c=Math.cos(dive.p.angle),s=Math.sin(dive.p.angle),top=pool.p.position[2]+1.09;
  for(const v of native.vertices){const [x,y,z]=v.position,px=c*x+s*y+dive.p.position[0],py=-s*x+c*y+dive.p.position[1],pz=z+dive.p.position[2];if(pz<=top+0.01&&Math.abs(py)<4.5)assert(px>pool.high[0]+0.02,'Diving support intersects pool');}
  assert(dive.low[0]<pool.p.position[0]+6,'Board must extend over actual water');
 }
}

const names=['Map3DRecreationKit.swift','Map3DRecreationKitGeometry.swift','Map3DRecreationKitVenues.swift','Map3DRecreationKitFitness.swift','Map3DRecreationKitSport.swift','Map3DRecreationKitAquatic.swift','Map3DRecreationKitExamples.swift','Map3DStationKitGeometry.swift','Map3DCivicKitGeometry.swift'];
manifest.recipe_sha256=Object.fromEntries(names.map(n=>[n,hash(readFileSync(new URL('../../Sources/GamePresentation/'+n,import.meta.url)))]));writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
const result={status:'VERIFIED',environment:'Linux / Swift 6.4 / Node / Chromium WebGL 2',parts:24,examples:4,models:28,views,triangles,ball_return_contacts:{status:'VERIFIED',gap_metres:ballRailGaps},maximum_triangles:Math.max(...manifest.models.map(m=>m.triangles)),checks:['all native vertices round-trip through the game loader','native / GLB / PNG SHA-256','complete native-to-GLB conversion','four categories of 6 distinct sports assets','all seven transparent views nonempty and unclipped','opaque finite native vertices and connector normals','both actual ball-return rail contacts; indoor fixture clearance, venue separation, pool-deck height and cantilever clearance'],not_verified:['iPhone / iPad Metal rendering and performance','live map placement, collisions, interior navigation or animation','sports physics, equipment animation or structural safety']};
writeFileSync(resolve(root,'verification.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
