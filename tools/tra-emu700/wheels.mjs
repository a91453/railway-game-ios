// Actual connected solids, not recipe constants alone. Scope: four axles,
// eight tyres at the documented centres and rail plane. No full collision claim.
import assert from 'node:assert/strict';import{readFileSync,writeFileSync}from'node:fs';import{resolve}from'node:path';import{model}from'../train-models/native.mjs';
function components(v){
 const parent=v.map((_,i)=>i),seen=new Map();const find=i=>{while(parent[i]!==i){parent[i]=parent[parent[i]];i=parent[i]}return i};const join=(a,b)=>parent[find(a)]=find(b);
 for(let i=0;i<v.length;i++){const k=v[i].position.map(x=>Math.round(x*1e5)).join(',');if(seen.has(k))join(i,seen.get(k));else seen.set(k,i);join(i,i-i%3)}
 const out=new Map();for(let i=0;i<v.length;i++){const k=find(i);if(!out.has(k))out.set(k,[]);out.get(k).push(i)}return [...out.values()].map(indices=>{const low=[0,1,2].map(a=>Math.min(...indices.map(i=>v[i].position[a]))),high=[0,1,2].map(a=>Math.max(...indices.map(i=>v[i].position[a])));return{indices,low,high,size:high.map((x,a)=>x-low[a]),center:high.map((x,a)=>(x+low[a])/2)}});
}
function tyres(v){return components(v).filter(c=>Math.abs(c.size[0]-.86)<.001&&Math.abs(c.size[1]-.13)<.001&&Math.abs(c.size[2]-.86)<.001)}
function check(v){const w=tyres(v);assert.equal(w.length,8,'eight actual tyre solids');for(const c of w){assert(Math.abs(c.low[2])<.0001,'rail contact');assert(Math.abs(Math.abs(c.center[1])-.6)<.001,'wheel lateral centre');assert([-8.3,-6,6,8.3].some(x=>Math.abs(x-c.center[0])<.001),'axle centre')}return w}
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(root+'/manifest.json')),rows=[];
for(const m of manifest.models.filter(m=>m.native_kind!=='assembly')){
 const vs=model(readFileSync(resolve(root,m.native))).vertices,w=check(vs),chosen=new Set(w[0].indices);
 const lift=vs.map((v,i)=>chosen.has(i)?{...v,position:v.position.map((x,a)=>a===2?x+.1:x)}:v);
 assert.throws(()=>check(lift),/rail/);
 const wrongAxle=vs.map((v,i)=>chosen.has(i)?{...v,position:v.position.map((x,a)=>a===0?x+.2:x)}:v);
 assert.throws(()=>check(wrongAxle),/axle/);
 assert.throws(()=>check(vs.filter((v,i)=>!chosen.has(i))),/eight/);
 rows.push({id:m.id,tyres:w.map(({low,high,center})=>({low,high,center})),actual_tyres_lift_100mm_rejected:true,actual_axle_shift_200mm_rejected:true,actual_missing_tyre_rejected:true});
}
writeFileSync(root+'/wheel-verification.json',JSON.stringify({status:'VERIFIED',models:rows,limits:'Connected tyre solids and documented static centres only; no flanges, worn wheels, full collision, glass, equipment or dynamics proof.'},null,2)+'\n');console.log('VERIFIED',rows.length,'units: eight actual tyres and three mutations each');
