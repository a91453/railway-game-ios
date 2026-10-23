import{readFileSync,writeFileSync}from'node:fs';import{resolve}from'node:path';import{createHash}from'node:crypto';import assert from'node:assert/strict';import{readNative,glbFromNative}from'../station-kit/package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),sha=b=>createHash('sha256').update(b).digest('hex'),vertices=new Map();
assert.equal(manifest.models.length,5);
for(const m of manifest.models){
 const bytes=readFileSync(resolve(root,m.native)),glb=readFileSync(resolve(root,m.glb)),model=readNative(bytes);
 assert.equal(sha(bytes),m.native_sha256);assert.equal(sha(glb),m.glb_sha256);assert.deepEqual(glbFromNative(model),glb);assert.equal(model.vertices.length/3,m.triangles);assert(m.triangles>100&&m.triangles<=15000);vertices.set(m.id,model.vertices);
 const low=[0,1,2].map(i=>Math.min(...model.vertices.map(v=>v.position[i]))),high=[0,1,2].map(i=>Math.max(...model.vertices.map(v=>v.position[i])));
 for(let i=0;i<3;i++){assert(Math.abs(low[i]-m.minimum[i])<1e-5);assert(Math.abs(high[i]-m.maximum[i])<1e-5);}
 for(const view of manifest.directions){const b=readFileSync(resolve(root,m.views[view])),metric=m.view_metrics[view];assert.equal(b[25],6);assert.equal(sha(b),metric.sha256);const[l,t,r,bottom]=metric.visible_bounds;assert(l>=2&&t>=2&&r<=510&&bottom<=510&&metric.opaque_pixels>30);}
 const b=v=>m.view_metrics[v].visible_bounds,w=v=>b(v)[2]-b(v)[0],h=v=>b(v)[3]-b(v)[1];assert(Math.abs(w('left')-w('top'))<=3);assert(Math.abs(h('left')-h('front'))<=3);
 if(m.family==='steam')for(const v of model.vertices){const[r,g,b]=v.color,max=Math.max(r,g,b),min=Math.min(r,g,b),d=max-min;if(d>35&&max===r)assert(Math.abs(60*((g-b)/d))>18,'red paint');}
}
const parts=manifest.models.filter(m=>m.category==='section'),train=manifest.models.find(m=>m.category==='formation'),assembly=manifest.assemblies.steam;let index=0;assert.equal(parts.length,2);assert.equal(new Set(parts.map(m=>m.metres_per_pixel)).size,1);
let minimumNormalDot=1;
for(const[j,p]of parts.entries())for(const v of vertices.get(p.id)){const q=vertices.get(train.id)[index++];assert.deepEqual(q.position.map(n=>n+0),v.position.map((n,k)=>Math.fround(n+(k===0?Math.fround(assembly.centres_x_m[j]):0))));assert.deepEqual(q.color,v.color);minimumNormalDot=Math.min(minimumNormalDot,q.normal.reduce((s,n,k)=>s+n*v.normal[k],0));}
assert(minimumNormalDot>.9999);assert.equal(index,vertices.get(train.id).length);assert.equal(train.minimum[2],0);
const components=JSON.parse(readFileSync(resolve(root,'components.json'))),couplers=parts.map((m,j)=>{const p=components[m.id].find(p=>p.name===(j===0?'rear-coupler':'tender-coupler-4.02'));const vs=vertices.get(m.id).slice(p.start_triangle*3,(p.start_triangle+p.triangles)*3);return vs.map(v=>v.position[0]+assembly.centres_x_m[j]);});
const couplerGap=Math.min(...couplers[0])-Math.max(...couplers[1]);assert(Math.abs(couplerGap)<1e-5,'assembled couplers separated or penetrated');
const result={status:'VERIFIED',models:5,seven_direction_pngs:35,minimum_translated_normal_dot:minimumNormalDot,coupler_gap_m:couplerGap,checks:['Swift native readback','native/GLB byte-exact conversion','actual metre bounds','two-unit assembly vertices/colors/normals','couplers meet without volume overlap','fixed seven-direction scales','no red paint'],unverified:['real model identification, engineering dimensions, concealed exact axle designation','device Metal, performance, moving rods, animation, operational binding','OS double-click file navigation']};
writeFileSync(resolve(root,'verification.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
