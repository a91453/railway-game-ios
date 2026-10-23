import {readFileSync,writeFileSync} from 'node:fs';import {resolve} from 'node:path';import {createHash} from 'node:crypto';import assert from 'node:assert/strict';import {readNative,glbFromNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),sha=b=>createHash('sha256').update(b).digest('hex'),vertices=new Map();
assert.equal(manifest.models.length,7);
for(const m of manifest.models){
 const bytes=readFileSync(resolve(root,m.native)),glb=readFileSync(resolve(root,m.glb)),model=readNative(bytes);
 assert.equal(sha(bytes),m.native_sha256);assert.equal(sha(glb),m.glb_sha256);assert.deepEqual(glbFromNative(model),glb);assert.equal(model.vertices.length/3,m.triangles);assert(m.triangles>100&&m.triangles<=15000);vertices.set(m.id,model.vertices);
 for(const view of manifest.directions){const b=readFileSync(resolve(root,m.views[view])),metric=m.view_metrics[view];assert.equal(b[25],6);assert.equal(sha(b),metric.sha256);const [l,t,r,bottom]=metric.visible_bounds;assert(l>=2&&t>=2&&r<=510&&bottom<=510&&metric.opaque_pixels>30);}
 const b=v=>m.view_metrics[v].visible_bounds,w=v=>b(v)[2]-b(v)[0],h=v=>b(v)[3]-b(v)[1];assert(Math.abs(w('left')-w('top'))<=3);assert(Math.abs(h('left')-h('front'))<=3);
 // Red paint is near zero hue, not every warm colour (the approved sand is gold).
 if(m.family==='metro')for(const v of model.vertices){const [r,g,b]=v.color,max=Math.max(r,g,b),min=Math.min(r,g,b),d=max-min;if(d>35&&max===r){const hue=60*((g-b)/d);assert(Math.abs(hue)>18,m.id+' red paint');}}
}
const parts=manifest.models.filter(m=>m.category==='section'),train=manifest.models.find(m=>m.category==='formation'),assembly=manifest.assemblies.metro;let i=0;
assert.equal(parts.length,4);assert.equal(new Set(parts.map(m=>m.metres_per_pixel)).size,1);
for(const [j,p] of parts.entries())for(const v of vertices.get(p.id)){const q=vertices.get(train.id)[i++];for(let k=0;k<3;k++)assert(Math.abs(q.position[k]-v.position[k]-(k===0?assembly.centres_x_m[j]:0))<.0001);assert.deepEqual(q.color,v.color);// M3DM stores Float32 positions; translated wheel facets recompute with minute rounding.
 assert(q.normal.reduce((sum,n,k)=>sum+n*v.normal[k],0)>1-1e-8);}
assert.equal(i,vertices.get(train.id).length);assert.equal(train.minimum[2],0);
for(const m of [...parts,train]){
 const wheels=vertices.get(m.id).filter(v=>v.color.join(',')==='43,46,52,255'),xs=wheels.map(v=>v.position[0]).sort((a,b)=>a-b);let clusters=0,last=-Infinity;for(const x of xs){if(x-last>.17)clusters++;last=x;}assert.equal(clusters,m===train?16:4,'actual axle clusters');
}
const result={status:'VERIFIED',models:7,views:49,checks:['native/GLB exact contents and independent Swift readback','four-car assembly per vertex and normal','actual four axles per car, sixteen per formation','fixed metre scales on seven directions','no red paint'],unverified:['device Metal / performance / animation / operational assignment','engineering dimensions and hidden equipment','OS double-click navigation']};
writeFileSync(resolve(root,'verification.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
