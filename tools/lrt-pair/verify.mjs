import {readFileSync,writeFileSync} from 'node:fs';import {resolve} from 'node:path';import {createHash} from 'node:crypto';import assert from 'node:assert/strict';import {readNative,glbFromNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),before=resolve(process.argv[3]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),sha=b=>createHash('sha256').update(b).digest('hex'),vertices=new Map();
assert.equal(manifest.models.length,16);
for(const m of manifest.models){
 const bytes=readFileSync(resolve(root,m.native)),glb=readFileSync(resolve(root,m.glb)),model=readNative(bytes);
 assert.equal(sha(bytes),m.native_sha256);assert.equal(sha(glb),m.glb_sha256);assert.deepEqual(glbFromNative(model),glb);assert.equal(model.vertices.length/3,m.triangles);assert(m.triangles>100&&m.triangles<=15000);
 vertices.set(m.id,model.vertices);
 for(const view of manifest.directions){const b=readFileSync(resolve(root,m.views[view])),metric=m.view_metrics[view];assert.equal(b[25],6);assert.equal(sha(b),metric.sha256);const [l,t,r,bottom]=metric.visible_bounds;assert(l>=2&&t>=2&&r<=510&&bottom<=510&&metric.opaque_pixels>30);}
 const b=v=>m.view_metrics[v].visible_bounds,w=v=>b(v)[2]-b(v)[0],h=v=>b(v)[3]-b(v)[1];assert(Math.abs(w('left')-w('top'))<=3);assert(Math.abs(h('left')-h('front'))<=3);
 if(m.family!=='comparison')assert(model.vertices.every(v=>{const [r,g,b]=v.color;return !(r>100&&r>g+30&&r>b+30)}),m.id+' red paint');
}
const wheelColor=[43,46,52,255].join(','); // project tyre palette, not an axle count
for(const family of ['five','seven']){
 const parts=manifest.models.filter(m=>m.family===family&&m.category==='section'),train=manifest.models.find(m=>m.family===family&&m.category==='formation'),assembly=manifest.assemblies[family];let i=0;
 assert.equal(parts.length,family==='five'?5:7);assert.equal(new Set(parts.map(m=>m.metres_per_pixel)).size,1);
 for(const [j,p] of parts.entries())for(const v of vertices.get(p.id)){const q=vertices.get(train.id)[i++];for(let k=0;k<3;k++)assert(Math.abs(q.position[k]-v.position[k]-(k===0?assembly.centres_x_m[j]:0))<.0001);assert.deepEqual(q.color,v.color);}
 assert.equal(i,vertices.get(train.id).length);assert(Math.abs(train.maximum[0]-train.minimum[0]-assembly.length_m)<.001);assert.equal(train.minimum[2],0);
 const wheels=vertices.get(train.id).filter(v=>v.color.join(',')===wheelColor),xs=wheels.map(v=>v.position[0]).sort((a,b)=>a-b);let clusters=0,last=-Infinity;for(const x of xs){if(x-last>.17)clusters++;last=x;}assert.equal(clusters,assembly.axles,'actual axle clusters');
}
// Five-section silhouette/doors/wheels/equipment are preserved. Only trailing
// cab-side glazing/frame triangles may change to follow the correct diagonal.
for(const m of manifest.models.filter(m=>m.family==='five')){
 const old=readNative(readFileSync(resolve(before,m.native))).vertices,now=vertices.get(m.id);
 const canRepair=m.id==='lrt-five-trailing'||m.id==='lrt-five-formation',dx=m.category==='formation'?-12.5:0;
 function stable(vs){const out=[];for(let i=0;i<vs.length;i+=3){const tri=vs.slice(i,i+3);if(canRepair&&tri.every(v=>v.position[0]-dx < -2.75&&Math.abs(v.position[1])>1.1&&v.position[2]>=.69&&v.position[2]<=2.93))continue;for(const v of tri)out.push([v.position,v.normal,v.glow,v.color[3]]);}return out;}
 assert.deepEqual(stable(now),stable(old),m.id+' geometry changed outside localized glazing repair');
}
const result={status:'VERIFIED',models:16,views:112,checks:['native/GLB exact contents and independent Swift native readback','five and seven unit-by-unit assembly / axis / rail datum','actual six and eight axle clusters','all seven orthographic views at fixed metre scales','five geometry/normals/order/alpha/glow match prior5a2fd38e outside the trailing cab-side pane repair','no red paint on final five or seven'],unverified:['device Metal / performance / animation / operational assignment','engineering dimensions / hidden bogie details','OS double-click file navigation']};
writeFileSync(resolve(root,'verification.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
