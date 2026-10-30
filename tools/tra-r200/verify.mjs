// Vehicle-specific tests on exported geometry, including actual mutations.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {model,bounds} from '../train-models/native.mjs';
const root=resolve(process.argv[2]);const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const near=model(readFileSync(resolve(root,manifest.models[0].native))).vertices;
const far=model(readFileSync(resolve(root,manifest.models[1].native))).vertices;
const tol=(x,y,t=.0001)=>Math.abs(x-y)<t;
// Orthographic X rays use barycentric coordinates in the YZ plane.
function firstHit(vs,end,y,z){
 let hit=null;
 for(let i=0;i<vs.length;i+=3){
  const t=vs.slice(i,i+3),p=t.map(v=>v.position),a=p[0],b=p[1],c=p[2];
  const det=(b[1]-a[1])*(c[2]-a[2])-(c[1]-a[1])*(b[2]-a[2]);if(Math.abs(det)<1e-10)continue;
  const u=((y-a[1])*(c[2]-a[2])-(c[1]-a[1])*(z-a[2]))/det;
  const v=((b[1]-a[1])*(z-a[2])-(y-a[1])*(b[2]-a[2]))/det;
  if(u<-.00001||v<-.00001||u+v>1.00001)continue;
  const x=a[0]+u*(b[0]-a[0])+v*(c[0]-a[0]);
  if(!hit||x*end>hit.x*end)hit={x,color:t[0].color};
 }
 return hit;
}
function highest(vs,x,y){
 let best=-Infinity;
 for(let i=0;i<vs.length;i+=3){const[a,b,c]=vs.slice(i,i+3).map(v=>v.position);const det=(b[0]-a[0])*(c[1]-a[1])-(c[0]-a[0])*(b[1]-a[1]);if(Math.abs(det)<1e-10)continue;const u=((x-a[0])*(c[1]-a[1])-(c[0]-a[0])*(y-a[1]))/det,v=((b[0]-a[0])*(y-a[1])-(x-a[0])*(b[1]-a[1]))/det;if(u>=0&&v>=0&&u+v<=1)best=Math.max(best,a[2]+u*(b[2]-a[2])+v*(c[2]-a[2]));}
 return best;
}
function check(vs){
 const seen=new Set();
 for(let i=0;i<vs.length;i+=3){const key=vs.slice(i,i+3).map(v=>v.position.map(n=>Math.round(n*1e5)).join(',')).sort().join('|');assert(!seen.has(key),'duplicate triangle / equipment');seen.add(key);}
 const b=bounds(vs);assert(tol(b.minimum[0],-10.005)&&tol(b.maximum[0],10.005),'coupler envelope');assert(tol(b.minimum[2],0)&&tol(b.maximum[2],4.08),'rail/roof envelope');
 for(const x of [2.55,4,5.45])assert(tol(highest(vs,x,.1),4.065,.003),'radiator fan hidden or displaced');
 // Test every intended tyre contact from the final payload. Removing or
 // raising a wheel must fail rather than relying on the overall Z bound.
 for(const c of [-5.9,5.9])for(const dx of [-1.5,0,1.5])for(const side of [-1,1]){
  const contacts=vs.filter(v=>tol(v.position[0],c+dx)&&v.position[1]*side>.47&&v.position[1]*side<.69&&tol(v.position[2],0));assert(contacts.length,'missing wheel or lifted tyre');
 }
 for(const end of [-1,1]){
  for(const y of [-.99,.99]){const h=firstHit(vs,end,y,2.09);assert(h&&h.color[0]>130,'lamp hidden or displaced');}
  for(const y of [-.72,-.38,.38,.72])for(const z of [3.03,3.22,3.40]){
   const h=firstHit(vs,end,y,z);assert(h&&h.color[2]>h.color[0]&&h.color[0]<90,'windshield occluded');
   assert(tol(h.x*end,9.45-(z-2.1)*.39+.042,.002),'windshield surface intersection');
  }
  const glass=vs.filter(v=>v.position[0]*end>8.7&&v.position[2]>2.84&&v.position[2]<3.49&&Math.abs(v.position[1])<1.02);
  assert(glass.length,'cab glass absent');
  const front=glass.filter(v=>Math.abs(v.normal[0])>.5&&v.normal[0]*end>0&&v.color[2]>v.color[0]);
  assert(front.length,'front-facing glass');
  for(const v of front){const[x,y,z]=v.position;const gap=x*end-(9.45-Math.max(0,z-2.1)*.39);assert(gap>.019&&gap<.06,'glass buried or floating');assert(Math.abs(y)<1.04,'glass outside frame');}
 }
 return b;
}
for(const vs of [near,far])check(vs);
assert.throws(()=>check([...near,...structuredClone(near.slice(0,3))]),/duplicate/);
const bad=(mutator,pattern)=>{const v=structuredClone(near);mutator(v);assert.throws(()=>check(v),pattern);};
bad(v=>{for(const a of v)if(tol(a.position[0],4.4)&&Math.abs(a.position[1])>.47&&Math.abs(a.position[1])<.69&&a.position[2]<.01)a.position[2]+=.1;},/wheel/);
bad(v=>{for(const a of v)if(a.position[0]>8.7&&a.position[2]>2.84&&a.position[2]<3.49&&a.color[2]>a.color[0])a.position[0]+=.2;},/glass|windshield/);
bad(v=>{for(const a of v)if(a.position[0]>8.7&&a.position[2]>2.84&&a.position[2]<3.49&&a.color[2]>a.color[0])a.position[0]-=.1;},/glass|windshield/);
bad(v=>{for(const a of v)if(a.position[0]>2&&a.position[0]<6.5&&a.position[2]>4.06)a.position[2]-=.1;},/fan|roof/);
assert(near.length>far.length*2,'far detail budget');
assert.deepEqual(bounds(near),bounds(far),'LOD envelope jump');
writeFileSync(resolve(root,'r200-verification.json'),JSON.stringify({status:'VERIFIED',checks:['12 actual tyre contacts at 6 axle stations','rail/coupler/roof bounds','both end front-facing glass surface gap and 24 first-hit rays','near/far bounds and detail ratio','actual lifted tyre and floating/buried windshield mutations rejected'],limits:['not exhaustive collision detection','door visibility, opposite side fittings and roof BOM require further source/audit','front gap test is not independent ray visibility proof']},null,2)+'\n');
console.log('VERIFIED R200-specific geometry probes');
